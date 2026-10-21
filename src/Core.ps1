# SPDX-License-Identifier: MIT
$script:AMFamily='AppleInc.AppleMusicWin_nzyj5cx40ttqa'
$script:AMProject='AppleMusicCacheRepair'

function Get-AMIdentity { [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
function Get-AMLocalAppData { [Environment]::GetFolderPath('LocalApplicationData') }
function Get-AMDesktop { [Environment]::GetFolderPath('Desktop') }
function Get-AMDefaultInstallDirectory { Join-Path (Get-AMLocalAppData) $script:AMProject }
function Get-AMFullPath([string]$Path) {
    # IsPathRooted also accepts drive-relative forms such as C:folder and \folder.
    if([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^(?:[A-Za-z]:[\\/]|\\\\(?![?.][\\/])[^\\/]+[\\/][^\\/]+(?:[\\/]|$))'){throw 'An absolute filesystem path is required.'}
    [IO.Path]::GetFullPath($Path)
}
function Test-AMWithin([string]$Path,[string]$Root,[switch]$AllowRoot) {
    $full=(Get-AMFullPath $Path).TrimEnd('\')
    $anchor=(Get-AMFullPath $Root).TrimEnd('\')
    ($AllowRoot -and $full.Equals($anchor,[StringComparison]::OrdinalIgnoreCase)) -or $full.StartsWith($anchor+'\',[StringComparison]::OrdinalIgnoreCase)
}
function Assert-AMPlainPath([string]$Path,[switch]$AllowMissing) {
    $full=Get-AMFullPath $Path
    $current=$full
    while(-not (Test-Path -LiteralPath $current)){
        if(-not $AllowMissing){throw ('Path missing or inaccessible: '+$current)}
        $parent=Split-Path -Parent $current
        if(-not $parent -or $parent -eq $current){throw 'No accessible filesystem ancestor.'}
        $current=$parent
    }
    $node=Get-Item -LiteralPath $current -Force -ErrorAction Stop
    while($node){
        if($node.Attributes -band [IO.FileAttributes]::ReparsePoint){throw ('Unexpected filesystem link: '+$node.FullName)}
        if($node -is [IO.FileInfo]){$node=$node.Directory}else{$node=$node.Parent}
    }
}
function Initialize-AMData([string]$DataDirectory) {
    $path=Get-AMFullPath $DataDirectory
    Assert-AMPlainPath $path -AllowMissing
    if(-not (Test-Path -LiteralPath $path)){New-Item -ItemType Directory -Path $path -ErrorAction Stop | Out-Null}
    Assert-AMPlainPath $path
    $path
}
function Write-AMLog([string]$DataDirectory,[string]$RunId,[string]$Status,[string]$Message) {
    $path=Join-Path $DataDirectory 'cleanup.log'
    Assert-AMPlainPath $path -AllowMissing
    if((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path -Force).Length -gt 524288){
        $previous=$path+'.previous'
        Assert-AMPlainPath $previous -AllowMissing
        [IO.File]::WriteAllBytes($previous,[IO.File]::ReadAllBytes($path))
        [IO.File]::WriteAllText($path,'')
    }
    $record=[ordered]@{Time=(Get-Date).ToUniversalTime().ToString('o');RunId=$RunId;Status=$Status;Message=$Message}
    Add-Content -LiteralPath $path -Value ($record|ConvertTo-Json -Compress) -Encoding UTF8 -ErrorAction Stop
}
function New-AMResult([string]$Status,[int]$Code,[string]$Message,[string]$RunId) {
    [pscustomobject][ordered]@{Status=$Status;Code=$Code;Message=$Message;RunId=$RunId;Count=0;Files=@();Relaunch='NotRequested'}
}
function Resolve-AMCacheContext([string]$LocalAppData,[string]$UserSid) {
    $local=Get-AMFullPath $LocalAppData
    Assert-AMPlainPath $local
    $package=Join-Path $local ('Packages\'+$script:AMFamily)
    Assert-AMPlainPath $package -AllowMissing
    $ac=Join-Path $package 'AC'
    $logical=Join-Path $ac 'INetCache'
    if(-not (Test-Path -LiteralPath $ac -PathType Container)){
        return [pscustomobject]@{Exists=$false;Cache=$logical;LogicalCache=$logical;Ac=$ac;Sid=$UserSid}
    }
    $item=Get-Item -LiteralPath $ac -Force -ErrorAction Stop
    $actualAc=$ac
    if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){
        $targets=@($item.Target)
        if($item.LinkType -ne 'Junction' -or $targets.Count -ne 1){throw 'Unrecognized Apple Music AC link.'}
        $actualAc=(Get-AMFullPath ([string]$targets[0])).TrimEnd('\')
        # Store apps on other volumes use this per-user, package-specific layout.
        # Arbitrary junction targets and links nested within it remain forbidden.
        $expected='^[A-Za-z]:\\WpSystem\\'+[regex]::Escape($UserSid)+'\\AppData\\Local\\Packages\\'+[regex]::Escape($script:AMFamily)+'\\AC$'
        if($actualAc -notmatch $expected){throw 'AC link target is not the expected current-user Store package.'}
    }
    Assert-AMPlainPath $actualAc
    $cache=Join-Path $actualAc 'INetCache'
    Assert-AMPlainPath $cache -AllowMissing
    [pscustomobject]@{Exists=(Test-Path -LiteralPath $cache -PathType Container);Cache=$cache;LogicalCache=$logical;Ac=$ac;Sid=$UserSid}
}
function Assert-AMCacheUnchanged($Context) {
    # Recheck the logical link before mutations, including a move performed while waiting.
    $local=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $Context.Ac))
    $again=Resolve-AMCacheContext $local $Context.Sid
    if(-not $again.Exists -or $again.Cache -ne $Context.Cache){throw 'Apple Music cache location changed during this run.'}
    Assert-AMPlainPath $Context.Cache
}
function Get-AMMusicProcesses {
    @(Get-Process -ErrorAction Stop | Where-Object {$_.ProcessName -match '^(AppleMusic|AMPLibraryAgent)$'})
}
function Get-AMCacheFiles($Context) {
    $queue=New-Object 'System.Collections.Generic.Queue[string]'
    $queue.Enqueue($Context.Cache)
    while($queue.Count){
        $folder=$queue.Dequeue()
        Assert-AMPlainPath $folder
        foreach($item in @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction Stop)){
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
            if($item.PSIsContainer){$queue.Enqueue($item.FullName)}
            elseif($item.Name -match '^setupCert(?:\[\d+\])?\.(xml|plist)$'){$item}
        }
    }
}
function Read-AMCertificateBytes([string]$Path) {
    # Check the opened file, not potentially stale directory-enumeration metadata.
    # Refuse writers and renames while reading and bound the allocation to 1 MiB.
    $stream=New-Object IO.FileStream($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        if($stream.Length -gt 1048576){throw 'Unexpected certificate size (over 1 MiB).'}
        $bytes=New-Object byte[] ([int]$stream.Length)
        $offset=0
        while($offset -lt $bytes.Length){
            $read=$stream.Read($bytes,$offset,$bytes.Length-$offset)
            if($read -eq 0){throw 'Cache changed while reading; original was retained.'}
            $offset+=$read
        }
        return ,$bytes
    }finally{$stream.Dispose()}
}
function Invoke-AMCacheCleanup($Context,[string]$DataDirectory,[switch]$Preview) {
    $runId=[guid]::NewGuid().ToString('N')
    $result=New-AMResult 'Error' 1 'Cleanup did not complete.' $runId
    $mutex=$null;$owns=$false;$data=$null
    try{
        $data=Initialize-AMData $DataDirectory
        $mutex=New-Object Threading.Mutex($false,('Local\AppleMusicCacheRepair-Cleanup-'+$Context.Sid))
        try{$owns=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owns=$true}
        if(-not $owns){$result.Status='Busy';$result.Code=4;$result.Message='Another cleanup is running.';return $result}
        if(-not $Context.Exists){$result.Status='MissingCache';$result.Code=2;$result.Message='Apple Music cache is missing or inaccessible.';return $result}
        if(-not $Preview -and @(Get-AMMusicProcesses).Count){$result.Status='Running';$result.Code=3;$result.Message='Apple Music or its agent is running; no cache was removed.';return $result}
        Assert-AMCacheUnchanged $Context
        $entries=@(Get-AMCacheFiles $Context)
        if(-not $entries.Count){$result.Status='NoMatch';$result.Code=0;$result.Message='No matching setupCert cache files were found.';return $result}
        foreach($entry in $entries){
            $full=$entry.FullName
            if(-not (Test-AMWithin $full $Context.Cache)){throw 'Cache containment check failed.'}
            Assert-AMPlainPath $full
            $bytes=Read-AMCertificateBytes $full
            $sha=[Security.Cryptography.SHA256]::Create()
            try{$hash=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')}finally{$sha.Dispose()}
            $kind='unknown'
            if($bytes.Length -ge 2 -and $bytes[0] -eq 31 -and $bytes[1] -eq 139){$kind='gzip'}
            elseif($bytes.Length -and $bytes[0] -eq 60){$kind='plain'}
            elseif(-not $bytes.Length){$kind='empty'}
            $relative=$full.Substring($Context.Cache.TrimEnd('\').Length+1)
            $detail=[pscustomobject]@{RelativePath=$relative;Kind=$kind;Length=$bytes.Length;SHA256=$hash;Removed=$false}
            if($Preview){$result.Files+=@($detail);continue}
            if(@(Get-AMMusicProcesses).Count){throw 'Apple Music started during cleanup; remaining entries were retained.'}
            $backups=Initialize-AMData (Join-Path $data 'certificate-backups')
            $backup=Join-Path $backups ($hash+'.bak')
            Assert-AMPlainPath $backup -AllowMissing
            if(-not (Test-Path -LiteralPath $backup)){
                # Writing public certificate bytes avoids copying EFS encryption metadata.
                $stream=New-Object IO.FileStream($backup,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
                try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush()}finally{$stream.Dispose()}
            }
            if((Get-FileHash -LiteralPath $backup -Algorithm SHA256 -ErrorAction Stop).Hash -ne $hash){throw 'Certificate backup hash verification failed.'}
            $manifest=Join-Path $data 'backup-manifest.jsonl'
            Assert-AMPlainPath $manifest -AllowMissing
            $record=[ordered]@{Time=(Get-Date).ToUniversalTime().ToString('o');RunId=$runId;RelativePath=$relative;Backup=($hash+'.bak');SHA256=$hash;Kind=$kind;Length=$bytes.Length}
            Add-Content -LiteralPath $manifest -Value ($record|ConvertTo-Json -Compress) -Encoding UTF8 -ErrorAction Stop
            # Manifest I/O can take time: perform the final checks after it completes.
            Assert-AMCacheUnchanged $Context
            Assert-AMPlainPath $backup
            if((Get-FileHash -LiteralPath $backup -Algorithm SHA256 -ErrorAction Stop).Hash -ne $hash){throw 'Certificate backup changed before deletion; original was retained.'}
            Assert-AMPlainPath $full
            if((Get-FileHash -LiteralPath $full -Algorithm SHA256 -ErrorAction Stop).Hash -ne $hash){throw 'Cache changed after backup; original was retained.'}
            if(@(Get-AMMusicProcesses).Count){throw 'Apple Music started before deletion; original was retained.'}
            Remove-Item -LiteralPath $full -Force -ErrorAction Stop
            if(Test-Path -LiteralPath $full){throw 'Cache entry still exists after removal.'}
            $detail.Removed=$true
            $result.Count++
            $result.Files+=@($detail)
        }
        $result.Status=if($Preview){'Preview'}else{'Repaired'}
        $result.Code=0
        $result.Message=if($Preview){'Preview completed; no cache was removed.'}else{'Matching certificate cache files were backed up and removed.'}
        return $result
    }catch{
        $result.Status='Error';$result.Code=1;$result.Message=$_.Exception.Message
        return $result
    }finally{
        if($data){
            try{Write-AMLog $data $runId $result.Status $result.Message}
            catch{$result.Status='Error';$result.Code=1;$result.Message='Failed to write cleanup log; inspect the data directory permissions.'}
        }
        if($owns){$mutex.ReleaseMutex()}
        if($mutex){$mutex.Dispose()}
    }
}
function Invoke-AMCleanup([string]$DataDirectory,[switch]$Preview) {
    if(-not $DataDirectory){$DataDirectory=Join-Path (Split-Path $PSScriptRoot -Parent) 'data'}
    try{
        $context=Resolve-AMCacheContext (Get-AMLocalAppData) (Get-AMIdentity)
        Invoke-AMCacheCleanup $context $DataDirectory -Preview:$Preview
    }catch{New-AMResult 'Error' 1 $_.Exception.Message ([guid]::NewGuid().ToString('N'))}
}
