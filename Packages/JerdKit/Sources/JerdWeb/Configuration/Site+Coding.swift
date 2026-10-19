import Foundation

extension Site {
    private enum CodingKeys: String, CodingKey {
        case id, displayName, projectPath, documentRoot, hostname, aliases, phpSelection, isEnabled
    }

    /// A site without `aliases` has none, as in earlier builds, and every key that earlier builds
    /// required stays required.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        displayName = try values.decode(String.self, forKey: .displayName)
        projectPath = try values.decode(String.self, forKey: .projectPath)
        documentRoot = try values.decode(String.self, forKey: .documentRoot)
        hostname = try values.decode(String.self, forKey: .hostname)
        aliases = try values.decodeIfPresent([String].self, forKey: .aliases) ?? []
        phpSelection = try values.decode(PHPSelection.self, forKey: .phpSelection)
        isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
    }

    /// Omitting empty aliases preserves the exact format of earlier sites, so an earlier build
    /// reads the file unchanged.
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(displayName, forKey: .displayName)
        try values.encode(projectPath, forKey: .projectPath)
        try values.encode(documentRoot, forKey: .documentRoot)
        try values.encode(hostname, forKey: .hostname)
        if !aliases.isEmpty { try values.encode(aliases, forKey: .aliases) }
        try values.encode(phpSelection, forKey: .phpSelection)
        try values.encode(isEnabled, forKey: .isEnabled)
    }
}
