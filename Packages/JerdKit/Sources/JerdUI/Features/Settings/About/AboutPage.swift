import JerdDesign
import SwiftUI

/// Dashboard › About: the app, its updates, versions, credits, and the disclaimer.
struct AboutPage: View {
    let updates: AppUpdatesModel
    let appearance: AppearanceModel
    let info: AppInfo
    let showRuntimes: @MainActor () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @Environment(\.calendar) private var calendar

    var body: some View {
        FormPage {
            AboutHeader(info: info, icon: appearance.image(for: appearance.icon))
        } content: {
            updatesSection
            Section("Versions") {
                ValueRow("Jerd", value: "\(info.version) (\(info.build))")
                ValueRow("macOS", value: info.macOSVersion)
                ValueRow("App architecture", value: info.architecture)
            }
            CreditsSection()
            Section {
                Text(
                    "Use Jerd only for local development. Jerd does not isolate project code from your user account. Use trusted projects and keep backups of important data. Jerd is an independent project. It has no affiliation with Laravel or the projects above."
                )
                .textRole(.detail)
                .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Disclaimer")
            } footer: {
                FormFooter(info.copyright)
            }
        }
    }

    private var updatesSection: some View {
        Section {
            ActionRow("Jerd updates", detail: updates.message) {
                Button(AppUpdatesModel.checkTitle, systemImage: "arrow.clockwise") { updates.checkForUpdates() }
                    .disabled(!updates.canCheckForUpdates)
                    .accessibilityLabel("Check for app updates")
                    .accessibilityIdentifier("about.check-for-updates")
            }
            if let error = updates.errorMessage {
                InlineMessage(error, kind: .error, identifier: "about.update-error")
            }
            Toggle("Automatically check for app updates", isOn: automaticChecks)
                .toggleStyle(.switch)
                .disabled(!updates.canChangePreferences)
            if let lastCheck = updates.lastCheck {
                ValueRow("Last check", value: formatted(lastCheck))
            }
            ActionRow("PHP and other runtimes") {
                Button("Manage Runtimes", action: showRuntimes)
                    .accessibilityIdentifier("about.manage-runtimes")
            }
        } header: {
            Text("Updates")
        } footer: {
            FormFooter("Installation requires your approval. An app update restarts Jerd and stops its local services.")
        }
    }

    private var automaticChecks: Binding<Bool> {
        Binding {
            updates.automaticallyChecks
        } set: { isOn in
            updates.setAutomaticChecks(isOn)
        }
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(
                date: .abbreviated, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone))
    }
}
