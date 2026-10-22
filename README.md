[简体中文](README.md) | [English](README.en.md)

# Apple Music Cache Repair

Windows 版 Apple Music 的 `setupCert` 证书缓存修复工具。只备份并清理对应缓存文件，不重置应用，不清理下载音乐、资料库或登录数据。

这是基于 [mikepink/music-on-windows11-unknown-error-fix](https://github.com/mikepink/music-on-windows11-unknown-error-fix) 的 MIT 开源改进版，来源和改动见 [NOTICE.md](NOTICE.md)。工具非 Apple 官方产品；它只能处理这类证书缓存问题，不能保证修复所有“未知错误”、网络或账户问题。

## 环境与快速使用

- Windows 11、Microsoft Store 版 Apple Music、系统自带 Windows PowerShell 5.1。
- 普通用户权限即可。不下载或执行远程代码，不修改代理、DNS、系统证书或系统执行策略。
- 默认正常关闭客户端；后台未退出时保留缓存，只有用户明确选择后才强制关闭。
- 修复会中断播放。请避开导入音乐、同步及编辑资料库的时段。

下载发布 ZIP 并解压，双击 `Repair.cmd` 即可直接使用。成功提示只代表缓存操作完成，搜索和播放仍需在客户端验证。

如果 Windows 提示来源不可信，请先核对发布包哈希并阅读源代码；不要关闭系统安全功能。企业策略阻止脚本时应联系设备管理员。

## 安装和快捷方式

双击 `Install.cmd`：默认安装到当前用户本地应用数据目录下的 `AppleMusicCacheRepair`，创建桌面快捷方式，**默认不添加自动任务**。安装后的目录需要保留。不要安装到全盘根目录、原始源码目录、共享可写目录或包含符号链接的目录。

自定义安装路径，例如在 PowerShell 中执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -InstallDirectory "E:\Tools\Apple Music Repair"
```

无需预先创建目录；安装器会拒绝覆盖非本项目的已有文件夹、同名任务或快捷方式。升级时，从新版本目录运行相同命令，选择原安装路径。安装失败会恢复本次变更前的脚本、配置、任务和快捷方式；若回滚自身也失败，错误信息会明确列出。

如不需要桌面快捷方式，加 `-NoDesktopShortcut`。默认检测 VBS 隐藏启动器能否运行，不可用时使用 PowerShell 入口；也可以加 `-PowerShellOnly`。备用入口可能短暂显示窗口。PowerShell 修复本身不依赖 VBS。Windows 后续禁用 VBS 时，使用 `Repair.cmd` 或以 `-PowerShellOnly` 重新安装即可。

`-ExecutionPolicy Bypass` 仅作用于本次进程，脚本不修改系统的执行策略配置。

## 可选：自动修复

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Automatic
```

添加当前用户专属任务，登录 30 秒后及每小时运行。任务使用当前用户的交互式登录令牌和普通权限，不保存密码，不结束进程，Apple Music 或其后台运行时只跳过。

希望关闭打包桌面应用后也触发，可加 `-ExitTrigger`。此选项监听 AppModel-Runtime 事件 217，**会被所有打包桌面应用的退出事件触发**，随后由脚本判断是否有工作可做。它是可选项，避免新用户默认承受过多后台启动；应用更新通常不需要重建该触发器。

重复安装会保留已有自动任务选项。用 `-DisableAutomatic` 明确关闭自动任务。升级不会接管上游或其他工具建立的任务；请先用原工具停用它们，避免重复清理。

任务名称为 `Apple Music Cache Repair - <当前用户 SID>`。默认任务不会在刚安装完成时执行清理。首次使用自动功能后，请检查任务的上次运行结果及 `data\cleanup.log`，确认实际运行；仅看到任务注册成功不能证明修复脚本已运行。

## 命令行、预览和结果

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Repair.ps1 -Preview -NoUi
powershell -NoProfile -ExecutionPolicy Bypass -File .\Repair.ps1 -CheckOnly -NoUi
powershell -NoProfile -ExecutionPolicy Bypass -File .\Repair.ps1 -NoUi -NoRelaunch
```

预览不关闭应用、不重启应用、不删除缓存，但会在 `data` 中写入操作日志。`-CheckOnly` 检查应用注册和路径，不进行清理。命令行输出本次调用的 JSON 结果，无需读取共享日志最后一行。

`-ForceClose` 是明确授权强制关闭的命令行选项；默认不启用。它只结束已核实属于 Apple Music 安装包、当前会话内的进程。图形入口遇到后台不退出时，会先询问是否强制关闭。清理时若检测到其他会话仍有 Apple Music 进程，则拒绝清理。

| Code | Status | 含义 |
|---|---|---|
| 0 | Repaired / NoMatch / Preview / CheckPassed | 清理成功、无匹配项、预览或检查成功 |
| 1 | Error | 操作或日志写入失败；结果保留已完成文件列表 |
| 2 | MissingCache | 缓存目录不存在或不可访问 |
| 3 | Running | 应用仍运行，拒绝清理 |
| 4 | Busy | 另一项修复或清理正在进行 |

后台入口将 `Running` 视为正常跳过，返回 0；其他失败会传给计划任务。`Relaunch=Requested` 仅说明发送了启动请求；`Observed` 表示检测到客户端进程，均不代表搜索或播放已经恢复。

## 清理范围与备份

仅在当前用户的 `Packages\AppleInc.AppleMusicWin_nzyj5cx40ttqa\AC\INetCache` 内匹配完整文件名：

- `setupCert.xml`、`setupCert.plist`
- `setupCert[数字].xml`、`setupCert[数字].plist`

不匹配 `.bak`、`.old`、其他 `setupCert*` 名称，不清理 MediaServices `data` 数据库。超过 1 MiB 的目标文件会触发错误。gzip、普通内容、空文件都先备份，校验 SHA-256 后才删除。

支持常规本地安装，以及 Store 将 `AC` 映射到其他盘 `WpSystem\<当前用户 SID>\AppData\Local\Packages\<同一包名>\AC` 的布局。盘符自动识别；其他链接布局和缓存内嵌套链接不会被跟随。目录布局不符合预期时，请提交脱敏描述；不要通过放宽路径检查绕过错误。

运行数据全部位于安装目录的 `data` 中：

- `cleanup.log`：带本次 RunId 的日志，达到约 512 KiB 后保留上一份。
- `certificate-backups`：按 SHA-256 去重的证书内容备份，不复制 EFS 加密属性。
- `backup-manifest.jsonl`：原缓存相对路径、哈希、大小和本次 RunId；记录备份，不代表原文件一定已删除，以本次结果中的 `Removed` 为准。

备份不会自动过期。源缓存的系统加密设置不被修改。通常不应恢复旧 gzip 缓存，以免错误复发；如要恢复，先停用自动任务并退出 Apple Music，按清单核对备份哈希，仅在原路径不存在时复制回对应位置。不要覆盖客户端已重新生成的文件。

脚本在写完备份清单后、删除前再次检查进程、备份、文件哈希及路径；最终检查与删除并非不可分割，仍无法完全排除检查后客户端启动或文件再次变化的短暂竞争窗口。修复过程中请不要手动打开 Apple Music。

## 卸载与隐私

运行安装目录中的 `Uninstall.cmd`，移除本项目拥有的任务和桌面快捷方式，保留脚本、日志及备份。确认不再需要后，可手动删除安装目录。卸载失败时会尝试恢复原配置。

不要把 `data`、`install.json`、个人日志、备份、任务 XML 或生成的快捷方式上传到 GitHub。安装配置和错误日志可能包含路径、用户 SID 等信息。提交问题前脱敏；公共证书备份也不需要上传。工具没有遥测、自动更新或远程日志上传。

## 开发与验证

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Release.ps1
```

测试只操作临时目录；用模拟适配器验证计划任务、应用进程和快捷方式，不终止真实客户端、不修改用户的任务。核心测试同时运行于 Windows PowerShell 5.1 和 PowerShell 7；用户入口统一调用 Windows PowerShell 5.1。GitHub Actions 配置会在推送和 PR 后运行，但本地附带配置并不表示云端已经运行通过。

发布使用文件白名单重新生成 ZIP 和 SHA-256，不能直接压缩日常使用目录。发布前须在另一台电脑或新的 Windows 用户环境完成实际客户端、任务触发和 VBS 禁用后的备用入口检查。当前版本为 beta，已验证机器和环境有限。

MIT License。保留上游版权及许可全文；贡献规则见 [CONTRIBUTING.md](CONTRIBUTING.md)，安全问题见 [SECURITY.md](SECURITY.md)。
