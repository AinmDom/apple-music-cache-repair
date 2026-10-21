# SPDX-License-Identifier: MIT
[CmdletBinding()]
param([string]$InstallDirectory)
$ErrorActionPreference='Stop'
try{
    Import-Module (Join-Path $PSScriptRoot 'src\AppleMusicCacheRepair.psm1') -Force -ErrorAction Stop
    if(-not $InstallDirectory -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'install.json'))){$InstallDirectory=$PSScriptRoot}
    Uninstall-AMRepair -InstallDirectory $InstallDirectory | ConvertTo-Json -Depth 4
    exit 0
}catch{Write-Error $_ -ErrorAction Continue;exit 1}
