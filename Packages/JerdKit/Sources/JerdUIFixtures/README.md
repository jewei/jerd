# JerdUIFixtures

In-memory implementations of the JerdUI ports, realistic sample data with fixed dates, and
the window scenarios for snapshots. Tests and `jerd-snapshots` use it; the app never links it.

| Type | Purpose |
| --- | --- |
| `AppFixture` | An `AppState` on in-memory ports, with access to every port. |
| `InMemoryShell`, `InMemoryFilePanels`, `InMemoryUpdater` | Window, pasteboard, Finder, Dock, panels, and updater effects, recorded. |
| `InMemoryRuntimeInventory`, `InMemoryAdvancedPorts` | Runtime, recovery, registration, and HTTPS recovery ports. |
| `InMemoryFeature`, `SampleFeatures` | A recording feature for lifecycle tests, and the sample data variants. |
| `InMemoryServicePorts`, `SampleServices` | Database, storage, mail, and command-line tools ports in memory, with a start and stop `ServiceBehavior`. |
| `ServiceScenario`, `SnapshotCatalog.addServicePages()` | Databases, Storage, Mail, and their sheets, as snapshot entries. |
| `SampleData` | Runtimes, releases, findings, backups, registrations; 6 October 2026, 09:41 GMT. |
| `FixtureScenario`, `ScenarioHost` | Named window states and their one-time preparation. |
| `SnapshotCatalog.addJerdPages()` | Registers every scenario as a snapshot entry. |
| `IdleSleeper` | A poller clock that never ticks. |
| `InMemorySitesPort`, `InMemoryTunnelsPort`, `SampleData+Sites` | Sites, the environment, HTTPS approval, and tunnels in memory. |
| `SitesSheetScenario` | Each Sites and tunnel sheet, rendered alone (`sheet-*` snapshots). |

`Resources/AppIcons` holds 144-pixel copies of the shipped icon designs.
See [JerdUI](../JerdUI/README.md) for how to add a scenario.
