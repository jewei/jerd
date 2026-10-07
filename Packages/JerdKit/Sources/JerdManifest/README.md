# JerdManifest

JerdManifest holds the formats and the rules that the app and the `./dev` tool share.
These are runtime pins, payload receipts, build receipts, payload folder IDs, and app
update checks.
It depends only on JerdFoundation. It does no network work.

## Main types

| Type | Purpose |
| --- | --- |
| `RuntimeKind`, `RuntimeVersion`, `CPUArchitecture` | The runtime values. Raw values are saved in files and folder names. |
| `PayloadGroup`, `PayloadIdentifier` | The first-launch groups and the one identifier rule. |
| `RuntimePinCatalog`, `RuntimePin` | The pin catalog `Runtimes/runtimes.json`: one reviewed artifact per pinned kind. |
| `PayloadReceipt`, `PayloadFileRecord`, `PayloadSigning` | The one receipt of a bundled payload: `payload-receipt.json`. |
| `PayloadFolderID` | The one formula for the folder name of an installed bundled payload. |
| `BuildReceipt` | The receipt of a managed build: `runtime-updates/<folder>/update-receipt.json`. |
| `SupportReceipt` | The receipt of a built support library (`support-receipt.json`): the XZ library that the RustFS preparation needs, in `.build/runtimes/support/xz` and in the app. |
| `LegacyPayloadReceipt` | Reads the three receipt forms that older builds wrote into installed folders. |
| `AppUpdateSettings` | Accepts only the official Sparkle feed URL and Ed25519 key. |
| `AppcastVerifier`, `SignedFeed`, `Appcast` | Verify a signed appcast and an update archive with the public key only. |

## Rules

- `embeddedPins` are copied into the app; `onDemandPins` (today MySQL, PostgreSQL, Mailpit, and
  RustFS) are not, so the database group is partly embedded (Redis stays) and the mail and
  storage groups are not. An on-demand pin must name an archive.
  The installed runtime must report a pinned `engineVersion`. `installedSize` (1 byte to 8 GB)
  is the approximate size of the installed runtime, for the free-space check and the install
  dialog. The keys are optional, are omitted when nil, and earlier readers ignore them; the
  installed folder layout does not change.
- A pin names one archive by URL, exact size, and SHA-256. The MySQL pin also names its
  signature file by URL, size limit, and SHA-256; JerdRuntimes enforces all three before the
  OpenPGP check. The Laravel installer pin names the committed `composer.lock` instead.
- A payload receipt lists every file with its SHA-256 and its executable flag, but not
  itself. A native executable must be recorded as executable.
- The folder ID is `<payload ID>-<16 hexadecimal characters>`. The characters start the
  SHA-256 of the sorted lines `<path>\t<sha256>\t<x or ->\n`. A changed file or mode gives
  a new folder, so payloads install side by side and never replace each other.
- `update-receipt.json` keeps its old form exactly: default `JSONEncoder`, schema 1, and
  `secondaryExecutable` omitted when nil. Current folders end with the archive SHA-256;
  legacy folders without it are still read.
- Legacy receipts are read only: `jerd-receipt.json` with `fileSHA256` (development),
  `jerd-receipt.json` with file objects (databases), and `receipt.json` (Mailpit, RustFS).
  `Format(group:)` names the form of each group. `LegacyPayloadVerifier` in JerdRuntimes
  uses all three forms to verify old installed folders before use.
- `support-receipt.json` keeps the form that `./dev runtimes prepare` wrote: pretty, sorted keys,
  a final newline, schema 1, `name`, `version`, `archiveSHA256`, `deploymentTarget`, and `files`
  (plain file names to SHA-256). The release adds the optional `signing` record. The folder must
  hold exactly the recorded files, each a regular file.
- The feed signature covers the bytes before the last `<!-- sparkle-signatures:` block,
  as in Sparkle 2. The block `length` must equal that byte count.
- A build must carry exactly the official feed URL and key. Unexpanded build settings fail.

## Pin catalog

`Runtimes/runtimes.json` has `schemaVersion`, `architecture`, `pins`, and
`supportSources` (the XZ source that `./dev runtimes prepare` builds for RustFS; the app embeds
the built library on its own as `RuntimePayloads/support/xz`). Each pin has `id`, `kind`, `version` (the Postgres.app version for PostgreSQL),
`releasePage`, the optional `embedded` (false: the app installs the pin on demand; absent:
embedded), `engineVersion` (the version that the runtime reports, when it differs from
`version`: `18.6` for PostgreSQL), and `installedSize` (approximate bytes), and one of
`archive {url, size, sha256, assetID?}` or `composerProject {directory, lockSHA256}`, plus
`signature {url, sizeLimit, sha256}` for MySQL. The build copies the catalog into the app
bundle as `RuntimePayloads/runtimes.json`.

## Test

```sh
swift test --package-path Packages/JerdKit --filter JerdManifestTests
```

The golden fixtures are receipts from an installed copy and the committed `appcast.xml`,
which verifies with the official public key. The tests use no network.
