# JerdSystem

JerdSystem holds the shared parts of privileged system integration. The app and the helper
both use it. It edits no system file by itself: the helper gives it the hosts file, the record
folder, and the keychain. It depends only on JerdFoundation.

## Main types

| Type | Purpose |
| --- | --- |
| `JerdHelperProtocol`, `JerdTrustConsentProtocol` | The XPC selectors. Do not change a name or a type. |
| `HelperWireProtocol`, `HelperWireError` | Payload limits, JSON coding, and stable error codes in error texts. |
| `SystemSetupStatus`, `SystemRegistrationRequest`, … | The XPC DTOs. Add new fields only as optional fields. |
| `HostsSection`, `HostsMapping`, `ValidatedHostnames` | The tracked `# BEGIN JERD` section of the hosts file. |
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
- A failed step is undone in reverse order. A rollback writes back the exact earlier record bytes.
  When an undo fails, the journal stays and the error is `.partialChange`.
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

It signs a copy of `JerdXPCCheck` as `dev.jerd.app`, transfers two loopback listeners, and makes
sure that XPC refuses a wrong client identity and a wrong server identity.
