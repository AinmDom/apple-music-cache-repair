# SPDX-License-Identifier: MIT
[CmdletBinding()]
param([string]$WorkRoot,[string]$ReportPath)
$ErrorActionPreference='Stop'
$repository=Split-Path $PSScriptRoot -Parent
if(-not $WorkRoot){$WorkRoot=Join-Path ([IO.Path]::GetTempPath()) ('AMCacheRepair.Tests-'+[guid]::NewGuid().ToString('N'))}
$WorkRoot=[IO.Path]::GetFullPath($WorkRoot)
if(Test-Path -LiteralPath $WorkRoot){throw 'Test work directory must be new.'}
New-Item -ItemType Directory -Path $WorkRoot | Out-Null
Import-Module (Join-Path $repository 'src\AppleMusicCacheRepair.psm1') -Force
$module=Get-Module AppleMusicCacheRepair
$report=& $module {
    param($Repository,$Work)
    $script:TestResults=New-Object 'System.Collections.Generic.List[object]'
    $script:Case=0
    $script:TestSidSeed=Get-Random -Minimum 10000 -Maximum 2000000000
    function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message}}
    function Assert-Throws([scriptblock]$Action,[string]$Pattern='.'){
        $caught=$null;try{& $Action|Out-Null}catch{$caught=$_}
        Assert ($null -ne $caught) 'Expected an exception.'
        Assert ($caught.Exception.Message -match $Pattern) ('Unexpected error: '+$caught.Exception.Message)
    }
    function Test([string]$Name,[scriptblock]$Action){
        try{& $Action;$script:TestResults.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=$null});Write-Host ('PASS '+$Name)}
        catch{$script:TestResults.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message});Write-Host ('FAIL '+$Name+': '+$_.Exception.Message) -ForegroundColor Red}
    }
    function New-Fixture {
        $script:Case++
        $root=Join-Path $Work ('case-'+$script:Case+' 中文 space')
        $local=Join-Path $root 'Local'
        $cache=Join-Path $local ('Packages\'+$script:AMFamily+'\AC\INetCache')
        $data=Join-Path $root 'data'
        $desktop=Join-Path $root 'Desktop'
        $app=Join-Path $root 'WindowsApps\AppleMusic'
        foreach($dir in @($cache,$data,$desktop,$app)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
        $script:State=@{Root=$root;Local=$local;Cache=$cache;Data=$data;Desktop=$desktop;App=$app;Sid=('S-1-5-21-100-200-'+$script:TestSidSeed+'-'+$script:Case);Processes=@();Task=$null;Closed=0;Forced=0;Started=0;Graceful=$false;FailTask=$false;FailShortcut=$false;FailRemoveShortcut=$false;FailWriteConfig=$false;FailProcesses=$false;FailLaunch=$false;Launcher='PowerShell';TaskWrites=0;GrowCache=$false;ChangeDuringManifest='';ChangePath=$null}
    }
    function script:Get-AMIdentity {$script:State.Sid}
    function script:Get-AMLocalAppData {$script:State.Local}
    function script:Get-AMDesktop {$script:State.Desktop}
    function script:Get-AMMusicProcesses {if($script:State.FailProcesses){throw 'process enumeration failed'};@($script:State.Processes)}
    $script:RealGetCacheFiles=${function:Get-AMCacheFiles}
    function script:Get-AMCacheFiles($Context){
        $entries=@(& $script:RealGetCacheFiles $Context)
        if($script:State.GrowCache -and $entries.Count){
            $null=$entries[0].Length
            [IO.File]::WriteAllBytes($entries[0].FullName,(New-Object byte[] 1048577))
        }
        $entries
    }
    function script:Add-Content {
        [CmdletBinding()]
        param([string]$LiteralPath,[object]$Value,[string]$Encoding)
        Microsoft.PowerShell.Management\Add-Content @PSBoundParameters
        if((Split-Path -Leaf $LiteralPath) -eq 'backup-manifest.jsonl'){
            switch($script:State.ChangeDuringManifest){
                'Cache' {[IO.File]::WriteAllText($script:State.ChangePath,'NEW CACHE')}
                'Backup' {[IO.File]::WriteAllText($script:State.ChangePath,'CORRUPT BACKUP')}
                'Process' {$script:State.Processes=@((New-TestProcess))}
            }
        }
    }
    function script:Get-AMSession {7}
    function script:Get-AMAppInfo {[pscustomobject]@{InstallLocation=$script:State.App;AppUserModelId=($script:AMFamily+'!Example')}}
    function script:Request-AMClose($Process,$App){Assert-AMAppProcess $Process $App;$script:State.Closed++;if($script:State.Graceful){$script:State.Processes=@()}}
    function script:Stop-AMVerifiedProcess($Process,$App){Assert-AMAppProcess $Process $App;$script:State.Forced++;$script:State.Processes=@($script:State.Processes|Where-Object {$_.Id -ne $Process.Id})}
    function script:Start-AMApp($App){if($script:State.FailLaunch){throw 'launch failed'};$script:State.Started++;$script:State.Processes=@((New-TestProcess))}
    function New-TestProcess([string]$Name='AppleMusic',[int]$Session=7,[string]$Path){if(-not $Path){$Path=Join-Path $script:State.App ($Name+'.exe')};[pscustomobject]@{Id=12345;ProcessName=$Name;SessionId=$Session;Path=$Path;MainWindowHandle=1;StartTime=(Get-Date)}}
    function script:Select-AMLauncher([string]$Directory,[switch]$PowerShellOnly){if($PowerShellOnly){'PowerShell'}else{$script:State.Launcher}}
    function script:Get-AMTask([string]$Name){$script:State.Task}
    function script:Get-AMTaskXml([string]$Name){$script:State.Task|ConvertTo-Json -Depth 6}
    function script:Disable-AMTask([string]$Name){$script:State.Task.Enabled=$false}
    function script:Remove-AMTask([string]$Name){$script:State.Task=$null}
    function script:Restore-AMTask([string]$Name,[string]$Xml){$script:State.Task=$Xml|ConvertFrom-Json}
    function script:Save-AMTask($Config){
        $spec=Get-AMLaunchSpec $Config.InstallDirectory $Config.Launcher 'Background'
        $script:State.Task=[pscustomobject]@{TaskName=$Config.TaskName;Description=('AMCacheRepair:'+$Config.InstallationId+'; test');Principal=[pscustomobject]@{UserId=$Config.UserSid;LogonType='Interactive';RunLevel='Limited'};Actions=@([pscustomobject]@{Execute=$spec.Execute;Arguments=$spec.Arguments});Enabled=$true;ExitTrigger=$Config.ExitTrigger}
        $script:State.TaskWrites++
        if($script:State.FailTask){throw 'injected task registration failure'}
    }
    function script:Get-AMShortcut([string]$Path){if(Test-Path -LiteralPath $Path){Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json}}
    function script:Save-AMShortcut($Config){
        $spec=Get-AMLaunchSpec $Config.InstallDirectory $Config.Launcher 'Repair'
        [pscustomobject]@{Target=$spec.Execute;Arguments=$spec.Arguments;WorkingDirectory=$Config.InstallDirectory}|ConvertTo-Json|Set-Content -LiteralPath $Config.ShortcutPath -Encoding UTF8
        if($script:State.FailShortcut){throw 'injected shortcut failure'}
    }
    function script:Remove-AMShortcut([string]$Path){if($script:State.FailRemoveShortcut){throw 'injected shortcut removal failure'};Remove-Item -LiteralPath $Path -Force}
    $script:RealWriteConfig=${function:Write-AMConfig}
    function script:Write-AMConfig($Config){if($script:State.FailWriteConfig){throw 'injected configuration write failure'};& $script:RealWriteConfig $Config}
    function Add-Certificate([string]$Name='setupCert[1].xml',[byte[]]$Bytes=@(31,139,8,0,1,2)){
        $folder=Join-Path $script:State.Cache 'random'
        if(-not(Test-Path -LiteralPath $folder)){New-Item -ItemType Directory -Path $folder|Out-Null}
        $file=Join-Path $folder $Name
        [IO.File]::WriteAllBytes($file,$Bytes)
        $file
    }
    function Invoke-Cleanup([switch]$Preview){Invoke-AMCleanup -DataDirectory $script:State.Data -Preview:$Preview}
    function Install-Test([switch]$Automatic,[switch]$ExitTrigger,[switch]$NoDesktopShortcut,[switch]$DisableAutomatic){Install-AMRepair -SourceDirectory $Repository -InstallDirectory (Join-Path $script:State.Root 'Installed 工具') -Automatic:$Automatic -ExitTrigger:$ExitTrigger -NoDesktopShortcut:$NoDesktopShortcut -DisableAutomatic:$DisableAutomatic}
    Test 'Preview preserves exact cache and reports file kind' {
        New-Fixture;$file=Add-Certificate;$r=Invoke-Cleanup -Preview
        Assert ($r.Code -eq 0 -and $r.Status -eq 'Preview' -and $r.Files[0].Kind -eq 'gzip' -and (Test-Path -LiteralPath $file)) 'Preview changed cache or failed.'
        Assert (-not(Test-Path -LiteralPath (Join-Path $script:State.Data 'certificate-backups'))) 'Preview created a backup.'
    }
    Test 'Exact cache is deleted only after matching backup hash' {
        New-Fixture;$file=Add-Certificate;$hash=(Get-FileHash -LiteralPath $file).Hash;$r=Invoke-Cleanup
        $backup=Join-Path $script:State.Data ('certificate-backups\'+$hash+'.bak')
        Assert ($r.Code -eq 0 -and $r.Count -eq 1 -and -not(Test-Path -LiteralPath $file)) 'Cache was not removed.'
        Assert ((Get-FileHash -LiteralPath $backup).Hash -eq $hash) 'Backup differs.'
    }
    Test 'Backups use relative paths and per-run identifiers' {
        New-Fixture;$null=Add-Certificate;$r=Invoke-Cleanup;$row=Get-Content -LiteralPath (Join-Path $script:State.Data 'backup-manifest.jsonl')|ConvertFrom-Json
        Assert ($row.RunId -eq $r.RunId -and -not [IO.Path]::IsPathRooted($row.RelativePath)) 'Manifest exposes absolute cache path or wrong run.'
    }
    Test 'Unrelated files and renamed certificates are retained' {
        New-Fixture
        $names=@('setupCertNotes.xml','setupCert[1].xml.bak','setupCert[1].xml.old','song.m4a','data','settings.dat','setupCert[-1].xml','setupCert[].xml')
        $files=@($names|ForEach-Object {Add-Certificate $_})
        $r=Invoke-Cleanup
        Assert ($r.Status -eq 'NoMatch') 'Broad certificate pattern matched.'
        foreach($file in $files){Assert (Test-Path -LiteralPath $file) 'Unrelated file removed.'}
    }
    Test 'Plain plist and zero-byte cache are supported' {
        New-Fixture;$null=Add-Certificate 'setupCert.plist' ([Text.Encoding]::UTF8.GetBytes('<?xml?><plist/>'));$null=Add-Certificate 'setupCert[2].xml' ([byte[]]@());$r=Invoke-Cleanup
        Assert ($r.Code -eq 0 -and $r.Count -eq 2 -and @($r.Files|Where-Object {$_.Kind -eq 'empty'}).Count -eq 1) 'Plain/empty handling failed.'
    }
    Test 'Case-insensitive exact certificate filenames are supported' {New-Fixture;$null=Add-Certificate 'SETUPCERT[23].XML';$r=Invoke-Cleanup;Assert ($r.Count -eq 1) 'Filename case broke matching.'}
    Test 'Oversize certificate fails without deleting original' {New-Fixture;$file=Add-Certificate 'setupCert.xml' (New-Object byte[] 1048577);$r=Invoke-Cleanup;Assert ($r.Code -eq 1 -and(Test-Path -LiteralPath $file)) 'Oversize cache was removed.'}
    Test 'Cache growth after enumeration still obeys the size limit' {
        New-Fixture;$file=Add-Certificate;$script:State.GrowCache=$true;$r=Invoke-Cleanup
        Assert ($r.Code -eq 1 -and(Test-Path -LiteralPath $file)) 'Stale file metadata bypassed the size limit.'
    }
    Test 'Cache changed during manifest write is retained' {
        New-Fixture;$file=Add-Certificate;$script:State.ChangeDuringManifest='Cache';$script:State.ChangePath=$file;$r=Invoke-Cleanup
        Assert ($r.Code -eq 1 -and(Test-Path -LiteralPath $file) -and [IO.File]::ReadAllText($file) -eq 'NEW CACHE') 'Changed cache was deleted without a matching backup.'
    }
    Test 'Backup corrupted during manifest write blocks deletion' {
        New-Fixture;$file=Add-Certificate;$hash=(Get-FileHash -LiteralPath $file).Hash;$script:State.ChangeDuringManifest='Backup';$script:State.ChangePath=Join-Path $script:State.Data ('certificate-backups\'+$hash+'.bak');$r=Invoke-Cleanup
        Assert ($r.Code -eq 1 -and(Test-Path -LiteralPath $file)) 'Cache was deleted after its backup became corrupt.'
    }
    Test 'App started during manifest write blocks deletion' {
        New-Fixture;$file=Add-Certificate;$script:State.ChangeDuringManifest='Process';$r=Invoke-Cleanup
        Assert ($r.Code -eq 1 -and(Test-Path -LiteralPath $file)) 'Cache was deleted after the application started.'
    }
    Test 'Corrupt existing backup prevents deletion' {
        New-Fixture;$file=Add-Certificate;$hash=(Get-FileHash -LiteralPath $file).Hash;$dir=Join-Path $script:State.Data 'certificate-backups';New-Item -ItemType Directory -Path $dir|Out-Null;[IO.File]::WriteAllText((Join-Path $dir ($hash+'.bak')),'bad');$r=Invoke-Cleanup
        Assert ($r.Code -eq 1 -and(Test-Path -LiteralPath $file)) 'Corrupt backup did not block deletion.'
    }
    Test 'Running app returns Running without mutation' {New-Fixture;$file=Add-Certificate;$script:State.Processes=@((New-TestProcess));$r=Invoke-Cleanup;Assert ($r.Status -eq 'Running' -and $r.Code -eq 3 -and(Test-Path -LiteralPath $file)) 'Running app was ignored.'}
    Test 'Process enumeration failure fails closed' {New-Fixture;$file=Add-Certificate;$script:State.FailProcesses=$true;$r=Invoke-Cleanup;Assert ($r.Code -eq 1 -and(Test-Path -LiteralPath $file)) 'Process lookup error was ignored.'}
    Test 'Read-only preview is allowed while app is running' {New-Fixture;$file=Add-Certificate;$script:State.Processes=@((New-TestProcess));$r=Invoke-Cleanup -Preview;Assert ($r.Status -eq 'Preview' -and(Test-Path -LiteralPath $file)) 'Preview failed or modified cache.'}
    Test 'Absent cache is reported explicitly' {New-Fixture;[IO.Directory]::Delete($script:State.Cache);$r=Invoke-Cleanup;Assert ($r.Status -eq 'MissingCache' -and $r.Code -eq 2) 'Missing cache was treated as repaired.'}
    Test 'Repeated cleanup is a successful no-op' {New-Fixture;$null=Add-Certificate;$null=Invoke-Cleanup;$r=Invoke-Cleanup;Assert ($r.Status -eq 'NoMatch' -and $r.Code -eq 0) 'Repeated run failed.'}
    Test 'Structured results are not inferred from stale log lines' {New-Fixture;Set-Content -LiteralPath (Join-Path $script:State.Data 'cleanup.log') -Value 'STALE DELETED success';$r=Invoke-Cleanup;Assert ($r.Status -eq 'NoMatch' -and $r.Count -eq 0) 'Stale log determined result.'}
    Test 'Path containment rejects sibling prefixes' {New-Fixture;Assert (-not(Test-AMWithin ($script:State.Cache+'-other\setupCert.xml') $script:State.Cache)) 'Sibling path accepted.'}
    Test 'Drive-relative paths are rejected rather than resolved against working directories' {
        New-Fixture;$drive=[IO.Path]::GetPathRoot($script:State.Root).Substring(0,2)
        Assert-Throws {Get-AMFullPath ($drive+'relative')} 'absolute'
        Assert-Throws {Get-AMFullPath '\relative'} 'absolute'
    }
    Test 'Cache traversal skips nested junctions' {
        New-Fixture;$outside=Join-Path $script:State.Root 'outside';New-Item -ItemType Directory -Path $outside|Out-Null;$file=Join-Path $outside 'setupCert.xml';[IO.File]::WriteAllText($file,'KEEP');$junction=Join-Path $script:State.Cache 'nested-link';New-Item -ItemType Junction -Path $junction -Target $outside|Out-Null
        try{$r=Invoke-Cleanup;Assert ($r.Status -eq 'NoMatch' -and(Test-Path -LiteralPath $file)) 'Nested junction was followed.'}finally{[IO.Directory]::Delete($junction)}
    }
    Test 'Unexpected AC junction target is refused' {
        New-Fixture;$ac=Split-Path $script:State.Cache -Parent;[IO.Directory]::Delete($script:State.Cache);[IO.Directory]::Delete($ac);$outside=Join-Path $script:State.Root 'outside';New-Item -ItemType Directory -Path $outside|Out-Null;New-Item -ItemType Junction -Path $ac -Target $outside|Out-Null
        try{$r=Invoke-Cleanup;Assert ($r.Code -eq 1) 'Arbitrary AC redirect accepted.'}finally{[IO.Directory]::Delete($ac)}
    }
    Test 'Linked backup directory is refused' {
        New-Fixture;$file=Add-Certificate;$outside=Join-Path $script:State.Root 'outside';New-Item -ItemType Directory -Path $outside|Out-Null;$junction=Join-Path $script:State.Data 'certificate-backups';New-Item -ItemType Junction -Path $junction -Target $outside|Out-Null
        try{$r=Invoke-Cleanup;Assert ($r.Code -eq 1 -and(Test-Path -LiteralPath $file)) 'Backup directory link was followed.'}finally{[IO.Directory]::Delete($junction)}
    }
    Test 'Default manual repair never forces a running app to exit' {New-Fixture;$file=Add-Certificate;$script:State.Processes=@((New-TestProcess));$r=Invoke-AMRepair -DataDirectory $script:State.Data -CloseTimeoutSeconds 0 -NoRelaunch;Assert ($r.Status -eq 'Running' -and $script:State.Forced -eq 0 -and(Test-Path -LiteralPath $file)) 'Default manual repair forced termination.'}
    Test 'Graceful exit allows cleanup and observed relaunch' {New-Fixture;$null=Add-Certificate;$script:State.Processes=@((New-TestProcess));$script:State.Graceful=$true;$r=Invoke-AMRepair -DataDirectory $script:State.Data -CloseTimeoutSeconds 0;Assert ($r.Status -eq 'Repaired' -and $r.Relaunch -eq 'Observed' -and $script:State.Forced -eq 0 -and $script:State.Started -eq 1) 'Graceful repair/relaunch failed.'}
    Test 'Explicit ForceClose permits verified app termination' {New-Fixture;$null=Add-Certificate;$script:State.Processes=@((New-TestProcess));$r=Invoke-AMRepair -DataDirectory $script:State.Data -ForceClose -CloseTimeoutSeconds 0 -NoRelaunch;Assert ($r.Status -eq 'Repaired' -and $script:State.Forced -eq 1) 'Explicit force close failed.'}
    Test 'Unverified executable is never closed' {New-Fixture;$file=Add-Certificate;$script:State.Processes=@((New-TestProcess -Path (Join-Path $script:State.Root 'other.exe')));$r=Invoke-AMRepair -DataDirectory $script:State.Data -ForceClose -CloseTimeoutSeconds 0;Assert ($r.Code -eq 1 -and $script:State.Closed -eq 0 -and $script:State.Forced -eq 0 -and(Test-Path -LiteralPath $file)) 'Unrelated executable was closed.'}
    Test 'Processes in another session block cleanup and are never stopped' {New-Fixture;$file=Add-Certificate;$script:State.Processes=@((New-TestProcess -Session 9));$r=Invoke-AMRepair -DataDirectory $script:State.Data -ForceClose -CloseTimeoutSeconds 0;Assert ($r.Status -eq 'Running' -and $script:State.Forced -eq 0 -and(Test-Path -LiteralPath $file)) 'Another session was affected.'}
    Test 'CheckOnly does not close or launch application' {New-Fixture;$file=Add-Certificate;$script:State.Processes=@((New-TestProcess));$r=Invoke-AMRepair -CheckOnly;Assert ($r.Status -eq 'CheckPassed' -and $script:State.Closed -eq 0 -and $script:State.Started -eq 0 -and(Test-Path -LiteralPath $file)) 'CheckOnly changed app/cache.'}
    Test 'Preview does not close or launch application' {New-Fixture;$null=Add-Certificate;$script:State.Processes=@((New-TestProcess));$r=Invoke-AMRepair -DataDirectory $script:State.Data -Preview;Assert ($r.Status -eq 'Preview' -and $script:State.Closed -eq 0 -and $script:State.Started -eq 0) 'Manual preview changed application.'}
    Test 'Relaunch failure preserves successful cleanup outcome' {New-Fixture;$null=Add-Certificate;$script:State.FailLaunch=$true;$r=Invoke-AMRepair -DataDirectory $script:State.Data;Assert ($r.Status -eq 'Repaired' -and $r.Relaunch -eq 'Failed') 'Relaunch failure hid cleanup result.'}
    Test 'Default installation has no automatic task' {New-Fixture;$r=Install-Test;Assert ($r.Status -eq 'Installed' -and -not $r.Automatic -and $null -eq $script:State.Task) 'Task enabled by default.';Assert (Test-Path -LiteralPath $r.Shortcut) 'Shortcut missing.'}
    Test 'Installation handles Unicode and spaces' {New-Fixture;$r=Install-Test;Assert (Test-Path -LiteralPath (Join-Path $r.Directory 'src\Core.ps1')) 'Unicode install failed.'}
    Test 'Automatic task is optional and ordinary user only' {New-Fixture;$r=Install-Test -Automatic;Assert ($script:State.Task.Principal.RunLevel -eq 'Limited' -and $script:State.Task.Principal.LogonType -eq 'Interactive' -and -not $script:State.Task.ExitTrigger) 'Automatic task defaults incorrect.'}
    Test 'Broad exit-event trigger is opt-in' {New-Fixture;$r=Install-Test -ExitTrigger;Assert ($r.Automatic -and $script:State.Task.ExitTrigger) 'Explicit exit trigger missing.'}
    Test 'VBS launcher spec points to the selected installation' {New-Fixture;$script:State.Launcher='Vbs';$r=Install-Test -Automatic;$config=Read-AMConfig $r.Directory;Assert ($config.Launcher -eq 'Vbs' -and $script:State.Task.Actions[0].Arguments.Contains((Join-Path $r.Directory 'Launch.vbs'))) 'VBS task target wrong.'}
    Test 'Repeat installation preserves automatic mode and identity' {New-Fixture;$a=Install-Test -Automatic;$id=(Read-AMConfig $a.Directory).InstallationId;$b=Install-Test;Assert ($b.Automatic -and (Read-AMConfig $b.Directory).InstallationId -eq $id -and $script:State.Task.Enabled) 'Repeat install changed identity or disabled task.'}
    Test 'DisableAutomatic explicitly removes automatic task' {New-Fixture;$a=Install-Test -Automatic;$b=Install-Test -DisableAutomatic;Assert (-not $b.Automatic -and $null -eq $script:State.Task) 'Task not disabled.'}
    Test 'Non-project destination is never overwritten' {New-Fixture;$dest=Join-Path $script:State.Root 'Installed 工具';New-Item -ItemType Directory -Path $dest|Out-Null;Set-Content -LiteralPath (Join-Path $dest 'keep.txt') -Value 'KEEP';Assert-Throws {Install-Test} 'not an empty';Assert ((Get-Content -LiteralPath (Join-Path $dest 'keep.txt')) -eq 'KEEP') 'Existing file overwritten.'}
    Test 'Foreign task blocks installation before writing files' {New-Fixture;$script:State.Task=[pscustomobject]@{TaskName=('Apple Music Cache Repair - '+$script:State.Sid)};Assert-Throws {Install-Test -Automatic} 'another installation';Assert (-not(Test-Path -LiteralPath (Join-Path $script:State.Root 'Installed 工具'))) 'Files written despite task conflict.'}
    Test 'Foreign shortcut is never overwritten' {New-Fixture;[pscustomobject]@{Target='foreign.exe';Arguments='';WorkingDirectory=$script:State.Root}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $script:State.Desktop 'Apple Music Cache Repair.lnk');Assert-Throws {Install-Test} 'another installation';Assert ($script:State.TaskWrites -eq 0) 'Task changed despite shortcut conflict.'}
    Test 'New install registration failure removes partial task and scripts' {New-Fixture;$script:State.FailTask=$true;Assert-Throws {Install-Test -Automatic} 'previous files';Assert ($null -eq $script:State.Task) 'Partial task remained.';Assert (-not(Test-Path -LiteralPath (Join-Path $script:State.Root 'Installed 工具\install.json'))) 'Partial configuration remained.'}
    Test 'Failed first installation can be retried without manual cleanup' {New-Fixture;$script:State.FailTask=$true;Assert-Throws {Install-Test -Automatic};$script:State.FailTask=$false;$r=Install-Test -Automatic;Assert ($r.Status -eq 'Installed' -and $script:State.Task.Enabled) 'First-install rollback prevented retry.'}
    Test 'Failed upgrade restores task state and original script bytes' {
        New-Fixture;$r=Install-Test -Automatic;$scriptPath=Join-Path $r.Directory 'Repair.ps1';[IO.File]::AppendAllText($scriptPath,"`r`n# old local marker");$hash=(Get-FileHash -LiteralPath $scriptPath).Hash;$configHash=(Get-FileHash -LiteralPath (Join-Path $r.Directory 'install.json')).Hash;$script:State.FailTask=$true
        Assert-Throws {Install-Test -Automatic} 'previous files'
        Assert ($script:State.Task.Enabled -and (Get-FileHash -LiteralPath $scriptPath).Hash -eq $hash -and (Get-FileHash -LiteralPath (Join-Path $r.Directory 'install.json')).Hash -eq $configHash) 'Upgrade rollback failed.'
    }
    Test 'Failed upgrade restores an existing zero-byte file' {
        New-Fixture;$r=Install-Test -Automatic;$path=Join-Path $r.Directory 'NOTICE.md';[IO.File]::WriteAllBytes($path,[byte[]]@());$script:State.FailTask=$true
        Assert-Throws {Install-Test -Automatic} 'previous files'
        Assert ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Length -eq 0) 'Rollback deleted an existing empty file.'
    }
    Test 'Shortcut creation failure rolls back new task' {New-Fixture;$script:State.FailShortcut=$true;Assert-Throws {Install-Test -Automatic} 'previous files';Assert ($null -eq $script:State.Task -and -not(Test-Path -LiteralPath (Join-Path $script:State.Desktop 'Apple Music Cache Repair.lnk'))) 'Partial task/shortcut remained.'}
    Test 'Uninstall preserves certificate backups and logs' {New-Fixture;$r=Install-Test -Automatic;$data=Join-Path $r.Directory 'data';Set-Content -LiteralPath (Join-Path $data 'keep.log') -Value 'KEEP';$u=Uninstall-AMRepair -InstallDirectory $r.Directory;Assert ($u.Status -eq 'Uninstalled' -and $null -eq $script:State.Task -and -not(Test-Path -LiteralPath $r.Shortcut) -and(Test-Path -LiteralPath (Join-Path $data 'keep.log'))) 'Uninstall removed data or retained active task.'}
    Test 'Uninstall refuses a modified task action' {New-Fixture;$r=Install-Test -Automatic;$script:State.Task.Actions[0].Arguments+=' unexpected';Assert-Throws {Uninstall-AMRepair -InstallDirectory $r.Directory} 'ownership';Assert ($null -ne $script:State.Task -and $script:State.Task.Enabled) 'Foreign task removed or disabled.'}
    Test 'Uninstall failure restores task and shortcut' {New-Fixture;$r=Install-Test -Automatic;$script:State.FailRemoveShortcut=$true;Assert-Throws {Uninstall-AMRepair -InstallDirectory $r.Directory} 'original configuration';Assert ($null -ne $script:State.Task -and $script:State.Task.Enabled -and(Test-Path -LiteralPath $r.Shortcut)) 'Uninstall rollback incomplete.'}
    Test 'Configuration-write failure during uninstall restores all ownership metadata' {New-Fixture;$r=Install-Test -Automatic;$hash=(Get-FileHash -LiteralPath (Join-Path $r.Directory 'install.json')).Hash;$script:State.FailWriteConfig=$true;Assert-Throws {Uninstall-AMRepair -InstallDirectory $r.Directory} 'original configuration';Assert ($script:State.Task.Enabled -and(Test-Path -LiteralPath $r.Shortcut) -and(Get-FileHash -LiteralPath (Join-Path $r.Directory 'install.json')).Hash -eq $hash) 'Config-write failure lost prior configuration.'}
    Test 'Contradictory automatic settings are rejected' {New-Fixture;Assert-Throws {Install-AMRepair -SourceDirectory $Repository -InstallDirectory (Join-Path $script:State.Root 'install') -Automatic -DisableAutomatic} 'mutually exclusive';Assert ($script:State.TaskWrites -eq 0) 'Contradictory flags changed tasks.'}
    Test 'Actual cross-process cleanup mutex prevents parallel mutation' {
        New-Fixture;$file=Add-Certificate;$ready=Join-Path $script:State.Root 'ready';$holder=Join-Path $script:State.Root 'hold.ps1'
        $name='Local\AppleMusicCacheRepair-Cleanup-'+$script:State.Sid
        $body='$m=New-Object Threading.Mutex($false,'''+$name+''');[void]$m.WaitOne();[IO.File]::WriteAllText('''+$ready.Replace("'","''")+''',''ready'');Start-Sleep -Seconds 30'
        [IO.File]::WriteAllText($holder,$body,(New-Object Text.UTF8Encoding($true)))
        $process=Start-Process -FilePath (Get-AMPowerShell) -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$holder+'"') -WindowStyle Hidden -PassThru
        try{
            $deadline=(Get-Date).AddSeconds(8);while(-not(Test-Path -LiteralPath $ready) -and(Get-Date) -lt $deadline){Start-Sleep -Milliseconds 100}
            Assert (Test-Path -LiteralPath $ready) 'Mutex holder failed to start.'
            $r=Invoke-Cleanup;Assert ($r.Status -eq 'Busy' -and(Test-Path -LiteralPath $file)) 'Mutex failed to prevent concurrent cleanup.'
            Assert-Throws {Install-Test} 'active'
        }finally{if(-not $process.HasExited){$process.Kill();$process.WaitForExit()};$process.Dispose()}
    }
    [pscustomobject]@{PowerShell=$PSVersionTable.PSVersion.ToString();Passed=@($script:TestResults|Where-Object {$_.Passed}).Count;Failed=@($script:TestResults|Where-Object {-not $_.Passed}).Count;Tests=$script:TestResults.ToArray()}
} $repository $WorkRoot
if($ReportPath){$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath -Encoding UTF8}
Write-Host ('Tests: '+$report.Passed+' passed, '+$report.Failed+' failed; PowerShell '+$report.PowerShell)
if($report.Failed){exit 1}
exit 0
