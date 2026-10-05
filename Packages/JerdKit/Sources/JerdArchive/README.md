# JerdArchive

JerdArchive extracts runtime archives and copies runtime folder trees safely.
It depends on JerdFoundation and on the macOS system libarchive (`CArchive`).

## Main types

| Type | Purpose |
| --- | --- |
| `ArchiveExtractor` | Extracts selected regular files from a tar, gzip tar, or zip archive. |
| `ExtractionPolicy` | Selects files and sets the root rule and the limits of one extraction. |
| `ExtractionReport` | Lists the extracted files and the bytes written. |
| `ContainedTreeCopier` | Copies a folder tree that must stay inside an allowed root. |
| `ArchiveFailure` | Every error that this module throws, with its user message. |
| `ExtractionPlan` | Pure rules for each entry header (package access, for tests). |
| `ArchiveReader` | Reads entry headers and data with libarchive (package access). |

## Extraction rules

- Only the gzip filter and the tar and zip formats are read. A libarchive warning is an error.
- libarchive must be version 3.0.0 or later.
- An entry name must be a safe relative path: no leading `/`, no `\`, no control
  character, and no `..`. Empty and `.` components are removed.
- With `stripsRoot`, all entries must share one top folder. That folder is removed.
- Allowed types: regular file, folder, symbolic link, and hard link. Other types fail.
- Limits: 100,000 entries (all entries), 512,000,000 bytes for each entry (all entries),
  and `outputLimit` for the bytes written (selected files and link copies only).
- An entry without a recorded size can stream up to the smaller of the two size limits.
  An entry with a recorded size must have exactly that size.
- Two selected names that differ only in case or Unicode form fail.
- A file is created with `O_EXCL | O_NOFOLLOW`. Its mode is 0700 when the entry has an
  execute bit, else 0600. Folders get mode 0700.
- A link must stay inside the archive (and inside the root). A selected link becomes a
  regular copy of its final extracted file. No symbolic link is ever created.
- Cancellation is checked for each entry and each 1 MiB chunk.
- A failed extraction leaves partial output. Extract into a staging folder and remove it.

## Tree copy rules

- Each node is resolved through its links. The resolved path must stay under the root.
- A tree has at most 100,000 nodes. A folder link cycle fails.
- A selected file must be a regular file of at most 512,000,000 bytes. The copy gets mode
  0700 when the source has an execute bit, else 0600. Unselected files are skipped.

## Use

Both operations are synchronous. Run them off the cooperative thread pool, for example
in a detached task of the installer actor.

## Test

```sh
swift test --package-path Packages/JerdKit --filter JerdArchiveTests
```

The tests build tar and zip archives in memory and use temporary folders only.
