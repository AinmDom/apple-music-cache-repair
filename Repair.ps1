# SPDX-License-Identifier: MIT
[CmdletBinding()]
param([switch]$Preview,[switch]$CheckOnly,[switch]$ForceClose,[switch]$NoRelaunch,[switch]$NoUi)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'src\AppleMusicCacheRepair.psm1') -Force -ErrorAction Stop
$options=@{DataDirectory=(Join-Path $PSScriptRoot 'data');Preview=$Preview;CheckOnly=$CheckOnly;ForceClose=$ForceClose;NoRelaunch=$NoRelaunch}
$result=Invoke-AMRepair @options
if(-not $NoUi){
    Add-Type -AssemblyName System.Windows.Forms
    if($result.Status -eq 'Running' -and -not $ForceClose){
        $answer=[Windows.Forms.MessageBox]::Show('Apple Music 后台仍在运行，本次未清理缓存。是否强制关闭后继续？这会中断播放、下载或资料库操作。','Apple Music 缓存修复',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning)
        if($answer -eq [Windows.Forms.DialogResult]::Yes){$options.ForceClose=$true;$result=Invoke-AMRepair @options}
    }
    $message=switch($result.Status){
        'Repaired' {'证书缓存已备份并清理。请测试搜索和播放。'}
        'NoMatch' {'当前没有需要清理的 setupCert 缓存。此工具仅适用于这类证书缓存问题。'}
        'Preview' {'预览完成，未删除缓存。匹配文件数：'+$result.Files.Count}
        'CheckPassed' {'检查通过：Apple Music 和缓存目录可用。'}
        'Running' {'Apple Music 尚未完全退出，本次未清理缓存。'}
        'Busy' {'另一项修复正在运行，请稍后再试。'}
        default {'未完成修复：'+$result.Message}
    }
    if($result.Relaunch -eq 'Observed'){$message+="`r`n已检测到 Apple Music 重新启动。"}
    elseif($result.Relaunch -eq 'Requested'){$message+="`r`n已发送启动请求，尚未确认启动；请手动打开客户端。"}
    elseif($result.Relaunch -eq 'Failed'){$message+="`r`n自动启动失败，请手动打开 Apple Music。"}
    $icon=if($result.Code -eq 0){[Windows.Forms.MessageBoxIcon]::Information}else{[Windows.Forms.MessageBoxIcon]::Warning}
    [void][Windows.Forms.MessageBox]::Show($message,'Apple Music 缓存修复',[Windows.Forms.MessageBoxButtons]::OK,$icon)
}
$result|ConvertTo-Json -Depth 6
exit $result.Code
