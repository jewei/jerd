import ArgumentParser

/// Options that every command accepts.
struct GlobalOptions: ParsableArguments {
    @Flag(name: .shortAndLong, help: "Show each underlying command line and its complete output.")
    var verbose = false

    func context() throws -> DevContext {
        try DevContext.live(verbose: verbose)
    }
}
