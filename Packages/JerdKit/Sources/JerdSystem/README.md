# JerdSystem

JerdSystem holds the shared parts of privileged system integration. The app and the helper
both use it. It edits no system file by itself: the helper gives it the hosts file, the record
folder, and the keychain. It depends only on JerdFoundation.

## Main types

| Type | Purpose |
| --- | --- |
| `JerdHelperProtocol`, `JerdTrustConsentProtocol` | The XPC selectors. Do not change a name or a type. |
| `HelperWireProtocol`, `HelperWireError` | Payload limits, JSON coding, and stable error codes in error texts. |
| `SystemSetupStatus`, `SystemRegistrationRequest`, … | The XPC DTOs. Add new fields only as optional fields. Never make an existing field optional on the wire: `SystemRecoveryStatus` sends placeholders for an unreadable record. |
| `HostsSection`, `ValidatedHostnames` | The tracked `# BEGIN JERD` section of the hosts file. It parses with `HostsSectionLayout` and `HostsMapping` from JerdFoundation, the same rule that the app uses. |
| `GuardedFileSwap`, `FileMetadataSnapshot` | The race-checked replacement of the hosts file. |
| `RegistrationRecord`, `HelperRecordCodec`, `RootRecordDirectory` | The helper records and their exact formats. |
| `SetupStore`, `SetupTransaction`, `SetupPlan` | Configure and remove as journaled steps with rollback. |
| `RecoveryAssessor`, `RecoveryExecutor` | The recovery report and the approved recovery. |
| `CertificateIdentity`, `InstallationCertificate` | The checks of the installation CA. |
| `TrustSettingsPolicy`, `TrustScope`, `CertificateTrust` | The admin trust settings and their strict comparison. |
| `ConsentScope`, `ConsentGate`, `ConsentResponder` | The app side of the reverse trust calls. |
| `CodeSigningPolicy` | The code-signing requirement text and the team check. |
| `LoopbackListenerPair`, `PortLeaseCoordinator` | The listeners on ports 80 and 443 and their lease. |
| `ReplyGate`, `HelperConnection`, `HelperRegistration`, `HelperClient` | The app-side client. |
| `HelperTransportError`, `HelperRecoveryPolicy` | The cause of a transport failure and the one automatic restart of a stale helper. |
| `HelperRegistrationFailure`, `HelperProcessInspecting`, `HelperProcessTable` | The causes of `SMAppService` failures, and the check that the old helper process exited. |

## App-only and root-only code

One target holds three kinds of code. Keep the boundary when you add a file:

| Kind | Folders | Linked by |
| --- | --- | --- |
| Shared wire and policy | `Wire`, `Hosts`, `Certificates`, `Trust`, `Signing`, `Listeners` | App and helper |
| App only | `Client`, `Consent` (`ConsentResponder`, `ConsentGate`, `AdminTrustSettings`) | App; the helper never calls it |
| Root only | `Files`, `Records`, `Setup`, `Recovery`, `Ports` | Helper; the app never calls it |

Root-only code does not import `ServiceManagement` or call `SecTrustSettingsSetTrustSettings`; only
app-only code does. The helper binary links that code, but no helper path reaches it, because
`JerdHelperCore` calls only `SetupStore`, `GuardedFileSwap`, `RootRecordDirectory`,
`PortLeaseCoordinator`, `LoopbackListenerPair`, and the shared types.

The target is not split now, for these reasons. A split moves about 25 source files, about 10 test files,
and their fixtures, and makes `internal` parsers such as `HostsSection` `package` API. An app-client
target also changes the dependency lines of the app targets that import JerdSystem, which this
module does not own. Split it in its own change: move the root-only folders into `JerdHelperCore`
(with their tests), then move `Client` and `Consent` into an app-client target.

## Client API for JerdLive

`HelperClient` is an actor: `status()`, `approve()`, `configure(hostnames:caCertificate:policy:)`,
`acquireListeners()`, `releaseListeners()`, `removeSetup()`, `recover(report:action:)`,
`reconnect()`, `unregister()`, `invalidate()`. Give the listeners to the web layer with
`InheritedListeners(http: pair.http, https: pair.https)`.

## Rules

- Keep every format in `Tests/JerdSystemTests/Fixtures`: XPC selectors and types, DTO keys,
  `registration.json` v1 to v3 (write v3), `pending.json` v1 and the legacy form, and the hosts
  section. Use `JSONEncoder()` with default options for saved records and DTOs.
- Status, acquire, and release time out after 20 seconds. Configure, remove, and recover have no
  app timeout, because macOS can show an approval prompt. Cancellation ends only a status call.
  A timeout drops the shared link, but not while a change without a timeout waits on it.
- Each changing call opens its own consent scope with a token. A second scope is refused.
- A status or acquire call that fails with a code-signing requirement failure (`NSCocoaErrorDomain`
  4102: the helper still runs the code from before an app update) restarts the helper once per
  app run through `reregister()`, then retries once. It changes no hosts or trust. It never
  restarts while the app holds the listeners. A lost connection (4097, 4099) is retried once on a
  new connection. A changing call is never retried, because the helper can have run it.
- `reregister()` waits until the daemon is not enabled and no helper process runs (at most
  5 seconds), then registers. It retries "Operation not permitted" up to 4 times. Every failure is
  a `JerdError` that names what to do; some carry a remedy (Reconnect Helper…, Login Items).
- When another tool deleted the tracked hosts section, remove still removes the trust and the
  registration, with no change to the hosts bytes. Configure writes the section again after
  the external-mapping check.
- A failed step is undone in reverse order. A rollback writes back the exact earlier record bytes.
  When an undo fails, the journal stays and the error is `.partialChange`.
- When only the journal deletion fails after every step, nothing is undone. The journal stays with
  the phase "Applied; the recovery record could not be removed." and recovery finishes it.
- The hosts lock waits at most 5 seconds. A staging file stays only with a `.partialChange` error.
- A recovery keeps the first `recovery.previous.json` of a transaction.
- Status reports a running transaction as `operationInProgress`, never as interrupted. A corrupt
  `pending.json` gives a recovery report with a specific message and no allowed action.

## Test

```sh
swift test --package-path Packages/JerdKit --filter JerdSystemTests
```

The tests use temporary folders, fake trust, fake helpers, and in-process XPC. They do not touch
`/etc/hosts`, a keychain, trust settings, or `SMAppService`. The certificate fixtures come from
`Fixtures/Certificates/make-certificates.sh`.

The signed XPC check (the old `check-xpc`) is opt-in. It needs an Apple code-signing identity:

```sh
JERD_XPC_IDENTITY="Apple Development: Name (TEAMID)" \
  swift test --package-path Packages/JerdKit --filter SignedXPCCheckTests
```

It signs a copy of `JerdXPCCheck` as `dev.jerd.app` and transfers two loopback listeners. It
makes sure that XPC refuses a wrong client identity and a wrong server identity.
