# SPDX-License-Identifier: MIT
function Get-AMDistributionFiles {
    @('project.json','LICENSE','NOTICE.md','Repair.ps1','Background.ps1','Install.ps1','Uninstall.ps1','Launch.vbs','Repair.cmd','Install.cmd','Uninstall.cmd','src\AppleMusicCacheRepair.psm1','src\Core.ps1','src\Repair.ps1','src\Installation.ps1')
}
function Get-AMPowerShell { Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }
function Get-AMLaunchSpec([string]$Directory,[string]$Launcher,[ValidateSet('Repair','Background','Probe')][string]$Mode) {
    if($Launcher -eq 'Vbs'){
        return [pscustomobject]@{Execute=(Join-Path $env:SystemRoot 'System32\wscript.exe');Arguments=('//B //Nologo "'+(Join-Path $Directory 'Launch.vbs')+'" '+$Mode)}
    }
    $file=if($Mode -eq 'Repair'){'Repair.ps1'}else{'Background.ps1'}
    $arguments='-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $Directory $file)+'"'
    if($Mode -eq 'Probe'){$arguments+=' -Probe'}
    [pscustomobject]@{Execute=(Get-AMPowerShell);Arguments=$arguments}
}
function Select-AMLauncher([string]$Directory,[switch]$PowerShellOnly) {
    if($PowerShellOnly){return 'PowerShell'}
    $spec=Get-AMLaunchSpec $Directory 'Vbs' 'Probe'
    $process=$null
    try{
        if(-not (Test-Path -LiteralPath $spec.Execute)){return 'PowerShell'}
        $psi=New-Object Diagnostics.ProcessStartInfo
        $psi.FileName=$spec.Execute;$psi.Arguments=$spec.Arguments;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
        $process=[Diagnostics.Process]::Start($psi)
        if(-not $process.WaitForExit(10000)){$process.Kill();return 'PowerShell'}
        if($process.ExitCode -eq 0){return 'Vbs'}
        return 'PowerShell'
    }catch{return 'PowerShell'}finally{if($process){$process.Dispose()}}
}
function Get-AMTask([string]$Name) {
    # Enumerate successfully; a scheduler failure must not be treated as an absent task.
    @(Get-ScheduledTask -TaskPath '\' -ErrorAction Stop | Where-Object {$_.TaskName -eq $Name}) | Select-Object -First 1
}
function Get-AMTaskXml([string]$Name) { Export-ScheduledTask -TaskName $Name -TaskPath '\' -ErrorAction Stop }
function Disable-AMTask([string]$Name) {
    Disable-ScheduledTask -TaskName $Name -TaskPath '\' -ErrorAction Stop | Out-Null
    Stop-ScheduledTask -TaskName $Name -TaskPath '\' -ErrorAction Stop
}
function Remove-AMTask([string]$Name) { Unregister-ScheduledTask -TaskName $Name -TaskPath '\' -Confirm:$false -ErrorAction Stop }
function Restore-AMTask([string]$Name,[string]$Xml) { Register-ScheduledTask -TaskName $Name -TaskPath '\' -Xml $Xml -Force -ErrorAction Stop | Out-Null }
function Save-AMTask($Config) {
    $spec=Get-AMLaunchSpec $Config.InstallDirectory $Config.Launcher 'Background'
    $action=New-ScheduledTaskAction -Execute $spec.Execute -Argument $spec.Arguments
    $logon=New-ScheduledTaskTrigger -AtLogOn -User $Config.UserSid
    $logon.Delay='PT30S'
    $hourly=New-ScheduledTaskTrigger -Once -At ((Get-Date).AddHours(1)) -RepetitionInterval (New-TimeSpan -Hours 1)
    $triggers=@($logon,$hourly)
    if($Config.ExitTrigger){
        $channel=Get-WinEvent -ListLog 'Microsoft-Windows-AppModel-Runtime/Admin' -ErrorAction Stop
        if(-not $channel.IsEnabled){throw 'The packaged-app exit event channel is disabled.'}
        $class=Get-CimClass -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName 'MSFT_TaskEventTrigger' -ErrorAction Stop
        $trigger=New-CimInstance -CimClass $class -ClientOnly
        $trigger.Enabled=$true;$trigger.Delay='PT5S'
        $trigger.Subscription='<QueryList><Query Id="0" Path="Microsoft-Windows-AppModel-Runtime/Admin"><Select Path="Microsoft-Windows-AppModel-Runtime/Admin">*[System[Provider[@Name=''Microsoft-Windows-AppModel-Runtime''] and EventID=217]]</Select></Query></QueryList>'
        $triggers+=@($trigger)
    }
    $principal=New-ScheduledTaskPrincipal -UserId $Config.UserSid -LogonType Interactive -RunLevel Limited
    $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -MultipleInstances IgnoreNew
    $description='AMCacheRepair:'+ $Config.InstallationId+'; setupCert cache only; no process termination; logs in install-directory/data.'
    Register-ScheduledTask -TaskName $Config.TaskName -TaskPath '\' -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Description $description -Force -ErrorAction Stop | Out-Null
}
function Test-AMTaskOwned($Task,$Config) {
    if(-not $Task -or -not $Config){return $false}
    $spec=Get-AMLaunchSpec $Config.InstallDirectory $Config.Launcher 'Background'
    $principal=[string]$Task.Principal.UserId
    if($principal -notmatch '^S-1-'){
        try{$principal=(New-Object Security.Principal.NTAccount($principal)).Translate([Security.Principal.SecurityIdentifier]).Value}catch{return $false}
    }
    $actions=@($Task.Actions)
    $Task.TaskName -eq $Config.TaskName -and $principal -eq $Config.UserSid -and
        ([string]$Task.Principal.LogonType -in @('Interactive','InteractiveToken')) -and
        ([string]$Task.Principal.RunLevel -in @('Limited','LUA')) -and
        $Task.Description.StartsWith(('AMCacheRepair:'+$Config.InstallationId+';'),[StringComparison]::Ordinal) -and
        $actions.Count -eq 1 -and $actions[0].Execute -eq $spec.Execute -and $actions[0].Arguments -ceq $spec.Arguments
}
function Get-AMShortcut([string]$Path) {
    if(-not (Test-Path -LiteralPath $Path)){return $null}
    Assert-AMPlainPath $Path
    $shell=New-Object -ComObject WScript.Shell
    $link=$shell.CreateShortcut($Path)
    [pscustomobject]@{Target=$link.TargetPath;Arguments=$link.Arguments;WorkingDirectory=$link.WorkingDirectory}
}
function Test-AMShortcutOwned($Shortcut,$Config) {
    if(-not $Shortcut -or -not $Config){return $false}
    $spec=Get-AMLaunchSpec $Config.InstallDirectory $Config.Launcher 'Repair'
    $Shortcut.Target -eq $spec.Execute -and $Shortcut.Arguments -ceq $spec.Arguments -and $Shortcut.WorkingDirectory -eq $Config.InstallDirectory
}
function Save-AMShortcut($Config) {
    Assert-AMPlainPath $Config.ShortcutPath -AllowMissing
    $spec=Get-AMLaunchSpec $Config.InstallDirectory $Config.Launcher 'Repair'
    $shell=New-Object -ComObject WScript.Shell
    $link=$shell.CreateShortcut($Config.ShortcutPath)
    $link.TargetPath=$spec.Execute;$link.Arguments=$spec.Arguments;$link.WorkingDirectory=$Config.InstallDirectory
    $link.Description='Apple Music setupCert cache repair; backup before removal.'
    $link.IconLocation=(Join-Path $env:SystemRoot 'System32\shell32.dll')+',138'
    $link.WindowStyle=7;$link.Save()
}
function Remove-AMShortcut([string]$Path) { Assert-AMPlainPath $Path;Remove-Item -LiteralPath $Path -Force -ErrorAction Stop }
function Read-AMConfig([string]$Directory) {
    $path=Join-Path $Directory 'install.json'
    Assert-AMPlainPath $path -AllowMissing
    if(-not (Test-Path -LiteralPath $path)){return $null}
    $config=Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if($config.Project -ne $script:AMProject -or $config.SchemaVersion -ne 1 -or $config.UserSid -ne (Get-AMIdentity) -or $config.InstallDirectory -ne $Directory){throw 'Installation metadata does not match this directory and current user.'}
    $guid=[guid]::Empty
    if(-not [guid]::TryParse($config.InstallationId,[ref]$guid)){throw 'Invalid installation identity.'}
    if($config.TaskName -ne ('Apple Music Cache Repair - '+$config.UserSid) -or $config.Launcher -notin @('Vbs','PowerShell')){throw 'Invalid installation task metadata.'}
    $expectedShortcut=Join-Path (Get-AMDesktop) 'Apple Music Cache Repair.lnk'
    if($config.ShortcutPath -ne $expectedShortcut){throw 'Installation shortcut location changed; review it before updating.'}
    $config
}
function Write-AMConfig($Config) {
    $path=Join-Path $Config.InstallDirectory 'install.json'
    Assert-AMPlainPath $path -AllowMissing
    $Config|ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path -Encoding UTF8 -ErrorAction Stop
}
function Invoke-AMInstall([string]$SourceDirectory,[string]$InstallDirectory,[switch]$Automatic,[switch]$DisableAutomatic,[switch]$ExitTrigger,[switch]$NoDesktopShortcut,[switch]$PowerShellOnly) {
    $ErrorActionPreference='Stop'
    if($Automatic -and $DisableAutomatic){throw 'Automatic and DisableAutomatic are mutually exclusive.'}
    if($ExitTrigger -and $DisableAutomatic){throw 'ExitTrigger requires automatic cleanup.'}
    $source=Get-AMFullPath $SourceDirectory
    if(-not $InstallDirectory){$InstallDirectory=Get-AMDefaultInstallDirectory}
    $directory=(Get-AMFullPath $InstallDirectory).TrimEnd('\')
    if($directory -eq (Get-AMFullPath ([IO.Path]::GetPathRoot($directory))).TrimEnd('\')){throw 'Cannot install into a drive root.'}
    Assert-AMPlainPath $directory -AllowMissing
    Assert-AMPlainPath $source
    $files=Get-AMDistributionFiles
    foreach($relative in $files){Assert-AMPlainPath (Join-Path $source $relative)}
    $version=(Get-Content -LiteralPath (Join-Path $source 'project.json') -Raw|ConvertFrom-Json).version
    if($version -notmatch '^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$'){throw 'Invalid release version.'}
    $oldConfig=Read-AMConfig $directory
    if((Test-Path -LiteralPath $directory) -and -not $oldConfig -and @(Get-ChildItem -LiteralPath $directory -Force).Count){throw 'Destination is not an empty directory or an existing installation.'}
    $sid=Get-AMIdentity
    $taskName='Apple Music Cache Repair - '+$sid
    $oldTask=Get-AMTask $taskName
    if($oldTask -and -not (Test-AMTaskOwned $oldTask $oldConfig)){throw 'A task with this name belongs to another installation; no task was changed.'}
    $shortcutPath=Join-Path (Get-AMDesktop) 'Apple Music Cache Repair.lnk'
    $oldShortcut=Get-AMShortcut $shortcutPath
    if($oldShortcut -and -not (Test-AMShortcutOwned $oldShortcut $oldConfig)){throw 'Desktop shortcut belongs to another installation; no files were changed.'}
    $enabled=[bool]($Automatic -or $ExitTrigger -or ($oldConfig -and $oldConfig.Automatic))
    if($DisableAutomatic){$enabled=$false}
    $events=[bool]($ExitTrigger -or ($oldConfig -and $oldConfig.ExitTrigger -and $enabled))
    $installationId=if($oldConfig){$oldConfig.InstallationId}else{[guid]::NewGuid().ToString()}
    $config=[pscustomobject][ordered]@{Project=$script:AMProject;SchemaVersion=1;Version=$version;InstallationId=$installationId;UserSid=$sid;InstallDirectory=$directory;TaskName=$taskName;Automatic=$enabled;ExitTrigger=$events;DesktopShortcut=(-not $NoDesktopShortcut);ShortcutPath=$shortcutPath;Launcher='PowerShell'}
    $snapshots=@{};$taskXml=$null;$taskTouched=$false;$shortcutTouched=$false;$shortcutBytes=$null;$createdDirectories=@()
    if($oldTask){$taskXml=Get-AMTaskXml $taskName}
    if($oldShortcut){$shortcutBytes=[IO.File]::ReadAllBytes($shortcutPath)}
    $targets=@($files)+@('install.json')
    foreach($relative in $targets){
        $target=Join-Path $directory $relative
        Assert-AMPlainPath $target -AllowMissing
        # Assign directly so PowerShell does not collapse a zero-byte array to null.
        if(Test-Path -LiteralPath $target){$snapshots[$relative]=[IO.File]::ReadAllBytes($target)}else{$snapshots[$relative]=$null}
    }
    try{
        if($oldTask){$taskTouched=$true;Disable-AMTask $taskName}
        if(-not (Test-Path -LiteralPath $directory)){$createdDirectories+=@($directory);New-Item -ItemType Directory -Path $directory | Out-Null}
        foreach($relative in $files){
            $from=Join-Path $source $relative;$target=Join-Path $directory $relative
            $parent=Split-Path -Parent $target
            if(-not (Test-Path -LiteralPath $parent)){$createdDirectories+=@($parent);New-Item -ItemType Directory -Path $parent | Out-Null}
            Assert-AMPlainPath $target -AllowMissing
            if($from -ne $target){[IO.File]::WriteAllBytes($target,[IO.File]::ReadAllBytes($from))}
            if((Get-FileHash -LiteralPath $from).Hash -ne (Get-FileHash -LiteralPath $target).Hash){throw 'Installed source hash verification failed.'}
        }
        $dataDirectory=Join-Path $directory 'data'
        if(-not (Test-Path -LiteralPath $dataDirectory)){$createdDirectories+=@($dataDirectory)}
        [void](Initialize-AMData $dataDirectory)
        $config.Launcher=Select-AMLauncher $directory -PowerShellOnly:$PowerShellOnly
        Write-AMConfig $config
        if($enabled){
            $taskTouched=$true;Save-AMTask $config
            if(-not (Test-AMTaskOwned (Get-AMTask $taskName) $config)){throw 'Installed task definition verification failed.'}
        }elseif($oldTask){$taskTouched=$true;Remove-AMTask $taskName}
        if(-not $NoDesktopShortcut){
            $shortcutTouched=$true;Save-AMShortcut $config
            if(-not (Test-AMShortcutOwned (Get-AMShortcut $shortcutPath) $config)){throw 'Installed shortcut verification failed.'}
        }elseif($oldShortcut){$shortcutTouched=$true;Remove-AMShortcut $shortcutPath}
        [pscustomobject]@{Status='Installed';Version=$version;Directory=$directory;Automatic=$enabled;ExitTrigger=$events;Launcher=$config.Launcher;TaskName=$taskName;Shortcut=if($config.DesktopShortcut){$shortcutPath}else{$null}}
    }catch{
        $failure=$_.Exception.Message;$rollbackErrors=@()
        foreach($relative in $targets){
            try{
                $target=Join-Path $directory $relative
                Assert-AMPlainPath $target -AllowMissing
                if($null -ne $snapshots[$relative]){[IO.File]::WriteAllBytes($target,[byte[]]$snapshots[$relative])}
                elseif(Test-Path -LiteralPath $target){Remove-Item -LiteralPath $target -Force -ErrorAction Stop}
            }catch{$rollbackErrors+=@($_.Exception.Message)}
        }
        if($taskTouched){try{if($taskXml){Restore-AMTask $taskName $taskXml}elseif(Get-AMTask $taskName){Remove-AMTask $taskName}}catch{$rollbackErrors+=@($_.Exception.Message)}}
        if($shortcutTouched){try{if($null -ne $shortcutBytes){[IO.File]::WriteAllBytes($shortcutPath,$shortcutBytes)}elseif(Test-Path -LiteralPath $shortcutPath){Remove-AMShortcut $shortcutPath}}catch{$rollbackErrors+=@($_.Exception.Message)}}
        # Only remove empty directories created by this attempt, never recurse into data.
        foreach($created in @($createdDirectories|Sort-Object {$_.Length} -Descending|Select-Object -Unique)){
            try{if((Test-AMWithin $created $directory -AllowRoot) -and (Test-Path -LiteralPath $created)){Assert-AMPlainPath $created;if(@(Get-ChildItem -LiteralPath $created -Force).Count -eq 0){[IO.Directory]::Delete($created,$false)}}}catch{$rollbackErrors+=@($_.Exception.Message)}
        }
        if($rollbackErrors.Count){throw ('Install failed: '+$failure+'. Rollback incomplete: '+($rollbackErrors -join '; '))}
        throw ('Install failed; previous files, task and shortcut restored: '+$failure)
    }
}
function Invoke-AMUninstall([string]$InstallDirectory) {
    $ErrorActionPreference='Stop'
    if(-not $InstallDirectory){$InstallDirectory=Get-AMDefaultInstallDirectory}
    $directory=(Get-AMFullPath $InstallDirectory).TrimEnd('\')
    $config=Read-AMConfig $directory
    if(-not $config){throw 'No installation metadata found; no task was removed.'}
    $task=Get-AMTask $config.TaskName
    if($task -and -not (Test-AMTaskOwned $task $config)){throw 'Task ownership check failed; no task was removed.'}
    $shortcut=Get-AMShortcut $config.ShortcutPath
    if($shortcut -and -not (Test-AMShortcutOwned $shortcut $config)){throw 'Shortcut ownership check failed; no shortcut was removed.'}
    $xml=if($task){Get-AMTaskXml $config.TaskName}else{$null}
    $oldConfigBytes=[IO.File]::ReadAllBytes((Join-Path $directory 'install.json'))
    $oldShortcutBytes=if($shortcut){[IO.File]::ReadAllBytes($config.ShortcutPath)}else{$null}
    try{
        if($task){Disable-AMTask $config.TaskName;Remove-AMTask $config.TaskName}
        if($shortcut){Remove-AMShortcut $config.ShortcutPath}
        $config.Automatic=$false;$config.ExitTrigger=$false;$config.DesktopShortcut=$false
        Write-AMConfig $config
        [pscustomobject]@{Status='Uninstalled';Directory=$directory;Retained='Scripts, logs and certificate backups. Remove the directory manually when no longer needed.'}
    }catch{
        $failure=$_.Exception.Message;$errors=@()
        try{[IO.File]::WriteAllBytes((Join-Path $directory 'install.json'),$oldConfigBytes)}catch{$errors+=@($_.Exception.Message)}
        if($xml){try{Restore-AMTask $config.TaskName $xml}catch{$errors+=@($_.Exception.Message)}}
        if($null -ne $oldShortcutBytes){try{[IO.File]::WriteAllBytes($config.ShortcutPath,$oldShortcutBytes)}catch{$errors+=@($_.Exception.Message)}}
        if($errors.Count){throw ('Uninstall failed: '+$failure+'. Rollback incomplete: '+($errors -join '; '))}
        throw ('Uninstall failed; original configuration restored: '+$failure)
    }
}
function Invoke-AMInstallationLock([scriptblock]$Operation) {
    $held=@()
    try{
        $sid=Get-AMIdentity
        foreach($kind in @('Installation','Manual','Cleanup')){
            $mutex=New-Object Threading.Mutex($false,('Local\AppleMusicCacheRepair-'+$kind+'-'+$sid))
            $owns=$false
            try{try{$owns=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owns=$true};if(-not $owns){throw 'Repair or installation is active; retry after it completes.'};$held+=@($mutex)}
            catch{if(-not $owns){$mutex.Dispose()};throw}
        }
        & $Operation
    }finally{for($index=$held.Count-1;$index -ge 0;$index--){$held[$index].ReleaseMutex();$held[$index].Dispose()}}
}
function Install-AMRepair([string]$SourceDirectory,[string]$InstallDirectory,[switch]$Automatic,[switch]$DisableAutomatic,[switch]$ExitTrigger,[switch]$NoDesktopShortcut,[switch]$PowerShellOnly) {
    $arguments=$PSBoundParameters
    Invoke-AMInstallationLock {Invoke-AMInstall @arguments}
}
function Uninstall-AMRepair([string]$InstallDirectory) {
    Invoke-AMInstallationLock {Invoke-AMUninstall -InstallDirectory $InstallDirectory}
}
