# Implementation plan

The user approved completion of the real Milestone 1 proof and work on
Milestone 2. The user then confirmed that Jerd must serve all enabled registered
sites at the same time. Keep the app small and honor each site's PHP selection.

## Completed and tested

- Native SwiftUI app, menu controls, site records, document-root checks,
  `.test` hostname suggestions, and versioned atomic persistence.
- PHP 8.5.11 and Caddy 2.11.4 development artifacts, with fixed digest pins,
  bounded downloads, receipts, license notices, and app-owned installation.
- Real unprivileged PHP over CA-verified TLS on high loopback ports.
- Caddy inherited-socket support, restricted routes, process supervision,
  readiness checks, runtime-exit cleanup, and socket restart behavior.
- Signed XPC socket transfer and rejection of incorrect code identities.
- Host-file byte/metadata preservation, conflict detection, ownership checks,
  transaction rollback, and cleanup through test boundaries.
- Signed Release build, signature verification, app launch, and automatic
  runtime installation on the development Mac.
- Official Composer 2.10.3 and Laravel Installer 5.32.0 in the app payload.
- Optional native PHP/Composer/Laravel commands that select each registered
  project's PHP, with default selection outside projects and no pin fallback.
- Concurrent sites through one Caddy process, with separate routes and one
  PHP-FPM process group per selected runtime.
- Hostname-list setup, explicit CA trust policies, version 1/2 helper record
  migration, rollback, and removal of one host while retaining the others.
- Two-site real PHP/TLS tests with shared and separate PHP process groups.

## Milestone 2 system checks completed on the development Mac

- SMAppService helper with mutual signing requirements and typed XPC.
- Explicit setup screen with hostname and CA fingerprint.
- One owned host section and CA trust limited to TLS.
- Standard loopback sockets supplied to unprivileged Caddy.
- Start/Stop/Open actions; Ready requires normal system-trusted HTTPS.
- Removal of recorded host/trust state and helper registration.
- Safari page load, HTTP 200 with normal macOS trust, and HTTP-to-HTTPS redirect.
- Start/Stop, quit/reopen, removal of setup, and setup restoration.
- Both `games-jp.test` and `games-hk.test` served together over trusted HTTPS.
  Both loaded in Safari. Stop all, Start all, and disable/enable of one site passed.

The user approved stopping Herd's web service and chose `games-jp.test` for the
system test. The user then selected `games-hk.test` for the second-site check.
Both sites are running in Jerd. The test found and fixed first-time
helper registration, GUI certificate consent, and persistent certificate
deletion errors. Exact host restoration and preservation of the project entry
point were checked after cleanup. See Verification.md for remaining coverage.

## Later work

Milestone 3 concurrency is implemented. Remaining work includes testing two
different PHP binary versions together, editable per-runtime settings,
restart of only affected processes, and configuration rollback.

Milestone 4 adds reproducible runtime builds for each supported architecture,
signed release metadata, updates with rollback, notarized distribution, and
full uninstall. The current GitHub/HTTPS development bootstrap is not that
release system. Crash recovery and interrupted helper transaction recovery
also need completion before a production release.
