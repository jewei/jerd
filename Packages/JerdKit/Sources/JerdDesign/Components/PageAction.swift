import SwiftUI

/// One button in a page header or banner. A header takes at most one primary action, which is
/// always the next step (for example Start when stopped, Open when running).
public struct PageAction {
    public let title: String
    public let systemImage: String?
    public let role: ButtonRole?
    public let isEnabled: Bool
    public let help: String?
    public let accessibilityLabel: String?
    /// The stable identifier for UI tests, for example `site.stop`. Titles can change; this must not.
    public let identifier: String?
    public let perform: @MainActor () -> Void

    public init(
        _ title: String, systemImage: String? = nil, role: ButtonRole? = nil, isEnabled: Bool = true,
        help: String? = nil, accessibilityLabel: String? = nil, identifier: String? = nil,
        perform: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.isEnabled = isEnabled
        self.help = help
        self.accessibilityLabel = accessibilityLabel
        self.identifier = identifier
        self.perform = perform
    }
}
