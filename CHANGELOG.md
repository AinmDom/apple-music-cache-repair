# Changelog

## 0.1.0-beta.1

- Initial public-source preparation based on the upstream setupCert workaround.
- Drive-independent current-user cache discovery and restricted Store junction handling.
- Exact cache filename matching, SHA-256 verified byte backups, and per-run JSON results.
- Graceful close by default; force-close requires an explicit option or UI confirmation.
- Optional user-level automatic task; broad packaged-app exit trigger is opt-in.
- Task and shortcut identity checks, installation/uninstallation rollback, repeatable updates.
- Optional VBS launcher with automatic PowerShell fallback and portable command entrypoints.
- Isolated regression suite, Windows CI configuration, and allowlisted release packaging.
- Pre-publication review: bounded certificate reads, post-manifest deletion checks,
  rejection of drive-relative paths, and rollback preserving existing empty files.
- 52 isolated regression scenarios passed under Windows PowerShell 5.1 and PowerShell 7,
  both locally and in GitHub Actions; actual task/client checks on another Windows
  installation and VBS-disabled behavior remain pending.
