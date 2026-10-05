import ArgumentParser

/// Options that every command accepts.
struct GlobalOptions: ParsableArguments {
    @Flag(name: .shortAndLong, help: "Show each underlying command line and its complete output.")
    var verbose = false

    @Flag(help: "Print one JSON summary on standard output. Every other line goes to standard error.")
    var json = false

    func context() throws -> DevContext {
        try DevContext.live(verbose: verbose, json: json)
    }
}

/// A `./dev` command with the global options. `DevMain` reads `options.json` to print the summary.
protocol DevSubcommand: AsyncParsableCommand {
    var options: GlobalOptions { get }
}
