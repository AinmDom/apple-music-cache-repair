[简体中文](README.md) | [English](README.en.md)

# Apple Music Cache Repair

A `setupCert` certificate-cache repair tool for Apple Music on Windows. It backs up and removes only the matching cache files. It does not reset the app or clear downloaded music, your library, or sign-in data.

This is an MIT-licensed improvement based on [mikepink/music-on-windows11-unknown-error-fix](https://github.com/mikepink/music-on-windows11-unknown-error-fix). See [NOTICE.md](NOTICE.md) for attribution and changes. This is not an official Apple product. It addresses this specific type of certificate-cache problem and cannot guarantee a fix for every “unknown error,” network issue, or account problem.

## Requirements and quick start

- Windows 11, the Microsoft Store version of Apple Music, and the built-in Windows PowerShell 5.1.
- Runs with ordinary user permissions. It does not download or execute remote code, or change your proxy, DNS, system certificates, or system execution-policy settings.
- Requests a normal app shutdown by default. If background processes remain active, the cache is retained. Force-closing requires an explicit choice.
- Repair interrupts playback. Avoid running it while importing music, syncing, or editing your library.

Download and extract the release ZIP, then double-click `Repair.cmd` to run it directly. A success message means the cache operation completed; you still need to check search and playback in Apple Music.

If Windows warns that the source is untrusted, verify the release checksum and review the source code first. Do not disable system security features. If organizational policy blocks scripts, contact your device administrator.

## Installation and shortcuts

Double-click `Install.cmd`. By default, it installs to `AppleMusicCacheRepair` under the current user's local application-data directory and creates a desktop shortcut. **No automatic task is added by default.** Keep the installed directory in place. Do not install to a drive root, the original source directory, a directory writable by other users, or a path containing symbolic links.

To choose an installation directory, run this in PowerShell, for example:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -InstallDirectory "E:\Tools\Apple Music Repair"
```

You do not need to create the directory first. The installer refuses to overwrite an existing directory, task, or shortcut that does not belong to this project. To upgrade, run the same command from the new version's directory and select the existing installation path. If installation fails, it restores the previous scripts, configuration, task, and shortcut. If rollback also fails, the error message lists those failures.

Add `-NoDesktopShortcut` if you do not want a desktop shortcut. The installer checks whether the optional hidden VBS launcher can run and uses a PowerShell entry point if it cannot. You can also select PowerShell explicitly with `-PowerShellOnly`. The fallback may briefly display a window. The repair code itself does not depend on VBS. If Windows disables VBS after installation, use `Repair.cmd` or reinstall with `-PowerShellOnly`.

`-ExecutionPolicy Bypass` applies only to the current process. The scripts do not change the system's execution-policy configuration.

## Optional automatic repair

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Automatic
```

This adds a task for the current user that runs 30 seconds after sign-in and every hour. It uses the current user's interactive logon token and ordinary permissions, stores no password, and never terminates processes. It skips cleanup while Apple Music or its background agent is running.

Add `-ExitTrigger` if you also want to run after a packaged desktop app exits. This option listens for AppModel-Runtime event 217 and **is triggered by the exit of any packaged desktop app**. The script then checks whether there is work to do. It is optional to avoid frequent background launches by default. App updates generally do not require rebuilding this trigger.

Reinstalling preserves existing automatic-task options. Use `-DisableAutomatic` to turn automatic cleanup off explicitly. Upgrading does not take over tasks created by the upstream tool or other tools. Disable those with their original tool first to avoid duplicate cleanup.

The task is named `Apple Music Cache Repair - <current user SID>`. By default, it does not clean the cache immediately after installation. After first enabling automatic cleanup, check the task's last run result and `data\cleanup.log` to confirm execution. Successful task registration alone does not prove that the repair script ran.

## Command line, preview, and results

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Repair.ps1 -Preview -NoUi
powershell -NoProfile -ExecutionPolicy Bypass -File .\Repair.ps1 -CheckOnly -NoUi
powershell -NoProfile -ExecutionPolicy Bypass -File .\Repair.ps1 -NoUi -NoRelaunch
```

Preview does not close or relaunch the app or delete cache files, but it writes an operation log under `data`. `-CheckOnly` checks app registration and paths without cleaning the cache. Command-line output is the JSON result for that invocation; there is no need to infer the result from the last line of a shared log.

`-ForceClose` explicitly authorizes forced termination and is off by default. It only terminates processes in the current session whose executable paths have been verified as belonging to the Apple Music installation package. The graphical entry point asks for confirmation if background processes do not exit. Cleanup is refused if Apple Music processes are still detected in another session.

| Code | Status | Meaning |
|---|---|---|
| 0 | Repaired / NoMatch / Preview / CheckPassed | Cleanup succeeded, no matching files, preview completed, or checks passed |
| 1 | Error | Operation or log-writing failure; the result retains the list of files already completed |
| 2 | MissingCache | Cache directory is missing or inaccessible |
| 3 | Running | The app is still running; cleanup was refused |
| 4 | Busy | Another repair or cleanup is in progress |

The background entry point treats `Running` as an expected skip and returns 0. Other failures are passed to Task Scheduler. `Relaunch=Requested` means only that an app-launch request was sent; `Observed` means a client process was detected. Neither confirms that search or playback has recovered.

## Cleanup scope and backups

Only complete filenames matching the following are selected inside the current user's `Packages\AppleInc.AppleMusicWin_nzyj5cx40ttqa\AC\INetCache`:

- `setupCert.xml` and `setupCert.plist`
- `setupCert[digits].xml` and `setupCert[digits].plist`, where the brackets contain one or more digits, such as `setupCert[23].xml`

Files ending in `.bak` or `.old`, other `setupCert*` names, and the MediaServices `data` database are not cleaned. A target larger than 1 MiB causes an error. gzip content, plain content, and empty files are all backed up and verified with SHA-256 before deletion.

Supported layouts include a normal local installation and a Store installation whose `AC` directory is mapped to `WpSystem\<current user SID>\AppData\Local\Packages\<same package family>\AC` on another drive. Drive letters are detected automatically. Other link layouts and links nested inside the cache are not followed. If your directory layout is not recognized, report a description with personal details removed. Do not bypass the error by weakening path checks.

All runtime data is stored under `data` in the installation directory:

- `cleanup.log`: log records with the current RunId; the previous log is retained when the file grows beyond approximately 512 KiB.
- `certificate-backups`: certificate-content backups deduplicated by SHA-256, without copying EFS encryption metadata.
- `backup-manifest.jsonl`: original relative cache paths, hashes, sizes, and RunId. A backup record does not prove that the original was deleted; check `Removed` in the invocation's result.

Backups do not expire automatically. The original cache files' system encryption settings are not changed. Restoring an old gzip cache is generally discouraged because the problem may return. If you need to restore a backup, first disable automatic cleanup and exit Apple Music. Verify the backup hash against the manifest, then copy it to its corresponding original location only if that path does not exist. Do not overwrite files the client has regenerated.

After writing the backup manifest and before deleting a file, the script rechecks processes, the backup, file hashes, and paths. The final check and deletion are not atomic: a brief race remains if the client starts or a file changes after the last check. Do not open Apple Music manually during repair.

## Uninstallation and privacy

Run `Uninstall.cmd` from the installed directory. It removes this project's task and desktop shortcut while retaining scripts, logs, and backups. You can delete the installation directory manually once you no longer need it. If uninstallation fails, it attempts to restore the original configuration.

Do not upload `data`, `install.json`, personal logs, backups, task XML, or generated shortcuts to GitHub. Installation configuration and error logs may contain paths or user SIDs. Remove personal details before reporting an issue. Public certificate backups do not need to be uploaded either. The tool has no telemetry, automatic updater, or remote log upload.

## Development and validation

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Release.ps1
```

Tests operate only in temporary directories. Scheduled tasks, app processes, and shortcuts are tested through mocked adapters; tests do not terminate the real client or modify the user's tasks. The core tests run under Windows PowerShell 5.1 and PowerShell 7; user-facing entry points consistently call Windows PowerShell 5.1. GitHub Actions is configured to run on pushes and pull requests, but merely including a workflow does not establish that a hosted run passed. See [VALIDATION.md](VALIDATION.md) for recorded results and limitations.

Releases are rebuilt from a file allowlist with a ZIP and SHA-256 checksum. Do not simply archive a directory used for day-to-day repair. Before publishing a release, check the actual client, task triggers, and fallback entry point with VBS disabled on another computer or in a new Windows user environment. This version is beta and has been validated on a limited set of machines and environments.

MIT License. Retain the upstream copyright notice and the full license text. See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines and [SECURITY.md](SECURITY.md) for security reports.
