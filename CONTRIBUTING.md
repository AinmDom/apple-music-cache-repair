# Contributing

Use Windows PowerShell 5.1-compatible syntax. Keep PowerShell sources UTF-8 with BOM
and VBS/cmd launchers ASCII. Run `tests/Run-Tests.ps1` in Windows PowerShell and,
when available, PowerShell 7 before submitting a PR.

Never broaden deletion beyond the current-user Apple Music setupCert cache.
Keep missing paths, unexpected links, failed process enumeration, and failed backup
verification as refusal conditions. Add regression tests for changes to these rules.
Tests must use temporary fixtures and mocked task/process/shortcut adapters.

Describe user-visible changes and actual validation. Do not claim to have fixed all
Apple Music errors. Do not attach personal logs, real task exports, credentials,
music, or certificate backups. Reproduce failures with generated fixtures where possible.

Security reports belong in the private reporting channel described in SECURITY.md.
