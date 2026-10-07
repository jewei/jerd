import Foundation

/// One registered project: its folder, document root, `.test` hostname, PHP selection, and start flag.
///
/// The property names are the saved JSON keys. A saved site is validated: the paths are canonical
/// and absolute, the document root is inside the project, and the hostname is lowercase.
public struct Site: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var displayName: String
    public var projectPath: String
    public var documentRoot: String
    public var hostname: String
    public var phpSelection: PHPSelection
    /// "Include when starting all sites". Start and Stop of one site do not change it.
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(), displayName: String, projectPath: String, documentRoot: String, hostname: String,
        phpSelection: PHPSelection = .followDefault, isEnabled: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.projectPath = projectPath
        self.documentRoot = documentRoot
        self.hostname = hostname
        self.phpSelection = phpSelection
        self.isEnabled = isEnabled
    }
}
