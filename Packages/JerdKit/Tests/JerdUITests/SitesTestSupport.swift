import Foundation
import JerdUIFixtures

@testable import JerdUI

/// A Sites model on in-memory ports, with the ports and the recorded shell effects.
@MainActor
struct SitesHarness {
    let sites: InMemorySitesPort
    let tunnels: InMemoryTunnelsPort
    let shell = InMemoryShell()
    let panels: InMemoryFilePanels
    let clipboard: Clipboard
    let model: SitesModel
    /// Every destination that the model showed, and every alert, in order.
    let recorder = ShellRecorder()

    init(
        sites: InMemorySitesPort = InMemorySitesPort(), tunnels: InMemoryTunnelsPort = InMemoryTunnelsPort(),
        panels: InMemoryFilePanels = InMemoryFilePanels()
    ) {
        self.sites = sites
        self.tunnels = tunnels
        self.panels = panels
        clipboard = Clipboard(pasteboard: shell)
        let tunnelsModel = TunnelsModel(port: tunnels, panels: panels, workspace: shell, clipboard: clipboard)
        model = SitesModel(port: sites, tunnels: tunnelsModel, panels: panels, workspace: shell, clipboard: clipboard)
        let recorder = recorder
        let shellValue = SitesShell(
            show: { recorder.shown.append($0) }, open: { recorder.opened.append($0) },
            alert: { recorder.alerts.append($0) })
        model.shell = shellValue
        model.tunnels.shell = shellValue
    }

    /// A harness whose model has launched.
    static func launched(
        sites: InMemorySitesPort = InMemorySitesPort(), tunnels: InMemoryTunnelsPort = InMemoryTunnelsPort(),
        panels: InMemoryFilePanels = InMemoryFilePanels()
    ) async -> SitesHarness {
        let harness = SitesHarness(sites: sites, tunnels: tunnels, panels: panels)
        await harness.model.launch()
        return harness
    }
}

/// Records the shell calls of the Sites models.
@MainActor
final class ShellRecorder {
    var shown: [Destination] = []
    var opened: [Destination] = []
    var alerts: [AppAlert] = []
}
