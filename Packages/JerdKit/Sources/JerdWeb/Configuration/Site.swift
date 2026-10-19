import Foundation

/// One registered project: its folder, document root, `.test` hostname and aliases, PHP selection,
/// and start flag.
///
/// The property names are the saved JSON keys. A saved site is validated: the paths are canonical
/// and absolute, the document root is inside the project, and the hostnames are lowercase.
public struct Site: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var displayName: String
    public var projectPath: String
    public var documentRoot: String
    /// The main name: Open in Browser, the CLI, and tunnel routes use it.
    public var hostname: String
    /// More `.test` names that serve the same document root, for example for tenants. Sorted.
    public var aliases: [String]
    public var phpSelection: PHPSelection
    /// "Include when starting all sites". Start and Stop of one site do not change it.
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(), displayName: String, projectPath: String, documentRoot: String, hostname: String,
        phpSelection: PHPSelection = .followDefault, isEnabled: Bool = true, aliases: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.projectPath = projectPath
        self.documentRoot = documentRoot
        self.hostname = hostname
        self.aliases = aliases
        self.phpSelection = phpSelection
        self.isEnabled = isEnabled
    }

    /// Every name that the site serves: the main hostname first, then the aliases.
    public var servedHostnames: [String] { [hostname] + aliases }
}
