# SPDX-License-Identifier: MIT
[CmdletBinding()]
param([string]$OutputDirectory,[switch]$Force)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(-not $OutputDirectory){$OutputDirectory=Join-Path $root 'dist'}
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
$project=Get-Content -LiteralPath (Join-Path $root 'project.json') -Raw|ConvertFrom-Json
if($project.name -ne 'apple-music-cache-repair' -or $project.version -notmatch '^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$'){throw 'Invalid package identity.'}
$manifest=Get-Content -LiteralPath (Join-Path $root 'release-files.json') -Raw|ConvertFrom-Json
$files=@($manifest|ForEach-Object {[string]$_})
if(-not $files.Count -or @($files|Select-Object -Unique).Count -ne $files.Count){throw 'Invalid or duplicate release manifest entries.'}
$checked=@()
$profile=[Environment]::GetFolderPath('UserProfile')
foreach($relative in $files){
    if([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)' -or $relative -match ':'){throw ('Unsafe manifest path: '+$relative)}
    if($relative -match '(?i)(^|[\\/])(data|previous-install|certificate-backups|dist|\.git)([\\/]|$)|\.(log|bak|lnk|xml)$|(^|/)(install|deployment|verification)\.json$'){throw ('Runtime/private artifact in manifest: '+$relative)}
    $path=Join-Path $root $relative
    $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if($item.PSIsContainer){throw 'Release manifest must contain individual files.'}
    $node=$item
    while($node){if($node.Attributes -band [IO.FileAttributes]::ReparsePoint){throw ('Release source link refused: '+$path)};if($node -is [IO.FileInfo]){$node=$node.Directory}else{$node=$node.Parent}}
    $bytes=[IO.File]::ReadAllBytes($path)
    $text=[Text.Encoding]::UTF8.GetString($bytes)
    if($profile -and $text.IndexOf($profile,[StringComparison]::OrdinalIgnoreCase) -ge 0){throw ('Personal profile path found: '+$relative)}
    if($text -match '(?i)[A-Z]:\\(?:Users|Documents and Settings)\\[^\\\s]+'){throw ('Literal user profile found: '+$relative)}
    if($item.Extension -in @('.ps1','.psm1')){
        if($bytes.Length -lt 3 -or $bytes[0] -ne 239 -or $bytes[1] -ne 187 -or $bytes[2] -ne 191){throw ('PowerShell 5.1 requires UTF-8 BOM for this distribution: '+$relative)}
        $tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
        if($errors){throw ('PowerShell syntax failure: '+$relative+' '+($errors.Message -join '; '))}
    }
    if($item.Extension -in @('.vbs','.cmd') -and @($bytes|Where-Object {$_ -gt 127}).Count){throw ('Launcher must remain ASCII: '+$relative)}
    $checked+=@([pscustomobject]@{Relative=$relative.Replace('\','/');Path=$path})
}
if(-not(Test-Path -LiteralPath $OutputDirectory)){New-Item -ItemType Directory -Path $OutputDirectory|Out-Null}
$name=$project.name+'-'+$project.version+'.zip'
$zip=Join-Path $OutputDirectory $name
if(Test-Path -LiteralPath $zip){if(-not $Force){throw 'Release archive already exists; use Force to replace it.'};Remove-Item -LiteralPath $zip -Force}
Add-Type -AssemblyName System.IO.Compression
$fileStream=New-Object IO.FileStream($zip,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
$archive=$null
try{
    $archive=New-Object IO.Compression.ZipArchive($fileStream,[IO.Compression.ZipArchiveMode]::Create,$true)
    foreach($file in $checked){
        $entry=$archive.CreateEntry(($project.name+'/'+$file.Relative),[IO.Compression.CompressionLevel]::Optimal)
        # Fixed timestamps make builds from the same bytes reproducible on the same runtime.
        $entry.LastWriteTime=[DateTimeOffset]::Parse('2026-01-01T00:00:00+00:00')
        $stream=$entry.Open()
        try{$bytes=[IO.File]::ReadAllBytes($file.Path);$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
    }
}finally{if($archive){$archive.Dispose()};$fileStream.Dispose()}
$hash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText(($zip+'.sha256'),($hash+'  '+$name+"`n"),[Text.Encoding]::ASCII)
[pscustomobject]@{Archive=$zip;SHA256=$hash;Files=$checked.Count;Checks='Allowlist, links, private artifacts, profile paths, PowerShell syntax/BOM, ASCII launchers'}
