# SPDX-License-Identifier: MIT
function Get-AMAppInfo {
    $packages=@(Get-AppxPackage -Name AppleInc.AppleMusicWin -ErrorAction Stop | Where-Object {$_.PackageFamilyName -eq $script:AMFamily})
    if($packages.Count -ne 1){throw 'Apple Music is not registered for the current user.'}
    $package=$packages[0]
    $manifest=Get-AppxPackageManifest -Package $package.PackageFullName -ErrorAction Stop
    $apps=@($manifest.Package.Applications.Application)
    $main=@($apps | Where-Object {$_.Executable -match '(?i)(^|[\\/])AppleMusic\.exe$'})
    if($main.Count -eq 1){$appId=[string]$main[0].Id}
    elseif($apps.Count -eq 1){$appId=[string]$apps[0].Id}
    else{throw 'Cannot identify the Apple Music launch entry.'}
    [pscustomobject]@{InstallLocation=(Get-AMFullPath $package.InstallLocation);AppUserModelId=($script:AMFamily+'!'+$appId)}
}
function Get-AMSession { (Get-Process -Id $PID -ErrorAction Stop).SessionId }
function Assert-AMAppProcess($Process,$App) {
    if($Process.SessionId -ne (Get-AMSession)){throw 'Refusing to close a process in another session.'}
    if($Process.ProcessName -notmatch '^(AppleMusic|AMPLibraryAgent)$'){throw 'Unexpected process name.'}
    if(-not $Process.Path -or -not (Test-AMWithin $Process.Path $App.InstallLocation)){throw 'Cannot verify the Apple Music process executable.'}
}
function Request-AMClose($Process,$App) {
    Assert-AMAppProcess $Process $App
    if($Process.MainWindowHandle -ne 0){[void]$Process.CloseMainWindow()}
}
function Stop-AMVerifiedProcess($Process,$App) {
    $fresh=Get-Process -Id $Process.Id -ErrorAction SilentlyContinue
    if(-not $fresh){return}
    Assert-AMAppProcess $fresh $App
    if($fresh.StartTime -ne $Process.StartTime){throw 'Process identity changed; refusing to stop it.'}
    Stop-Process -Id $fresh.Id -ErrorAction Stop
}
function Start-AMApp($App) {
    Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList ('shell:AppsFolder\'+$App.AppUserModelId) -ErrorAction Stop | Out-Null
}
function Invoke-AMRepair([string]$DataDirectory,[switch]$Preview,[switch]$ForceClose,[switch]$NoRelaunch,[switch]$CheckOnly,[ValidateRange(0,60)][int]$CloseTimeoutSeconds=12) {
    if($Preview){return Invoke-AMCleanup -DataDirectory $DataDirectory -Preview}
    $mutex=$null;$owns=$false
    try{
        $sid=Get-AMIdentity
        $mutex=New-Object Threading.Mutex($false,('Local\AppleMusicCacheRepair-Manual-'+$sid))
        try{$owns=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owns=$true}
        if(-not $owns){return (New-AMResult 'Busy' 4 'Another manual repair is running.' ([guid]::NewGuid().ToString('N')))}
        $app=Get-AMAppInfo
        $context=Resolve-AMCacheContext (Get-AMLocalAppData) $sid
        if(-not $context.Exists){return (New-AMResult 'MissingCache' 2 'Apple Music cache is missing or inaccessible.' ([guid]::NewGuid().ToString('N')))}
        if($CheckOnly){return (New-AMResult 'CheckPassed' 0 'Apple Music registration and cache location are available.' ([guid]::NewGuid().ToString('N')))}
        $session=Get-AMSession
        $processes=@(Get-AMMusicProcesses | Where-Object {$_.SessionId -eq $session})
        # Verify every candidate before requesting any shutdown.
        foreach($process in $processes){Assert-AMAppProcess $process $app}
        foreach($process in $processes){Request-AMClose $process $app}
        $deadline=(Get-Date).AddSeconds($CloseTimeoutSeconds)
        while(@(Get-AMMusicProcesses | Where-Object {$_.SessionId -eq $session}).Count -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 250}
        $remaining=@(Get-AMMusicProcesses | Where-Object {$_.SessionId -eq $session})
        if($remaining.Count -and $ForceClose){
            foreach($process in $remaining){Stop-AMVerifiedProcess $process $app}
            $deadline=(Get-Date).AddSeconds(5)
            while(@(Get-AMMusicProcesses | Where-Object {$_.SessionId -eq $session}).Count -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 250}
        }
        # Includes other sessions: cache is per user, so never mutate while any agent is active.
        if(@(Get-AMMusicProcesses).Count){return (New-AMResult 'Running' 3 'Apple Music is still running. Close it fully or explicitly select Force Close.' ([guid]::NewGuid().ToString('N')))}
        $result=$null
        for($attempt=0;$attempt -lt 6;$attempt++){
            $result=Invoke-AMCleanup -DataDirectory $DataDirectory
            if($result.Status -ne 'Busy'){break}
            Start-Sleep -Milliseconds 250
        }
        if($result.Code -eq 0 -and -not $NoRelaunch){
            try{
                Start-AMApp $app
                $result.Relaunch='Requested'
                $deadline=(Get-Date).AddSeconds(5)
                do{
                    $started=@(Get-AMMusicProcesses | Where-Object {$_.ProcessName -eq 'AppleMusic' -and $_.SessionId -eq $session})
                    if($started.Count){$result.Relaunch='Observed';break}
                    Start-Sleep -Milliseconds 250
                }while((Get-Date) -lt $deadline)
            }catch{$result.Relaunch='Failed';$result.Message+=' Cache cleanup completed, but Apple Music could not be reopened.'}
        }
        $result
    }catch{New-AMResult 'Error' 1 $_.Exception.Message ([guid]::NewGuid().ToString('N'))}
    finally{if($owns){$mutex.ReleaseMutex()};if($mutex){$mutex.Dispose()}}
}
