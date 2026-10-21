# Attribution

This project is derived from the MIT-licensed certificate-cache workaround in
[mikepink/music-on-windows11-unknown-error-fix](https://github.com/mikepink/music-on-windows11-unknown-error-fix).
The upstream copyright notice is preserved in LICENSE.
The reviewed upstream installer has Git blob SHA `3db67f5f896a9a8d50bb0c5a703f33cd850c3c33`.

The upstream investigation identified the gzip-encoded setupCert response as a
possible trigger on its test machine. This project adds strict filename and path
checks, verified backups, structured outcomes, manual repair, configurable
installation, transactional task/shortcut updates, and automated regression tests.
It does not claim that all Apple Music errors have the same cause.

Apple Music is a trademark of Apple Inc. This is an unofficial community tool,
not affiliated with or endorsed by Apple. No Apple binaries, logos, credentials,
music, or certificate-cache samples are distributed.
