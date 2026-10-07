import JerdLive
import JerdUI
import SwiftUI

/// The menu bar icon: the chosen design in full color, or a symbol when the image is missing.
struct MenuBarLabel: View {
    let appearance: AppearanceModel
    let images: AppIconImages

    var body: some View {
        if let image = images.menuBarImage(for: appearance.icon) {
            Image(nsImage: image)
                .renderingMode(.original)
                .accessibilityLabel("Jerd")
        } else {
            Image(systemName: "server.rack")
                .accessibilityLabel("Jerd")
        }
    }
}
