# JerdRuntimes

JerdRuntimes supplies runtimes: it reads publisher catalogs, downloads and verifies
releases, prepares and probes them, installs managed builds and bundled payloads, and owns
the Composer and Laravel tool record. All network access goes through `HTTPFetching`.

## Main types

| Type | Purpose |
| --- | --- |
| `RuntimeRelease`, `ReleasePolicy`, `HostAllowlist` | A release, rules R1–R5 for one candidate, and the one URL rule. |
| `URLSessionFetcher` (`HTTPFetching`), `MetadataCache` | HTTPS with a live byte limit and progress; a 5-minute shared cache. |
| `RuntimeCatalog`, `RuntimeUpdateCheck` | One source per publisher. Bad candidates are dropped, not fatal. |
| `RuntimePipeline`, `PreparationTools` | Download → verify → prepare → probe → permissions → hashes. |
| `PinnedRSAVerifier`, `PinnedRSAKey` | OpenPGP v4 signature check with Oracle's pinned MySQL key. |
| `PinnedLicense`, `CodeRequirement` | Hash-pinned license texts and the Postgres.app signing requirement. |
| `RuntimeInstaller`, `ManagedRuntimeStore`, `ManagedRuntime` | Managed builds in `runtime-updates/`. |
| `BundledRuntimeBootstrap`, `VerifiedPayloadInstaller` | First-launch installation of the bundled payloads. |
| `LegacyPayloadVerifier`, `LegacyInstalledPayload` | Verifies a payload folder that an older Jerd installed, before use. |
| `PinnedPayloadPreparer` | Prepares the pinned payloads for the app bundle (`./dev runtimes prepare`). |
| `CLICompanionStore`, `CLICompanions` | The only reader and writer of `runtimes/cli-tools.json`. |
| `ManagedExecutableVerifier` | Proves that a PHP executable is a managed file with its recorded digest. |

## Rules

- Every request, redirect, and final URL must be HTTPS on port 443 to a listed host,
  without user or password. The transfer stops as soon as it exceeds its byte limit.
- A release needs a SHA-256 or a pinned publisher signature (MySQL). The Laravel installer
  is verified by Composer only, and the Runtimes page says so.
- Managed updates and bundled payloads use the same preparers and version probes. PHP
  names come from the version. RustFS gets the reviewed XZ library instead of Homebrew's.
  Postgres.app must satisfy its designated requirement (team ZF84SJ5A3G). Its disk image is
  always ejected with `diskutil eject`, the replacement that macOS 27 names for the deprecated
  `hdiutil detach`. `hdiutil attach` stays until its replacement is known to work on macOS 14.
- A build or payload has private modes only: folders and executables 0700, files 0600.
  No symbolic link, FIFO, or device is accepted.
- An install renames its staging folder into place with `RENAME_EXCL`: an existing folder
  is never replaced. One installation runs at a time. Cancellation stops it before the rename.
- A listing reports each build folder on its own. A bad folder does not hide the others.
- A release without a digest (MySQL, Laravel) matches its build by kind and version, so it
  shows as installed and is not downloaded again.
- Finder's `.DS_Store` is the only file that verification ignores, on both sides: preparation
  deletes it before it records the files, and a receipt that records one still matches.
- A staging folder is locked (`flock`) while its installation runs. `removeAbandonedStaging()`
  of `RuntimeInstaller`, `BundledRuntimeBootstrap` (all four group folders), and
  `PinnedPayloadPreparer` removes only staging folders that nobody holds. Call them at start.
- A corrupt `cli-tools.json` is never reset. Later tool selections survive the bootstrap.
- Long file work runs on a GCD thread (`BlockingWork`), not on the cooperative pool. It runs
  inside the calling task (an actor on its own serial queue), so a cancellation stops a
  running hash, extraction, copy, or scan at its next chunk or entry.

## Bundle layout

`Contents/Resources/RuntimePayloads/runtimes.json` and
`RuntimePayloads/<group>/<payload ID>/payload-receipt.json` with the payload files. A
receipt must match its pin; folders without a pin are ignored. Installed folders are
`<group folder>/<folder ID>/` with the same receipt.

Folders that older builds installed (`<group folder>/<installation ID>/` with
`jerd-receipt.json` or `receipt.json`) stay in use, because old service records name them.
Verify one with `LegacyPayloadVerifier` each time before use: exactly the recorded files and
hashes, and the execute bit of each executable that the database form records.

## Test

```sh
swift test --package-path Packages/JerdKit --filter JerdRuntimesTests
JERD_RUNTIME_NETWORK=1 swift test --package-path Packages/JerdKit --filter Live
```

Default tests use saved publisher responses, a fake `URLProtocol`, fake commands, and
temporary folders. Opt-in: `JERD_RUNTIME_INSTALL=mailpit,caddy` installs real releases,
`JERD_MYSQL_ARCHIVE` and `JERD_RUSTFS_BINARY` check real files. `JERD_DISK_IMAGE=1`
attaches and ejects a small real disk image with the production commands: run it on each
new macOS, because the Postgres.app step depends on `hdiutil attach` and `diskutil eject`.
