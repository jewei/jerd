# Run tests

Run commands from the repository root. First prepare the required runtimes with
[Build Jerd](Build.md). Select trusted local binaries explicitly.

## Run core and service tests


Default tests need no root access and do not change system files or trust.
They cover site edit rollback, stale approval, cancelled preparation, no-op
starts, helper recovery stages, PID reuse, verified orphan shutdown, silent FPM
sockets, database registration restore, protected backups, and log limits.
Failure injection checks that uncertain process enumeration retains live-child
ownership, data locks, and recovery records. Helper reply tests cover status
cancellation, late replies, mutation completion, and timeout-task release:


```sh
swift test --package-path Packages/JerdCore
```

Run the real PHP/TLS tests with the prepared binaries:

```sh
JERD_INTEGRATION=1 \
JERD_PHP_CLI="$PWD/.build/development-runtimes/php/php-native-8.5" \
JERD_PHP_FPM="$PWD/.build/development-runtimes/php/php-native-fpm-8.5" \
JERD_CADDY="$PWD/.build/development-runtimes/caddy/caddy" \
swift test --package-path Packages/JerdCore
```

The test uses separate high loopback ports and an isolated CA. It verifies
TLS with `curl --cacert --resolve --noproxy '*'`; it never uses `-k`.
It compares effective CLI/FPM settings and observed modules, including CLI
`-n`, `-c`, `-d`, `PHPRC`, and `PHP_INI_SCAN_DIR` overrides.
It checks real PHP output, static files, sensitive paths, unknown hosts,
redirects, listeners, FPM failure, and cleanup. It runs both direct listeners
and inherited sockets. Two-site cases check separate roots with one shared
PHP group and with two separate PHP groups. To use a second PHP version, set `JERD_SECOND_PHP_CLI` and
`JERD_SECOND_PHP_FPM` to its trusted executables.
The public storage case verifies linked asset bytes and rejects private storage,
hidden files, PHP source, and PHP execution under the storage URL.
PHP client tests check cURL and OpenSSL stream requests between two isolated
HTTPS sites from both CLI and FPM. The trust decision is injected for the test CA;
no trust store is changed. Both clients reject an unapproved CA. Static-file
checks include favicon bytes, `robots.txt`, and JavaScript module content types.
The multiple-PHP-group test checks automatic cleanup after one group exits.
Set `JERD_KEEP_TEST_FILES=1` to retain diagnostic files.
Never install a test CA in a system trust store.

Run the real database test with the prepared independent runtimes:

```sh
JERD_DATABASE_INTEGRATION=1 \
JERD_DATABASE_RUNTIMES="$PWD/.build/database-runtimes" \
swift test --package-path Packages/JerdCore --filter Database
```

The test creates temporary instances of all three engines on high loopback
ports. It checks real writes, wrong-password rejection, persistence after
restart, independent shutdown, process-exit detection, version mismatch,
and retained data and credentials after registration removal and restore. No existing databases are used.

The separate `JERD_OCCUPIED_DATABASE_PORT` option enables a read-only regression
check against an existing wildcard TCP listener. It checks that registration
rejects the port without changing or connecting to that service. This passed
with DBngin Redis on port 6379.

Run the real SMTP and inbox test with the prepared Mailpit binary:

```sh
JERD_MAIL_INTEGRATION=1 \
JERD_MAIL_RUNTIME="$PWD/.build/mail-runtime/mailpit-1.31.3-arm64" \
swift test --package-path Packages/JerdCore --filter Mail
```

It uses a temporary inbox and high loopback ports. It sends a MIME message over SMTP and reads text, HTML, and attachment bytes
through the API. It also rejects an unknown HTTP Host, changes ports, and
checks persistence after restart. It also checks
process-exit detection, missing-database preservation, and runtime identity.
Plain messages without Date or Message-ID headers, multiple To/CC addresses,
and retained messages after restart are also checked.
It does not access an existing inbox or configure external mail delivery.

The storage test uses an explicitly selected RustFS runtime and temporary data:

```sh
JERD_STORAGE_INTEGRATION=1 \
JERD_STORAGE_RUNTIME="$PWD/.build/storage-runtime/rustfs-1.0.0-arm64" \
swift test --package-path Packages/JerdCore --filter StorageIntegrationTests
```

It checks automatic bucket startup, signed S3 reads and writes, public/private
access, persistence, port conflicts, credentials, and interrupted setup retry.


## Review the native interface

Build the Debug app with the standard Xcode build command, then run:

```sh
python3 Scripts/Checks/capture-ui.py
```

The script compiles a separate preview app from the current UI source. It uses
in-memory examples and does not call app startup, service actions, runtime
installation, the updater, or system setup. Pointer input is blocked in its
workspace. It opens a temporary review window and captures that window only.
A macOS graphical session and screen capture access are required.

Images are saved in `.build/ui-review/screenshots-final`. Check the main pages in
light and dark modes at standard and minimum window sizes. The examples cover
empty and populated pages, the lower form sections, long site names, and service running, error, and busy
states. These are visual fixtures; they do not prove service health. The capture
does not verify keyboard navigation, VoiceOver, or dialogs.

To check section changes with pointer input enabled, run:

```sh
python3 Scripts/Checks/capture-ui.py navigation
python3 Scripts/Checks/capture-ui.py navigation-compact
```

These modes record normal and rapid tab clicks at 980 × 660 and 820 × 540.
They check selection agreement, a fixed section control, retained page controllers,
sidebar width and collapsed state, native next/previous selection, and retained
scroll position. They also open site and storage editors with in-memory presentation
state and check dismissal with Escape. No Save or service action is invoked.
Movies are saved beside the screenshots. Inspect transitions frame by frame for
page overlap, intermediate widths, and sidebar movement. Check VoiceOver and the
full keyboard workflow separately before a release.

## Check signed XPC


Use an available Apple signing identity. This harness installs no service and
writes no host or trust settings. It binds only high loopback ports.

```sh
swiftc -swift-version 6 \
	Packages/JerdCore/Sources/JerdCore/Common/Models.swift \
	Packages/JerdCore/Sources/JerdCore/Web/ListeningSockets.swift \
	Packages/JerdCore/Sources/JerdCore/SystemIntegration/SystemIntegration.swift \
	Scripts/Checks/check-xpc.swift -o .build/check-xpc
codesign --force --sign 'Developer ID Application: Your Name (YOURTEAMID)' \
	--identifier dev.jerd.app --options runtime .build/check-xpc
.build/check-xpc
.build/check-xpc reject-client
.build/check-xpc reject-server
```

All three modes must print PASS and exit with status 0.


## Check Sparkle installation

Resolve Sparkle into `.build/SourcePackages` with the build command in [Build Jerd](Build.md).
Then run the isolated updater test with an available Apple signing identity:

```sh
python3 Scripts/Checks/check-app-updates.py \
	--identity 'Developer ID Application: Your Name (YOURTEAMID)'
```

Expect PASS for the empty feed, altered feed, altered archive, successful update,
and cancelled quit followed by a retry. The script creates temporary signed apps
and a temporary signing key. It serves the fixtures over a high loopback HTTP port.
It does not read Jerd's settings or use the production signing key.

## Check approved system setup

This procedure changes hosts and trust. Obtain explicit approval for the selected
projects and system changes before you start. Default tests do not require this procedure.


1. If a conflicting service must stop, obtain explicit approval to stop it through its own app.
2. Keep the signed Jerd app at a stable location.
3. Record the current hosts file and relevant certificate state.
4. Add a trusted plain-PHP fixture.
5. Check its suggested hostname and document root.
6. Review the hostname list, CA fingerprint, and TLS trust scope.
7. Approve setup.
8. If macOS requires approval, complete it in **Login Items & Extensions**.
9. Confirm that the helper runs as root and PHP/Caddy run as the current user.
10. Confirm that ports 80/443 listen only on loopback and FPM uses a private Unix socket.
11. When Jerd reports **Ready**, open the hostname in Safari and Brave or Chrome.
12. Check the certificate and PHP response without a warning bypass.
13. Verify the HTTP-to-HTTPS redirect.
14. Stop and start the environment.
15. Verify that the approved hostname still works.
16. Quit and reopen Jerd.
17. Start the environment again.
18. Verify that Jerd uses the same installation CA.
19. Add a second registration and approve its updated hostname list.
20. Verify both sites at the same time.
21. Disable and enable one site.
22. Remove that registration.
23. Verify that the other site remains available and both project folders remain.
24. Remove system setup.
25. Verify removal of the recorded hosts, exact CA certificate/trust, and helper registration.
26. Verify that all project files remain.
27. Repeat with occupied ports and withheld approval.
28. Confirm that a port conflict causes no host/trust change and does not report **Ready**.

For completed checks and remaining gaps, see the [verification record](Verification.md).

## Release preparation checks

Run the release failure and CLI setup checks without signing or network access:

```sh
/usr/bin/python3 -m unittest discover -s Scripts/Tests -v
```

CLI setup tests use a temporary home directory. They check version metadata,
bundled and updated PHP receipts, repeated setup, and shell symlink preservation.
They do not write to the user's shell files.

`Scripts/release.sh prepare VERSION BUILD` also runs the full core suite with
explicit paths to the signed candidate runtimes. These tests use private data,
loopback ports above 1023, and an isolated CA. They do not change hosts, trust
stores, installed apps, or existing service data. The opt-in
`JERD_RELEASE_RESOURCES` test verifies installation from signed bundle receipts.

## Tunnel checks

The default core suite uses temporary directories and injected tunnel transports
and secret stores. It checks saved settings, token separation, duplicate tokens,
process ownership, connection state, retry, graceful stop, and failed shutdown.
Log tests check tokens split across writes and bounded buffering. No real tunnel
or existing cloudflared process is used by these tests.

After a Debug build, capture the tunnel views with memory-only fixtures:

```sh
python3 Scripts/Checks/capture-ui.py tunnel-stopped,tunnel-connected,tunnel-error
```

For an approved live check, use a separate test tunnel and its token. Confirm its
remote route first. Check Connect, loss of network, reconnect, Stop, Quit, and
optional startup. Confirm loopback-only metrics, token-free logs, and that any
separate connector continues to run. A live test of the user's current tunnel
requires a separate instruction; default tests do not start or stop it.
