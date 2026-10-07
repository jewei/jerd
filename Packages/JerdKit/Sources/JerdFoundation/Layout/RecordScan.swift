import Foundation

/// How process recovery finds the saved run records of one service family below a folder.
public struct RecordScan: Sendable {
    /// Makes the location of one found instance from its ID and its actual folder or file URL.
    public typealias Locate = @Sendable (_ instance: UUID, _ found: URL) -> RecordLocation

    /// How the records are arranged in `directory`.
    public enum Arrangement: Sendable {
        /// One fixed record, for example `mail/active-run.json`.
        case single(RecordLocation)
        /// One `<UUID>/` folder per instance, for example `databases/instances/<UUID>/active-run.json`.
        case folderPerInstance(Locate)
        /// One `<UUID>.<extension>` file per instance, for example `environment/processes/<UUID>.json`.
        case filePerInstance(fileExtension: String, Locate)
    }

    public let family: RecordFamily
    /// The folder to inspect. It must be an owned directory inside the data root.
    public let directory: URL
    public let arrangement: Arrangement

    public init(family: RecordFamily, directory: URL, arrangement: Arrangement) {
        self.family = family
        self.directory = directory
        self.arrangement = arrangement
    }
}
