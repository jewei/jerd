# Verification record

Date: 2026-10-01. Host: Apple Silicon, macOS 27.0.1, Xcode 27.0, Swift 6.4.

## Passed

- 55 Swift Testing tests in 14 suites, including five real TLS/PHP cases,
  the real three-engine database test, the existing wildcard-port check,
  and the real SMTP/MIME persistence test.
- PHP 8.5.11 CLI and FPM, using the fixed `lerd-env/php` arm64 artifact.
- Caddy 2.11.4, using its official arm64 artifact.
- Direct high-port listeners and Caddy listeners inherited at descriptors 3/4.
- Two simultaneous sites with distinct roots and computed PHP output. One
  case shares a PHP process group; another uses separate runtime IDs and
  groups. Both run the available PHP 8.5.11 binary.
- A real TLS regression test first reproduced the public storage asset 404,
  then passed with the corrected route. It verifies exact asset bytes and
  `image/jpeg`, private project-root storage rejection, hidden-file rejection,
  and rejection of PHP execution and source under `/storage`, including
  directory URLs that would otherwise execute an uploaded `index.php`.
- Multiple-host updates, version 1 helper record migration, trust rollback,
  consent-scope checks, and removal of one hostname while retaining another.
- Version 1/2 trust-policy migration to version 3, preservation after failed
  approval, and restoration of server TLS trust after failed removal. A
  hostname-only consent cannot authorize broader server TLS trust. Old setup
  does not start under the new policy until the user approves the change.
- CA-verified TLS, computed PHP output and FPM SAPI, static content, sensitive
  path rejection, unknown hosts, redirects, and cleanup after FPM exit.
- Host byte/metadata preservation, conflicts, rollback, UID ownership checks,
  partial certificate-removal rollback, and interrupted-setup preservation.
- Coordinator rejection of missing setup and failed trust; socket release
  after engine failure; prompt listener restart without live-port sharing.
- Signed anonymous XPC transfer of both FileHandles, with the receiver retaining
  them after the sender closes its copies.
- Signed XPC rejection of incorrect client and server identifiers.
- Unsigned Debug build and signed Release build of app and helper.
- `codesign --verify --deep --strict` and the helper's read-only signing check.
- App launch, native window inspection, bundled runtime installation, and
  creation of the app's private configuration.
- Actual SMAppService registration and launch of the signed root helper.
- Actual host mapping, System.keychain import, and SSL trust limited to
  `games-jp.test`, approved through the logged-in app's Security.framework call.
- Safari loaded the selected Laravel site's home page without a trust warning.
  The page title was `ホーム | OneOne JP`. HTTPS returned HTTP 200.
- Normal macOS URLSession trust and hostname resolution; the app reported Ready.
- HTTP returned 308 to `https://games-jp.test/`.
- Actual loopback-only ports 80/443, with PHP/Caddy running as UID 501 and the
  helper as root. FPM used Jerd's private Unix socket.
- Stop released the listeners. Start and quit/reopen/start each restored HTTPS.
- Remove system setup restored the exact original hosts bytes, removed the
  tracked CA and its trust, and unregistered the helper. The project directory,
  `public/index.php`, site registration, and private installation CA remained.
- Setup was restored with the same CA. The site again reported Ready and HTTP 200.
- Composer 2.10.3 and Laravel Installer 5.32.0 were bundled and installed.
- New zsh sessions resolved `php`, `composer`, and `laravel` to Jerd's launcher.
  Version commands and `laravel new --help` passed without creating a project.
- Composer reported Jerd PHP 8.5.11 both outside a site and inside a nested
  directory of the registered site. Argument forwarding and exit status 23 passed.
- CLI selection tests cover a different pinned version, nested registrations,
  path boundaries, symlinks, a disabled web site, and missing-pin rejection.
- App data, saved runtime paths, generated server settings, and zsh commands
  use `~/Library/Application Support/Jerd`. After the directory move, site
  records, runtime IDs, default PHP selection, and CA bytes were unchanged.
  All three CLI commands passed; the site returned HTTP 200 over trusted HTTPS.
- The updated signed app loaded the existing single-host setup, then added
  the user-selected `games-hk` registration through the native folder form.
  Save opened the HTTPS review with both hostnames and the same CA fingerprint.
- Both hosts ran at the same time. `games-jp.test` returned 200;
  `games-hk.test` returned 302 to `/zh-hk`, which returned 200. Requests used
  normal macOS DNS and trust. The app showed Ready for both sites.
- System trust contained two SSL trustRoot rules, one per hostname. The owned
  hosts section contained both names. One unprivileged Caddy process and one
  shared PHP 8.5.11 process group served both project roots on loopback 80/443.
- Safari loaded both sites in the same window. The Hong Kong page title was
  `OneOne HK｜香港遊戲點數儲值平台`; the Japan page title was `ホーム | OneOne JP`.
- Stop all released ports 80/443. Start all restored both sites. Disabling
  `games-hk` left `games-jp` available and rejected the disabled HTTP host with
  421. Enabling it restored both sites without another setup change.
- The SHA-256 values for both projects' `public/index.php` files were unchanged.
  Both registrations remain enabled. PHP, Composer, and Laravel CLI version
  checks also passed after the app update, including Composer inside `games-hk`.
- The reported `https://games-hk.test/storage/112/amazon-us.jpg` initially
  returned an empty 404 even though its file and Laravel public storage link
  existed. The route blocked all storage URLs. After the fix and signed app
  update, the same URL returned 200, `image/jpeg`, and 14,338 bytes over normal
  macOS-trusted HTTPS. The response SHA-256 matched the source file exactly.
  Both site home pages still returned 200.
- Brave rejected the old hostname-limited CA trust with
  `NET::ERR_CERT_AUTHORITY_INVALID`. After the user approved the new scope,
  the updated app applied one SSL trustRoot rule for the same installation CA,
  without a hostname policy string. The system trust inspection confirmed
  that rule, and the app reported Ready. Both home pages returned 200 with
  normal macOS trust. The user confirmed that both sites now load in Brave.
  No browser certificate-warning bypass was used.
- The new app icon was present in the installed bundle, but the running app
  reported an empty icon and the menu bar still used a server symbol. The app
  now loads the bundled icon for both. After the signed update, macOS reported
  the correct running-app icon and a menu-bar capture showed the rainbow J.
  Both sites returned 200 after restart.
- The DBngin website, public repository screenshots, and installed DBngin
  27.0.1 window were inspected. The existing DBngin PostgreSQL and Redis
  processes remained running on ports 5432 and 6379.
- The database bootstrap verified Oracle's MySQL 8.4.11 signature, the fixed
  archive hashes, and the Postgres.app signature. PostgreSQL 18.6 and a local
  Redis 8.8.3 build passed actual version checks. The app installed all three
  independent runtimes from its bundle.
- The real database test started all three engines together, made SQL and
  Redis writes, rejected wrong passwords, and read the data after restart.
  It checked independent stop, unexpected exit, runtime identity mismatch,
  and retained data and credentials after registration removal.
- Database unit tests cover corrupt settings, immutable runtime selection,
  duplicate ports, retained files, private credentials, and graceful shutdown
  timeout. The timeout fixture remained tracked until a later graceful stop.
- Real Redis restart exposed a TIME_WAIT port-check failure. A closed-connection
  regression test and the three-engine test passed after the reuse correction.
  The installed-app check then exposed a distinct macOS wildcard-port case:
  a loopback Redis listener could share DBngin's wildcard port. Jerd's test
  service was stopped. Port checks now inspect existing TCP listeners before
  binding and verify exclusive ownership after startup. The separate read-only
  regression test rejected DBngin's port 6379 and preserved its listener list.
- The signed installed app created MySQL, PostgreSQL, and Redis services through
  the native form. Their final ports are 3306, 5433, and 6380. The updated Add
  form suggested 6381 for another Redis service: 6379 was occupied and 6380
  was already registered. No extra service was created.
- All three installed services passed authenticated queries. Their TCP listeners
  were restricted to `127.0.0.1`, with no UDP sockets, no shared database ports,
  and UID 501. Credential files had mode 0600. PostgreSQL Stop left MySQL,
  Redis, both DBngin processes, and both HTTPS sites available. PostgreSQL
  Start restored its authenticated query.
- Normal app quit stopped all three owned databases and retained each data
  folder and credential file. After app replacement and reopen, manual Start
  restored all three database connections and both trusted HTTPS sites.
  The final unsigned Debug build, signed Release build, and deep strict
  signature verification passed.

## Mail checks

- The official Mailpit 1.31.3 arm64 archive passed the fixed size and SHA-256
  checks. The binary reported its actual version without an online release
  check. Installed binary and notice files matched their receipts.
- The real SMTP test captured an encoded UTF-8 subject, plain text, HTML, and
  an attachment. The API returned the expected content and exact attachment
  bytes. Both messages remained after Stop, port edits, process restart, and
  recovery from an owned process exit.
- The test rejected an unknown HTTP Host with 403. Readiness checked the API
  version and private database path, an SMTP NOOP, both exact loopback listeners,
  exclusive port ownership, and absence of UDP sockets.
- Unit tests preserved corrupt settings, rejected runtime replacement and
  duplicate/privileged ports, and left occupied SMTP and web ports untouched.
  A saved live PID blocked startup without a signal. A version in the binary
  path did not pass an incorrect binary version. Integration checks preserved
  an initialized inbox when its database was missing or its identity differed.
- The installed signed app selected SMTP 1026 and web 8026 because the existing
  Homebrew Mailpit used 1025 and 8025. Its original PID 2115 remained alive.
  Jerd's Mailpit ran as UID 501, listened only on `127.0.0.1`, had no UDP
  sockets, and stored its SQLite database with mode 0600 in a private folder.
- The native Send test email button delivered `Jerd mail test` through SMTP.
  Open inbox opened `http://127.0.0.1:8026/` in Brave with title `Mailpit - Jerd`.
  A capture of the inbox content showed the test message in its message list.
- The native port editor rejected occupied SMTP port 1025 and kept the saved
  ports 1026/8026. The existing Homebrew Mailpit process remained alive.
- Stop mail retained the inbox. All three Jerd database queries still passed,
  both HTTPS sites returned 200, and the original external database and mail
  processes remained running.
- The same message ID, sender, recipient, and content remained after Stop/Start.
  Normal Quit stopped Jerd's mail and all three databases, released their ports,
  and retained the inbox. Original external services remained running.
- After reopen, the same message remained in Jerd's inbox. Mail returned to
  Ready on 1026/8026, all three database queries passed, and both HTTPS sites
  returned 200. The final signed Release and unsigned Debug builds passed.

The runtime inspection and real TLS tests use actual executables. Test doubles
are used only for controlled failure/transaction cases. Root access is not used
by the test suite. The separate approved system test changed hosts, trust, and
helper registration through the app. The user approved stopping Herd's web
service and selected the existing `games-jp.test` project. Other Herd services
were left running. Both selected sites remain available through Jerd.

The system test found and fixed three integration errors: first registration
can report SMAppService `notFound`; modern certificate consent needs the GUI
app; certificate deletion needs a keychain-backed item reference. Failed
cleanup restored the previous host/trust state before the fix was applied.
A test double also closed the same numeric descriptor twice during parallel
tests. Its cleanup is now idempotent. The restart test allows up to one second
for transient descriptor cleanup during parallel process tests. It separately
checks that an active listener cannot be shared. No `SO_REUSEPORT` is used.
The final full run passed all 55 tests.

The host's `/usr/bin/curl` has multiple TLS backends. Its default backend did
not use the installed macOS CA for this request. This command passed using
normal macOS trust, without a custom CA, resolver override, or TLS bypass:

```sh
CURL_SSL_BACKEND=secure-transport /usr/bin/curl --noproxy '*' \
  --silent --show-error --output /dev/null --write-out '%{http_code}\n' \
  https://games-jp.test/
```

## Reproduce the signed XPC check

Use an available Apple signing identity. This harness installs no service and
writes no host or trust settings. It binds only high loopback ports.

```sh
swiftc -swift-version 6 \
  Packages/JerdCore/Sources/JerdCore/Models.swift \
  Packages/JerdCore/Sources/JerdCore/ListeningSockets.swift \
  Packages/JerdCore/Sources/JerdCore/SystemIntegration.swift \
  Scripts/check-xpc.swift -o .build/check-xpc
codesign --force --sign 'Developer ID Application: Your Name (YOURTEAMID)' \
  --identifier dev.jerd.app --options runtime .build/check-xpc
.build/check-xpc
.build/check-xpc reject-client
.build/check-xpc reject-server
```

All three modes must print PASS and exit with status 0. On the tested host,
wrong client identity returned Cocoa error 4097; wrong server identity returned
4102. The harness uses the production protocol and signing requirement builder.
It does not establish that launchd registration or root certificate changes work.

## Manual system acceptance procedure

1. Stop the conflicting service in its own app. Keep a signed Jerd app in a
   stable location. Record the existing hosts file and relevant certificate state.
2. Add a trusted plain-PHP fixture. Check the suggested hostname and document root.
3. Review the enabled hostname list, fingerprint, and CA trust scope, then
   approve setup. The CA trust covers TLS server certificates for all hostnames.
   Complete macOS approval in Login Items & Extensions if required.
4. Confirm that the helper runs as root and that PHP/Caddy run as the current
   user. Confirm only loopback ports 80/443 listen; FPM uses a private Unix socket.
5. Confirm Ready, then open the hostname in Safari and Brave or Chrome. Check
   the certificate and execute PHP through HTTPS without a warning. Verify
   HTTP redirects to HTTPS.
6. Stop and start the environment. Check that the approved hostname still works.
7. Quit and reopen Jerd. Start again. Check that the same installation CA is used.
8. Add a second registration and approve the updated list. Check both sites
   at the same time. Disable and enable one site, then remove its registration.
   Check that the other site remains available and both project folders remain.
9. Remove system setup. Verify the recorded host section, exact CA trust/certificate,
   and helper registration are removed. Check that all project files remain.
10. Repeat with occupied ports and withheld approval. Check that the app reports
    the cause and never reports Ready. A port conflict must not change hosts/trust.

The original setup, browser, lifecycle, and full-removal sequence passed using
the user-selected Japan Laravel project. The concurrent-site check then passed
with the user's Hong Kong project. Both registrations were retained, so removal
of one host from a live multiple-host setup has core transaction and coordinator
coverage but still needs a separate GUI acceptance check. A deliberately withheld
GUI approval and an occupied-port attempt through the final signed helper also
need manual checks. Their core failure boundaries have automated coverage.
No new Laravel application was created as a test of the installer.

## Release limits

Intel execution, macOS 14 execution, notarization, separate-browser trust stores,
forced-crash recovery, and interrupted privileged transaction recovery are pending.
Execution with two different PHP binary versions is also pending; the separate
process-group test uses two runtime IDs for the available PHP 8.5.11 binary.
The developer signing identity is for local testing, not evidence of a release.
The development download pins are not publisher-signed manifests.
Database execution was checked on this arm64 Mac. The first database catalog
has one fixed version per engine and a development payload of about 1.1 GB.
More versions, release package size, database TLS, export/import UI, automatic
recovery after app crashes remain later work.
Mailpit runtime upgrades, multiple inboxes, and recovery after app crashes
are also pending. SMTP and HTTP use loopback without authentication or TLS.
