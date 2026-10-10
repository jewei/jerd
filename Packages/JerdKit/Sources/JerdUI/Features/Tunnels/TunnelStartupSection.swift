import JerdDesign
import JerdTunnels
import SwiftUI

/// The startup settings of a tunnel. Edit changes them.
struct TunnelStartupSection: View {
    let tunnel: TunnelRegistration

    var body: some View {
        Section {
            ValueRow("Connect when Jerd opens", value: tunnel.startOnLaunch && tunnel.canConnectOnLaunch ? "On" : "Off")
            ValueRow("Restart after an unexpected exit", value: tunnel.restartOnFailure ? "On" : "Off")
        } header: {
            Text("Startup")
        } footer: {
            FormFooter(
                (tunnel.canConnectOnLaunch ? "" : TunnelRouteCopy.launchNote + " ")
                    + "Closing the window keeps this connector running. Quit stops it. The Mac must stay awake and online to serve traffic."
            )
        }
    }
}
