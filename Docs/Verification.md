# Verification record

The checks below ran on Apple Silicon, macOS 27.0.1, Xcode 27.0, and Swift 6.4.
The latest check date is 2026-10-02. Commands are in [Run tests](Testing.md).
Earlier detailed records remain in Git history.

## App update checks

The isolated Sparkle test passed these cases with temporary signed apps.

| Case | Observed result |
| --- | --- |
| Signed empty feed | No update was offered |
| Altered signed feed | Verification failed before an update was offered |
| Altered archive | Verification failed before the install-ready state |
| Valid signed archive | Version 1 stopped before Sparkle installed and launched version 2 |
| Refused quit | Version 1 remained installed after refusal; a later graceful quit permitted replacement |

The fixture uses separate bundle identifiers, temporary data, a temporary signing
key, and high loopback ports. It does not use production data or the production key.
The tests use the isolated installer fixture. A production update with the registered
Jerd helper remains untested. Release preparation now has separate checks below.

The final Debug and signed Release builds passed. The built app contains build
number 2, the public GitHub HTTPS feed, the expected public key, and both signature
requirements. Strict recursive code-signature verification passed.
Three independent reviews covered code, architecture, and performance.
Their fixes strengthened signature assertions, delayed quit refusal, fixture
process cleanup, and the release-signing instructions. The revised tests passed.

The public GitHub feed downloaded over HTTPS and passed signature verification.
The installed build 2 checked that feed from both About and the app menu.
About displayed the completed status and last-check time. The automatic-check
switch saved both states and was restored to off.

Normal Quit released the owned service ports before atomic app replacement.
After relaunch, both sites returned HTTP 200 with normal TLS verification.
PostgreSQL and Redis passed authenticated queries. The mail inbox retained one
message, and a signed S3 list found the existing bucket.
DBngin's processes and the saved appearance preferences were unchanged.
The GitHub Actions core tests and Debug build passed on `macos-15`.

## Web and system integration

Real PHP/TLS tests passed with direct high-port listeners and inherited sockets.
The concurrent case used PHP 8.5.11 and 8.4.26 in separate process groups.
The cases cover computed PHP output, FPM SAPI, static files, redirects, unknown
hosts, sensitive paths, process exit, and cleanup with an isolated CA.
Laravel public storage tests verify exact asset bytes and reject private storage,
hidden files, PHP source, and PHP execution under the storage route.

The signed app served the two selected Laravel projects together on ports 80/443.
Both sites passed normal macOS HTTPS verification and loaded in Safari.
The user confirmed both sites in Brave after the approved server TLS trust change.
No certificate-warning bypass was used. Project entry-point hashes remained unchanged.

Helper checks passed registration, host mapping, CA import, GUI consent,
Start/Stop, quit/reopen, removal, and setup restoration.
Removal restored the original hosts bytes and removed the tracked CA and trust.
Core tests cover hostname-list changes, legacy trust migration, consent scope,
partial failure rollback, ownership conflicts, and interrupted transaction records.

The signed XPC harness passed socket transfer and incorrect client/server identity
rejection. The receiver retained its socket handles after the sender closed its copies.
PHP and Caddy ran as the user. The helper alone ran as root.

## CLI and runtime updates

New zsh sessions resolved PHP, Composer, and Laravel to Jerd's launcher.
Version checks, `laravel new --help`, argument forwarding, and exit status 23 passed.
The launcher selected site PHP from nested directories and the default outside sites.
Tests cover nested registrations, symlinks, path boundaries, disabled web sites,
and missing pins. No new Laravel project was created during these checks.

Real download and installation checks passed for all managed runtime sources.

| Runtime | Version checked |
| --- | --- |
| PHP | 8.4.26 installed beside 8.5.11 |
| Caddy | 2.11.6 |
| Composer | 2.10.3 |
| Laravel Installer | 5.32.0 |
| MySQL | 8.4.11 |
| PostgreSQL | 18.6 from Postgres.app 2.9.6 |
| Redis | 8.10.2 installed beside 8.8.3 |
| Mailpit | 1.31.3 |
| RustFS | 1.0.0 |

MySQL's publisher signature passed; altered data failed verification.
Archive tests cover traversal, unsafe links, bounds, and duplicate paths.
PostgreSQL checks cover read-only image mounting and cleanup after failures.
Fresh instances from each installed database package passed authenticated queries and restart.

The user's Laravel projects returned HTTP 500 with PHP 8.4.26.
Restoring PHP 8.5.11 restored HTTP 200. Runtime readiness does not establish project compatibility.
The installed Caddy remained 2.11.6. The PHP pins and project files were retained.

## Database checks

Real MySQL, PostgreSQL, and Redis tests passed writes, wrong-password rejection,
restart persistence, independent stop, process-exit detection, and retained data after removal.
Tests also cover duplicate ports, corrupt records, missing credentials, runtime mismatch,
incomplete initialization, and a shutdown timeout without forced termination.

Port tests cover TIME_WAIT restart and a macOS wildcard listener conflict.
The read-only occupied-port test rejected DBngin's Redis port without changing its process.
The installed Jerd services used distinct loopback ports and private credentials.
Normal Quit stopped owned services and retained their files.
Existing DBngin PostgreSQL and Redis processes remained running.

## Mail and storage checks

Mail tests passed SMTP capture of UTF-8, plain text, HTML, and attachments.
The API returned exact attachment bytes. Messages survived Stop, port changes,
restart, process-exit recovery, and a successful runtime change.
An invalid candidate restored the saved inbox and settings.
Unknown HTTP hosts were rejected. Missing initialized data remained an error.

Storage tests passed bucket creation on Save, policy readback, and HeadBucket.
Signed requests transferred binary data with UTF-8 keys, spaces, and reserved characters.
An independent curl SigV4 request interoperated with the native client.
Private reads rejected anonymous access. Public reads permitted only object reads.
Anonymous listing, writes, and deletion remained blocked.

Storage data, policies, and credentials survived Stop/Start and runtime changes.
Failure tests preserved incomplete setup, initialized data, credentials, and occupied ports.
Tests also covered interrupted backup recovery and restoration after an invalid candidate.
The RustFS console loaded at `/rustfs/console/`.

Installed-app checks passed Add bucket/Save, copied Laravel settings, the console,
mail test delivery, inbox display, and independent service controls.
Normal Quit released the owned data-service ports and retained the inbox and S3 objects.

## Dashboard and navigation

The signed app passed all five Dashboard pages at normal and minimum window sizes.
Dashboard cards changed to one column at the smaller size.
Settings and About commands selected the correct page and reopened a closed main window.
The two visibility switches worked independently in all four combinations.
Opening Jerd from Applications restored its window when both switches were off.
All seven icons were available. The user's original appearance values were restored.

Earlier code, architecture, and performance reviews resulted in corrected runtime
registration retries, image cleanup, independent service loading, and bootstrap checks.
File hashing now uses a 1 MiB buffer with an autorelease pool per chunk.
An isolated 87 MiB PHP hash needed 1 MiB of extra buffer memory after that change.

## Remaining test gaps

Intel execution, macOS 14 execution, and a published Jerd archive remain
unverified. Separate browser trust stores have no acceptance result.
A local signing identity alone does not establish distribution readiness.

Manual GUI checks remain for removal of one host from a live multiple-host setup,
withheld setup approval, and an occupied-port attempt through the final helper.
Core transaction and coordinator tests cover those failure boundaries.
Database withheld-shutdown and interrupted-initialization GUI checks remain incomplete.
Core tests now cover controller-exit recovery and interrupted privileged
transactions. Manual GUI checks of the new recovery actions, database registration
restore, backup cleanup, and shutdown stages remain incomplete. This reliability
change has no new signed release-candidate or browser-trust acceptance result.

Database TLS, database export/import UI, and multiple mail inboxes are not implemented.
SMTP and the data-service HTTP interfaces use loopback without TLS.

## Release preparation

Developer ID signing passed for the copied runtime payloads. The signed copies
passed the real PHP/TLS, MySQL, PostgreSQL, Redis, Mailpit, and RustFS tests with
private data and loopback ports. The checks include service restart and retained
data. The release copy of RustFS uses a library built from the pinned XZ source.
It does not load the Homebrew XZ library.

Release-script unit tests cover the first empty feed, increasing versions and
builds, unsafe paths, library relocation, and failure before public feed changes.
The release validator requires Apple acceptance and valid stapled tickets for
both the app and the DMG. Each completed candidate keeps its notary records,
runtime test log, source commit, artifact hashes, and retained symbols under
`.build/releases/`. Inspect those records for the selected candidate.

Three fresh independent reviews covered code, architecture, and performance.
The agreed changes removed inherited runtime-update test settings, retained
command output during failures, removed the unsafe outer service-test timeout,
and stopped new signing work after a failure. Regression tests cover these
conditions. The reviews found no further release-code blocker.
