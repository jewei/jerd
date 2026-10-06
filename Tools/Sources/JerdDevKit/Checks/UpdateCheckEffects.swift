import Foundation

/// The side effects of `./dev check updates` besides commands: time, processes, the loopback server,
/// and the home folder that holds Sparkle's caches. Tests replace each one.
struct UpdateCheckEffects: Sendable {
    var clock: any HarnessClock
    var inspector: any ProcessInspecting
    /// Makes a new server for each case, so that no case can read another case's files.
    var makeServer: @Sendable () -> any LoopbackFileServing
    var home: URL

    static let live = UpdateCheckEffects(
        clock: SystemHarnessClock(), inspector: LiveProcessInspector(), makeServer: { LoopbackFileServer() },
        home: FileManager.default.homeDirectoryForCurrentUser)
}
