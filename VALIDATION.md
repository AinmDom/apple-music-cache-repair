# Local validation for 0.1.0-beta.1

Validated on 2026-10-21 on one Windows 11 computer.

On 2026-10-22, the user reported completing ordinary installation and
uninstallation testing. This is user-reported confirmation; no additional
Windows or Apple Music version details were supplied. It does not establish
automatic task triggers, cross-machine repair, or VBS-disabled behavior.

| Check | Result |
|---|---|
| Windows PowerShell 5.1.26100.9711 | 52 isolated regression scenarios passed |
| PowerShell 7.6.5 | The same 52 scenarios passed |
| Real Apple Music registration and relocated Store AC cache discovery | Read-only CheckOnly passed |
| Native installation into a Unicode/space-containing temporary path | Passed, without a real automatic task or desktop shortcut |
| Native VBS launcher probe | Passed, child exit code 0 |
| Explicit PowerShell-only installation after VBS selection | Passed |
| Native uninstallation of the temporary configuration | Passed |
| Ordinary installation and uninstallation | User reported passed on 2026-10-22 |
| Release packaging in Windows PowerShell 5.1 and PowerShell 7 | Passed; 29 allowlisted files per archive, individually SHA-256 matched to source |

The review added six regression scenarios. All six failed against the original
runtime code and passed after fixes: growth beyond the size limit after directory
enumeration; cache changes, backup corruption, and app startup during manifest
writing; drive-relative paths; and restoring existing zero-byte files after a
failed upgrade. Certificate reads now check the opened file's size and exclude
writers while reading. Final path, backup, cache, and process checks occur after
manifest writing. These checks still do not make the final check/delete sequence
atomic; a concurrent change after the last check remains possible.

The initial sandboxed runs passed 43/46 original scenarios; three junction cases
could not create their generated links because of access restrictions. The final
52/52 runs above used permission to create links in isolated fixture directories.
Task, process, and shortcut operations remained mocked. The native installation
smoke check also mocked every task and shortcut adapter; it exercised actual file
installation, VBS probing, explicit PowerShell selection, and uninstallation only.

Regression cases cover exact filenames, unrelated-file preservation, verified
backups, corrupted backups, missing/oversize cache entries, nested and unexpected
junctions, process lookup errors, other sessions, default graceful exit,
explicit force close, structured outcomes, concurrent cleanup, optional tasks,
task/shortcut ownership checks, update rollback, uninstall rollback, and retrying
after a failed first install. Separate test runs use independent synthetic user
identifiers so they can run concurrently without sharing test locks.

The automated task, process-close and shortcut cases use adapters and temporary
fixtures. They do not certify actual logon/hourly/event triggers on every Windows
build. The public-version checks did not clear a real cache or terminate a real
client. The earlier machine-specific predecessor restored search on this computer;
that is not proof of the public version on other machines.

The upstream MIT notice and the workflow's pinned actions/checkout v7.0.1 commit
were checked against their upstream GitHub repositories during this review.

The GitHub Actions workflow is included but has not run remotely. Before a stable
release, validate actual repair and task triggers on another Windows installation
and test the PowerShell fallback with VBS disabled by system policy. Explicit
PowerShell selection on this computer does not certify that system-policy case.
