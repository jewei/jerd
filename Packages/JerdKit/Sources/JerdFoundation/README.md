# JerdFoundation

JerdFoundation is the base of all Jerd targets. It has no dependency on other Jerd targets.
It supplies errors, safe private files, locks, saved JSON documents, the data layout,
and small values.

## Main types

| Type | Purpose |
| --- | --- |
| `JerdError` | The error of every operation: a `kind` and a message that a user can act on. |
| `FileProbe` | Tells if a path is absent, present, or unknown. Only `absent` proves absence. |
| `OwnedDirectory` | Creates private folders (mode 0700) and checks folders inside the data root. |
| `AtomicFile` | Writes whole files atomically and reads private files with limits. |
| `InstanceLock` | Takes an exclusive `flock` without waiting. Releases on `release()` or deinit. |
| `JSONDocumentStore` | The one reader and writer of a saved JSON file, with its backup copy. |
| `DataLayout` | Names every path under `~/Library/Application Support/Jerd`. |
| `RecordLocation`, `RecordScan` | Tell where active-run records and their locks are. |
| `HostnamePolicy`, `Hostname` | Validate and suggest `.test` hostnames. |
| `HostsSectionLayout`, `HostsMapping`, `HostsConflictRule` | Parse Jerd's `# BEGIN JERD` hosts section and decide if a hostname is mapped by someone else. The app and the helper use this one rule. |
| `SecretGenerator`, `HexEncoding` | Make random secrets and hexadecimal text. |
| `FileDigest` | Calculates SHA-256 of files in chunks of 1 MiB. |
| `RelativePath` | A safe relative path for archives, receipts, and manifests. |

## Rules

- Do not overwrite corrupt data. A file that cannot be read, decoded, or validated stays
  in place. Load and save then throw `.corrupt`.
- Before a save replaces a valid file, the store copies the old bytes to the previous file.
- Writes go to a temporary file in the same folder. The data is flushed with
  `F_FULLFSYNC` (`.full`) or `fsync` (`.standard`). Then `rename` replaces the target.
- Reads refuse symbolic links, hard links, other owners, FIFOs, and files above the limit.
- `OwnedDirectory` never changes a folder of another user and never follows a final link.
- Lock file names and every path in `DataLayout` are a compatibility contract. Do not
  change them without a migration and a test that reads the old form.
- Settings files use `JSONFileFormat.settings` (pretty, sorted keys, unescaped slashes).
  Markers, credentials, and run records use `JSONFileFormat.compact`.
- A hostname is lowercase, ends in `.test`, has at most 253 bytes, and has labels of
  1 to 63 bytes of `a-z`, `0-9`, or an internal `-`.
- A hosts mapping is Jerd's own only inside a section with exact marker lines and only
  `127.0.0.1 <name>` lines (the helper's rule). A `::1` line, an unpaired marker, or any other
  line makes every mapping of the file count as external. The section format is the one of old
  builds: `\n# BEGIN JERD\n127.0.0.1 <host>\n…# END JERD\n`, LF only, hosts sorted.

## How to use a document store

1. Make one store for each file, with its size limit, format, and user name.
2. Give a `decode` closure for versioned files. Use `SchemaVersion.read` and throw
   `SchemaVersion.unsupported` for an unknown version.
3. Give `validate` for structural rules and `admit` for rules that compare the saved
   document with the new one. Use `admitting(_:)` for a rule of one operation.
4. Use `loadRecord()` and `save(bytes:)` when another file records a hash of the bytes.
5. Call the store from the one actor that owns the file.

## Test

```sh
swift test --package-path Packages/JerdKit --filter JerdFoundationTests
```

The tests use temporary folders only. They do not need root or a network.
