import Foundation

/// What to start: an absolute executable, an argument array, a working folder, and an explicit environment.
///
/// No shell is involved and nothing is inherited from Jerd's own environment.
public struct ProcessRequest: Sendable {
    /// An absolute file URL of the executable. It becomes `argv[0]`.
    public var executable: URL
    /// The arguments after `argv[0]`.
    public var arguments: [String]
    /// The working folder. It is also the default `HOME`.
    public var workingDirectory: URL
    /// Variables that replace or add to `SpawnPlan.baseEnvironment`.
    public var environment: [String: String]
    /// Loopback listeners that the child receives as descriptors 3 (HTTP) and 4 (HTTPS).
    public var listeners: InheritedListeners?
    /// Secrets that never reach the log. Output then passes through a redacting pipe.
    public var redactedValues: [String]

    public init(
        executable: URL, arguments: [String] = [], workingDirectory: URL, environment: [String: String] = [:],
        listeners: InheritedListeners? = nil, redactedValues: [String] = []
    ) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.listeners = listeners
        self.redactedValues = redactedValues
    }
}
