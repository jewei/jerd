# Implementation status

Status date: 2026-10-02. The [verification record](Verification.md) states the
checks that passed and the remaining test gaps.

## Completed features

| Area | Current behavior |
| --- | --- |
| Sites | Concurrent `.test` sites with per-site PHP selection, HTTPS, and protected static routes |
| System integration | Signed helper, explicit host/trust approval, loopback sockets, rollback, and removal |
| CLI tools | PHP, Composer, and Laravel select PHP from the current project's registration |
| Databases | Independent MySQL, PostgreSQL, and Redis services with retained data and graceful shutdown |
| Mail | Local Mailpit capture, persistent inbox, service controls, and Laravel settings |
| Storage | Native RustFS, verified bucket creation on Save, private access, and optional public object reads |
| Dashboard | Service status and two-pane navigation for Dashboard, Appearance, Runtimes, Advanced, and About |
| Appearance | Independent Dock/menu bar switches and the original icon plus six designs |
| Runtime updates | Stable version checks, verified downloads, installation, and activation controls |
| Data runtime changes | Mail/storage backups, candidate checks, and recovery after failed or interrupted changes |
| App updates | Sparkle, signed HTTPS feed, signed archives, explicit installation, and graceful app shutdown |

## Remaining release work

The initial public feed contains no update archive. Notarization and the first
published app release remain incomplete. Bundled executables need release signing
and updated digest receipts before notarization. [Publish an app update](PublishUpdate.md)
describes the release procedure.

Runtime distribution still needs reproducible builds, Jerd-signed manifests,
a tested architecture and minimum-OS matrix, and smaller release packages.
The development database files occupy about 1.1 GB before release packaging.
The available version catalog does not establish compatibility for every project.

Automatic recovery of orphan processes and interrupted helper transactions
remains incomplete. Full uninstall, automatic log rotation, editable per-runtime
settings, and restart of only affected web processes remain future work.

Database follow-up includes a wider tested version range, export/import controls,
and restoration of removed registrations. Existing database directories retain
their original runtime identity. Mail supports one inbox.

Code, architecture, and performance require independent review after feature work.
