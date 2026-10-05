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
  Postgres.app must satisfy its designated requirement (team ZF84SJ5A3G).
- A build or payload has private modes only: folders and executables 0700, files 0600.
  No symbolic link, FIFO, or device is accepted.
- An install renames its staging folder into place with `RENAME_EXCL`: an existing folder
  is never replaced. One installation runs at a time. Cancellation stops it before the rename.
- A listing reports each build folder on its own. A bad folder does not hide the others.
- A release without a digest (MySQL, Laravel) matches its build by kind and version, so it
  shows as installed and is not downloaded again.
- Verification of an installed folder ignores only Finder's `.DS_Store`.
- A corrupt `cli-tools.json` is never reset. Later tool selections survive the bootstrap.
- Long file work runs on a GCD thread (`BlockingWork`), not on the cooperative pool.

## Bundle layout

`Contents/Resources/RuntimePayloads/runtimes.json` and
`RuntimePayloads/<group>/<payload ID>/payload-receipt.json` with the payload files. A
receipt must match its pin; folders without a pin are ignored. Installed folders are
`<group folder>/<folder ID>/` with the same receipt.

## Test

```sh
swift test --package-path Packages/JerdKit --filter JerdRuntimesTests
JERD_RUNTIME_NETWORK=1 swift test --package-path Packages/JerdKit --filter Live
```

Default tests use saved publisher responses, a fake `URLProtocol`, fake commands, and
temporary folders. Opt-in: `JERD_RUNTIME_INSTALL=mailpit,caddy` installs real releases,
`JERD_MYSQL_ARCHIVE` and `JERD_RUSTFS_BINARY` check real files.
