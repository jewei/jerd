# JerdStorage

JerdStorage manages the one local RustFS service and its S3 buckets. Applications use its
loopback S3 API, and the user opens its loopback console. It uses JerdServiceKit for the lifecycle.

## Main types

| Type | Purpose |
| --- | --- |
| `StorageManager` | The public API: load, register a runtime, edit ports, start, stop, buckets, credentials, runtime update. |
| `StorageService` | The RustFS parts of the shared `SingleServiceCoordinator`: settings, definition, ports, update items. |
| `RustFSDefinition` | The version probe, the data preparation, and the exact RustFS command line. |
| `StorageData` | Identity, credentials, raw key files, and the hashes in `initialized.json`. |
| `StorageReadinessProbe` | A signed `ListBuckets`, then the console page; both in process. |
| `S3Signer` | Pure SigV4. The tests use the published AWS examples. |
| `S3Transport` (`S3Sending`) | One ephemeral session per launch: no proxy, cookie, cache, or redirect; bodies up to 4 MiB. |
| `S3Client`, `S3XMLParsers` | Bucket requests, and the bucket list without external entities. |
| `BucketPolicy`, `BucketProvisioner`, `BucketIntent` | Access rules and the steps from intent to a verified bucket. |
| `StorageSettings`, `StorageBucket`, `BucketName`, `BucketStatus` | `settings.json`, name rules, and row status. |
| `StorageLaunch`, `S3Session` | The S3 session and the bucket names of the current launch: the only per-launch state. |

## Files

All paths come from `StorageLayout` in JerdFoundation. Folders have mode 0700 and files 0600.

- `storage/settings.json` and `settings.previous.json` (settings format, at most 1 MiB).
- `storage/runtime.json`, `initialized.json`, and `credentials.json` (compact).
- `storage/access-key` and `secret-key`: raw key text without a newline, written on each start.
- `storage/data/`: the RustFS volume. `data/.rustfs.sys/format.json` is hashed.
- `storage/runtime-update.json` and `runtime-backups/<UUID>/` during and after an update.

## Rules

- `credentials.json` is written once and never encoded again. Its SHA-256 is in `initialized.json`.
- Data is never opened with another runtime, changed format, or changed credentials.
- RustFS listens only on `127.0.0.1`, gets keys only through files, and runs `data` from `storage/`.
- New buckets are private. A public bucket allows only anonymous `s3:GetObject`.
- Policies are compared by meaning. Any other policy is reported as custom and kept.
- A bucket is saved as an intent first and is complete only after it is verified. An unfinished
  intent can change its public read. A missing complete bucket is reported, never created again.
- Server bucket names that break the name rules are left out, so they cannot stop a start.
- Each launch has its own S3 session. `LaunchPlan.didStop` ends it after every kind of stop (Stop,
  an exit, a reap outside Jerd, a failed start): the session is invalidated and the names are cleared.
- A runtime update checks the data without a write, clones the data off the actor, and keeps
  its backup until the user deletes it in Advanced.

## Test

```sh
swift test --package-path Packages/JerdKit --filter JerdStorageTests
```

The default tests use fake processes, a fake `lsof`, an in-memory S3 service, golden files, and a
small HTTP server on a loopback port. The opt-in test starts a real RustFS:

```sh
JERD_STORAGE_INTEGRATION=1 JERD_STORAGE_RUNTIME=<folder with rustfs 1.0.0> \
  swift test --package-path Packages/JerdKit --filter StorageIntegrationTests
```
