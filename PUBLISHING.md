# 发布准备

本目录是可独立上传的开源源码，不包含用户运行数据。不要上传原先日常使用的修复目录。

1. 在你自己的 GitHub 账户创建仓库，例如 `apple-music-cache-repair`。上传本目录内容，保留 `.github`、`.gitignore`、LICENSE 和 NOTICE.md；不要再额外生成一个会覆盖现有声明的许可证。
2. README 已注明基于上游工作。保留 Mike Pinkowish 的 MIT 版权声明；你可以为自己新增的贡献添加真实署名，不要将上游代码改称全部原创。
3. 在仓库设置中启用 private vulnerability reporting，检查公开仓库的秘密扫描和推送保护设置。仓库不需要任何令牌、Apple 账户或运行日志。
4. 确认 GitHub Actions 的两种 PowerShell 测试及打包步骤通过。附带工作流配置不代表远端 CI 已经执行。
5. 在另一台 Windows 11 电脑或新用户环境中实测安装、搜索/播放恢复、登录和小时触发、卸载，以及禁用 VBS 后的 PowerShell 备用入口。模拟测试无法代替这些客户端检查。
6. 在源码目录运行 `tools\Build-Release.ps1`，生成白名单 ZIP 和 SHA-256。不要直接压缩安装目录。
7. 首次发布建议使用标签 `v0.1.0-beta.1`，附上生成的 ZIP、`.sha256` 和 CHANGELOG 中对应说明。声明当前验证范围，不保证修复所有“未知错误”。

项目代码、文档和发布包在本地准备完毕，不会自动创建仓库、推送提交或发布 Release。
