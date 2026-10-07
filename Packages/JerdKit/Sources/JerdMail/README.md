# JerdMail

JerdMail manages the one local Mailpit inbox. Applications send mail to its loopback SMTP
port, and the user reads the mail on its loopback web page. It uses JerdServiceKit for the
lifecycle.

## Main types

| Type | Purpose |
| --- | --- |
| `MailManager` | The public API: load, register a runtime, edit ports, start, stop, test email, runtime update. |
| `MailService` | The Mailpit parts of the shared `SingleServiceCoordinator`: settings, definition, ports, update items. |
| `MailpitDefinition` | The version probe, the inbox preparation, and the exact Mailpit command line. |
| `MailInbox` | The inbox identity (`runtime.json`), the start marker (`initialized.json`), and the database. |
| `MailReadinessProbe` | The information API must name the version and the database; SMTP `NOOP` must give `250 `. |
| `MailServerProbing`, `MailServerProbe` | The port and the live answers: an in-process HTTP request and one `curl` SMTP check. |
| `TestMessage`, `TestMessageSender` | The test email and its send through the local SMTP service. |
| `MailSettings`, `MailPorts`, `MailRuntime` | The content of `settings.json` and the Laravel settings. |
| `MailSettingsStore` | The only reader and writer of `settings.json`. |

## Files

All paths come from `MailLayout` in JerdFoundation. Folders have mode 0700 and files 0600.

- `mail/settings.json` and `settings.previous.json` (settings format, at most 64 KiB).
- `mail/service.lock`, `active-run.json`, `server.log`, `server.previous.log`.
- `mail/inbox/messages.sqlite`, `inbox/runtime.json`, and `inbox/initialized.json` (compact).
- `mail/runtime-update.json` and `mail/runtime-backups/<UUID>/` during and after an update.
- `mail/test-<UUID>.eml`: the test email. It is removed after the send.

## Rules

- A corrupt or unsupported `settings.json` is never replaced. Its runtime changes only in an update.
- Both ports are from 1024 to 65535, differ, and are free on every address before a start.
- Mailpit listens only on `127.0.0.1`, has no UDP socket, and gets a clean environment.
- An inbox is never opened with another runtime. Untracked files are never adopted.
- After a successful start, a missing database is refused, never replaced with an empty one.
- Edit checks the run record with the inbox lock held.
- Exit detection never blocks Stop. Stop and Quit keep every message.
- A runtime update checks the inbox first without a write. It keeps the lock for the whole
  transaction, and keeps its backup until the user deletes it in Advanced.

## Test

```sh
swift test --package-path Packages/JerdKit --filter JerdMailTests
```

The default tests use fake processes, a fake `lsof`, and scripted Mailpit answers. They also
use golden files from older builds and a small HTTP server on a loopback port. The opt-in test starts a real Mailpit:

```sh
JERD_MAIL_INTEGRATION=1 JERD_MAIL_RUNTIME=<folder with mailpit 1.31.3> \
  swift test --package-path Packages/JerdKit --filter MailIntegrationTests
```
