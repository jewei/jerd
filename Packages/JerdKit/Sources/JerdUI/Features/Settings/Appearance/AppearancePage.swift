import JerdDesign
import SwiftUI

/// Dashboard › Appearance: the menu bar and Dock switches and the icon picker.
struct AppearancePage: View {
    @Bindable var model: AppearanceModel

    var body: some View {
        FormPage {
            PageHeader("Appearance", subtitle: "Choose where Jerd appears and which icon it uses.")
        } messages: {
            if model.isHiddenEverywhere {
                InlineMessage(
                    "Jerd has no menu bar icon and no Dock icon. To return to this window, open Jerd from Applications.",
                    kind: .warning, style: .banner, identifier: "appearance.hidden")
            }
        } content: {
            Section {
                Toggle(isOn: $model.showMenuBar) {
                    VisibilityLabel(
                        "Menu bar", detail: "Keep Jerd within reach at the top of your screen.",
                        systemImage: "menubar.rectangle")
                }
                .accessibilityIdentifier("appearance.menu-bar")
                Toggle(isOn: $model.showDock) {
                    VisibilityLabel("Dock", detail: "Show the app icon in your Dock.", systemImage: "dock.rectangle")
                }
                .accessibilityIdentifier("appearance.dock")
            } header: {
                Text("App Visibility")
            } footer: {
                if let footer = Self.visibilityFooter(isHiddenEverywhere: model.isHiddenEverywhere) {
                    FormFooter(footer)
                }
            }
            .toggleStyle(CenteredSwitchStyle())
            Section {
                IconPicker(model: model)
            } header: {
                Text("App Icon")
            } footer: {
                FormFooter("The selected icon appears in the Dock and menu bar while Jerd is open.")
            }
        }
    }

    /// The note under the switches. While both are off, the warning banner already says how to
    /// return, so the note does not say it twice.
    static func visibilityFooter(isHiddenEverywhere: Bool) -> String? {
        isHiddenEverywhere ? nil : "When both are off, open Jerd from Applications to return to its window."
    }
}
