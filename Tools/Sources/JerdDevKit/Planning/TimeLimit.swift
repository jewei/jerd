/// The time limit of each kind of command. Each limit is far above a normal run on a CI Mac, so a
/// limit stops only a command that hangs.
enum TimeLimit {
    static let probe: Duration = .seconds(60)
    static let git: Duration = .seconds(120)
    static let generate: Duration = .seconds(300)
    static let format: Duration = .seconds(600)
    static let test: Duration = .seconds(30 * 60)
    static let build: Duration = .seconds(40 * 60)
    static let snapshots: Duration = .seconds(20 * 60)
}
