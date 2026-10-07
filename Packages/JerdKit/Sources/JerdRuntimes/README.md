# JerdRuntimes

JerdRuntimes gives the app its runtimes. It reads publisher catalogs, downloads and
verifies releases, and prepares and probes them. It installs managed builds and bundled
payloads, and owns the Composer and Laravel tool record. All network access goes through `HTTPFetching`.

## Main types

| Type | Purpose |
| --- | --- |
| `RuntimeRelease`, `ReleasePolicy`, `HostAllowlist` | A release, rules R1–R5 for one candidate, and the one URL rule. |
| `URLSessionFetcher` (`HTTPFetching`), `MetadataCache` | HTTPS with a live byte limit and progress; a 5-minute shared cache. |
| `RuntimeCatalog`, `RuntimeUpdateCheck` | One source per publisher. Bad candidates are dropped, not fatal. |
| `RuntimePipeline`, `PreparationTools` | Download → verify → prepare → strip → probe → permissions → hashes. |
| `SymbolStripping`, `SymbolStripper` | The pinned rule that removes local symbols from some executables, and the step that applies it. |
| `MinimumMacOS`, `SourceBuildCheck` | The oldest macOS of the app, which a source build targets and must declare. |
| `PinnedRSAVerifier`, `PinnedRSAKey` | OpenPGP v4 signature check with Oracle's pinned MySQL key. |
| `PinnedLicense`, `CodeRequirement` | Hash-pinned license texts and the Postgres.app signing requirement. |
| `RuntimeInstaller`, `ManagedRuntimeStore`, `ManagedRuntime` | Managed builds in `runtime-updates/`. |
| `BundledRuntimeBootstrap`, `VerifiedPayloadInstaller` | First-launch installation of the embedded payloads. |
| `OnDemandRuntimes`, `RuntimePin.release(...)` | The pinned releases that the app does not embed (MySQL, PostgreSQL, and RustFS), for `RuntimeInstaller`. |
| `BundledSupportLibrary` | The XZ library that the app embeds on its own (`RuntimePayloads/support/xz`), verified against its receipt and the pinned XZ source. |
| `DiskSpace` | Recognizes a full volume in any step, for one clear message. |
| `LegacyPayloadVerifier`, `LegacyInstalledPayload` | Verifies a payload folder that an older Jerd installed, before use. |
| `PinnedPayloadPreparer` | Prepares the pinned payloads for the app bundle (`./dev runtimes prepare`). |
| `CLICompanionStore`, `CLICompanions` | The only reader and writer of `runtimes/cli-tools.json`. |
| `ManagedExecutableVerifier` | Proves that a PHP executable is a managed file with its recorded digest. |

## Rules

- Every request, redirect, and final URL must be HTTPS on port 443 to a listed host,
  without user or password. The transfer stops as soon as it exceeds its byte limit.
- A release needs a SHA-256 or a pinned publisher signature (MySQL). The Laravel installer
  is verified by Composer only, and the Runtimes page says so.
- The selection rules leave out files whose library references cannot resolve inside the payload,
  because Jerd never rewrites the load commands of a signed upstream file: for MySQL the debug
  plugins (`lib/plugin/debug/`) and the WebAuthn client plugin with its private
  `lib/plugin/libfido2.1.dylib` (an upstream link, so its `@loader_path` breaks as a file); for
  PostgreSQL the ICU tool libraries `libicuio`, `libicutest`, and `libicutu`, which name their
  dependencies by bare file name. No server and no default account uses them. `./dev runtimes
  verify` checks every reference. A changed file set gives a new payload folder ID; installed
  folders and registered services stay valid, because reuse and `runtime-updates/` match by pin
  and digest, not by file set.
- After the preparer and before the probe, `SymbolStripper` runs `/usr/bin/strip -x` on the files that
  `SymbolStripping` names: the PHP CLI and FPM, `mailpit`, and Redis `bin/redis-server` and `bin/redis-cli`.
  Then `codesign --verify --strict` must accept each file, and the probe runs the stripped files, so the
  receipt and the release signer cover them. `-x` keeps the global symbols; `-S` saves almost nothing on
  these builds. The listed files carry an ad-hoc linker signature, which `strip` writes again. Caddy
  (`strip` refuses it), RustFS (no gain), MySQL, PostgreSQL, and the PHP scripts stay as they are.
  `./dev runtimes prepare` requires the step (`.required`). The app strips only when `xcode-select -p`
  names a developer folder (`.whenDeveloperToolsExist`), so an update never asks for the Command Line
  Tools. Stripped files give a new payload folder ID; installed folders stay valid.
- Managed updates and bundled payloads use the same preparers and version probes. PHP
  names come from the version. RustFS gets the reviewed XZ library instead of Homebrew's:
  `LZMALinker` copies `liblzma.5.dylib` and its license into the installed runtime, so the
  runtime keeps the library it loads. `bundledLZMA()` takes it from `support/xz` of the app
  (checked against `SupportReceipt` and the pinned source), or from an embedded RustFS payload
  of an older catalog; nil in a development build without it.
  Postgres.app must satisfy its designated requirement (team ZF84SJ5A3G). Its disk image is
  always ejected with `diskutil eject`, the replacement that macOS 27 names for the deprecated
  `hdiutil detach`. `hdiutil attach` stays until its replacement is known to work on macOS 14.
- A runtime that Jerd builds from source (today Redis, `RuntimePreparing.buildsFromSource`)
  targets `MinimumMacOS`, the oldest macOS of the app, not the macOS of the build Mac. The
  app reads it from `LSMinimumSystemVersion` of its Info.plist (`LiveConfiguration`); `./dev`
  reads `MACOSX_DEPLOYMENT_TARGET` of `Configuration/Base.xcconfig`. The Redis `make` gets
  `MACOSX_DEPLOYMENT_TARGET`, and `-arch arm64 -mmacosx-version-min=<minimum>` in `CFLAGS` and
  `LDFLAGS` through the environment, because a `make` argument would replace the flags of
  each Redis dependency. After the build, `SourceBuildCheck` refuses the payload when a
  Mach-O file declares a newer minimum (`LC_BUILD_VERSION` or `LC_VERSION_MIN_MACOSX`) and
  names each file and both versions. Jerd then installs nothing.
- A build or payload has private modes only: folders and executables 0700, files 0600.
  No symbolic link, FIFO, or device is accepted.
- An install renames its staging folder into place with `RENAME_EXCL`: an existing folder
  is never replaced. One installation runs at a time. Cancellation stops it before the rename.
- A listing reports each build folder on its own. A bad folder does not hide the others.
- The app does not embed a pin that the catalog marks `"embedded": false` (today MySQL,
  PostgreSQL, and RustFS; Redis and Mailpit stay embedded). `installStorage()` returns nil then. `BundledPayloadSource` skips it and
  `BundledRuntimeBootstrap` installs nothing of it and downloads nothing. `OnDemandRuntimes`
  turns each such pin into a `RuntimeRelease` with the exact URL, size, SHA-256, the reviewed
  MySQL signature file, and the pinned `engineVersion`, which the probe must report and which
  names the release (`PostgreSQL 18.6`); the app installs it only after a user
  action, with `RuntimeInstaller` into `runtime-updates/`. `./dev runtimes prepare` uses the
  same mapping (`RuntimePin.release(architecture:catalogDirectory:)`), pipeline, and preparers.
  A download that does not match its pin installs nothing. The download progress names the
  bytes of the exact size (`Downloading MySQL 8.4.11… 70.6 MB of 168 MB`); `ByteText` is the
  one byte format of the app.
- `OnDemandRuntimes.reusablePayload(for:layout:)` finds a payload folder of an on-demand pin that
  an earlier copy installed from its bundle (current or legacy form), so Jerd registers it again
  instead of a download. A folder that does not match stays as it is. The group folder and the
  payload folder must be real directories of the user inside the data root; a link is never
  followed. What the check proves: the folder holds exactly the files of its own receipt, and the
  receipt names the pin (ID, kind, release, archive digest, architecture, and folder ID). It does
  not prove the origin, because the receipt is in the folder. The trust boundary is the same user,
  who owns the data root, as for every installed runtime. `hasReusablePayload` reads receipts
  only, for the dialog that says "Nothing is downloaded"; the install still verifies the files.
- Failures name the step that fixes them: no network ("Jerd cannot reach the download
  server…"), a digest mismatch ("…does not match its expected SHA-256. Jerd installed
  nothing."), a full disk (`DiskSpace.outOfSpace`), and a Redis update without a compiler
  (`RedisSourceBuilder.missingCompiler`).
- A release without a digest (MySQL, Laravel) matches its build by kind and version, so it
  shows as installed and is not downloaded again.
- Finder's `.DS_Store` is the only file that verification ignores, on both sides.
  Preparation deletes it before it records the files. A receipt that records one still matches.
- A staging folder is locked (`flock`) while its installation runs. `removeAbandonedStaging()`
  of `RuntimeInstaller`, `BundledRuntimeBootstrap` (all four group folders), and
  `PinnedPayloadPreparer` removes only staging folders that nobody holds. Call them at start.
- A corrupt `cli-tools.json` is never reset. Later tool selections survive the bootstrap.
- Long file work runs on a GCD thread (`BlockingWork`), not on the cooperative pool. It runs
  inside the calling task (an actor on its own serial queue). Thus a cancellation stops a
  running hash, extraction, copy, or scan at its next chunk or entry.

## Bundle layout

`Contents/Resources/RuntimePayloads/runtimes.json` and
`RuntimePayloads/<group>/<payload ID>/payload-receipt.json` with the payload files. A
receipt must match its pin; folders without a pin are ignored. Installed folders are
`<group folder>/<folder ID>/` with the same receipt.

Folders that older builds installed (`<group folder>/<installation ID>/` with
`jerd-receipt.json` or `receipt.json`) stay in use, because old service records name them.
Verify one with `LegacyPayloadVerifier` each time before use. It requires exactly the
recorded files and hashes, and the execute bit of each executable in the database form.

## Test

```sh
swift test --package-path Packages/JerdKit --filter JerdRuntimesTests
JERD_RUNTIME_NETWORK=1 swift test --package-path Packages/JerdKit --filter Live
```

Default tests use saved publisher responses, a fake `URLProtocol`, fake commands, and
temporary folders. Opt-in: `JERD_RUNTIME_INSTALL=mailpit,caddy` installs real releases,
`JERD_MYSQL_ARCHIVE` and `JERD_RUSTFS_BINARY` check real files. `JERD_DISK_IMAGE=1`
attaches and ejects a small real disk image with the production commands. Run it on each
new macOS, because the Postgres.app step depends on `hdiutil attach` and `diskutil eject`.
