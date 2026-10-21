# SPDX-License-Identifier: MIT
[CmdletBinding()]
param([string]$InstallDirectory,[switch]$Automatic,[switch]$DisableAutomatic,[switch]$ExitTrigger,[switch]$NoDesktopShortcut,[switch]$PowerShellOnly)
$ErrorActionPreference='Stop'
try{
    Import-Module (Join-Path $PSScriptRoot 'src\AppleMusicCacheRepair.psm1') -Force -ErrorAction Stop
    if(-not $PSBoundParameters.ContainsKey('InstallDirectory') -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'install.json'))){$PSBoundParameters.InstallDirectory=$PSScriptRoot}
    Install-AMRepair -SourceDirectory $PSScriptRoot @PSBoundParameters | ConvertTo-Json -Depth 4
    exit 0
}catch{Write-Error $_ -ErrorAction Continue;exit 1}
