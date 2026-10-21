# SPDX-License-Identifier: MIT
# Derived from mikepink/music-on-windows11-unknown-error-fix; see NOTICE.md.
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'Core.ps1')
. (Join-Path $PSScriptRoot 'Repair.ps1')
. (Join-Path $PSScriptRoot 'Installation.ps1')
Export-ModuleMember -Function Invoke-AMCleanup,Invoke-AMRepair,Install-AMRepair,Uninstall-AMRepair,Get-AMDefaultInstallDirectory
