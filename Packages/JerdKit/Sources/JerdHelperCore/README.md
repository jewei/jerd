# JerdHelperCore

JerdHelperCore is the logic of the privileged helper daemon `dev.jerd.helper`. The helper runs
as root through `SMAppService`. `Apps/JerdHelper/main.swift` calls only `HelperDaemon.run()`.

## Main types

| Type | Purpose |
| --- | --- |
| `HelperDaemon`, `HelperLaunchPlan` | Start: team check, `--check-signing`, root check, the Mach service listener. |
| `HelperListenerDelegate`, `ConnectionAcceptPolicy` | Accept a connection: UID rule, code signature, session. |
| `HelperSession` | The exported object of one connection, with ordered changes and ordered listener calls. |
| `HelperService` | The one service: the setup store, the port lease, and the port reservation. |
| `ConsentRequester` | The reverse trust call to the app, without a timeout. |
| `TrustInstaller` | Adds and removes the CA, and asks the app for each trust change. |
| `SystemKeychainCertificates`, `AdminTrustInspector` | The system keychain and the admin trust settings. |

## Rules

- The helper never starts a process. It accepts no path, command, executable, or network target
  over XPC. It edits only `/private/etc/hosts` and `/Library/Application Support/JerdHelper`.
- A peer must have UID 501 or higher and the app's code signature from the helper's own team.
  The requirement is set on the listener and again on each connection. A refusal is logged.
- One setup change or listener acquisition runs at a time. A change refuses to run while a
  connection holds the listeners. Configure and restore reserve ports 80 and 443 first.
- Listeners go only to a ready setup: hosts and trust configured with the server TLS policy, and
  no interrupted or running transaction. A connection that closes gets no lease.
- Changing requests of one session run in arrival order. Listener calls keep their own order and
  never wait behind a change: during a change they are refused at once ("System setup is in
  progress"), because the app gives them only 20 seconds. A request that arrives after the close is
  refused.
- `TrustInstaller` deletes a keychain item that it added when a later step fails. It never deletes
  an item that existed before.
- Errors cross XPC as text with a stable code (`HelperWireError`).

## Test

```sh
swift test --package-path Packages/JerdKit --filter JerdHelperCoreTests
```

The tests use a temporary hosts file and record folder, a fake keychain, fake consent, and
ephemeral loopback ports. In-process XPC tests use the real listener delegate with the test
runner's own code-signing requirement. No test needs root or changes the system.
