# SPDX-License-Identifier: MIT
[CmdletBinding()]
param([switch]$Probe)
$ErrorActionPreference='Stop'
if($Probe){exit 0}
Import-Module (Join-Path $PSScriptRoot 'src\AppleMusicCacheRepair.psm1') -Force -ErrorAction Stop
$result=Invoke-AMCleanup -DataDirectory (Join-Path $PSScriptRoot 'data')
$result|ConvertTo-Json -Depth 6
# Running is an expected background no-op; manual callers retain code 3.
if($result.Status -eq 'Running'){exit 0}
exit $result.Code
