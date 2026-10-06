import Foundation

/// The data folder and the server log of one service, and whether each exists yet. A page
/// shows the folder only after the first start creates it.
public struct ServiceFiles: Equatable, Sendable {
    public let dataFolder: URL
    public let log: URL
    public let hasDataFolder: Bool
    public let hasLog: Bool

    public init(dataFolder: URL, log: URL, hasDataFolder: Bool, hasLog: Bool) {
        self.dataFolder = dataFolder
        self.log = log
        self.hasDataFolder = hasDataFolder
        self.hasLog = hasLog
    }
}
