import JerdDesign
import JerdManifest
import SwiftUI

/// The section of one runtime kind: installed versions, the check result, the installation
/// progress, and the result of the last installation.
struct RuntimeSection: View {
    let model: RuntimesModel
    let kind: RuntimeKind
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @Environment(\.calendar) private var calendar

    var body: some View {
        Section {
            if kind == .php, !model.registeredPHP.isEmpty {
                PHPDefaultRows(model: model)
            } else {
                ValueRow("Version", value: versionsText)
            }
            if let release = model.inventory.installableRelease(kind) {
                ActionRow("Available", detail: RuntimeCopy.onDemandDetail(release)) {
                    Button("Install…") { model.requestOnDemandInstall(release) }
                        .disabled(!model.canChangeRuntimes)
                        .accessibilityLabel("Install \(release.title)")
                        .accessibilityIdentifier(AccessibilityIdentifier.make("runtimes", kind.rawValue, "install"))
                }
            }
            if let check = model.checks[kind] {
                if let error = check.error {
                    InlineMessage(error, kind: .error)
                }
                if model.selectedRelease(kind) != nil {
                    RuntimeReleaseRows(model: model, kind: kind)
                }
            }
            if let installation = model.installation, installation.kind == kind {
                RuntimeProgressRow(model: model, installation: installation)
            }
            if let message = model.messages[kind] {
                InlineMessage(message, kind: message == RuntimeCopy.cancelledMessage ? .info : .success)
            }
            if let error = model.errors[kind] {
                InlineMessage(error, kind: .error)
            }
        } header: {
            Text(kind.title)
        } footer: {
            if let footer = RuntimeCopy.footer(kind, checkedAt: checkedText) {
                FormFooter(footer)
            }
        }
    }

    private var versionsText: String {
        let versions = model.inventory.installedVersions(kind)
        return versions.isEmpty ? "Not installed" : versions.joined(separator: ", ")
    }

    private var checkedText: String? {
        model.checks[kind].map { check in
            check.checkedAt.formatted(
                Date.FormatStyle(
                    date: .abbreviated, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone))
        }
    }
}
