import ArgumentParser
import Foundation

/// `./dev runtimes embed DEST`: the Xcode embed phase calls it to copy the verified payloads.
struct RuntimesEmbedCommand: DevSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "embed",
        abstract:
            "Verify the prepared payloads of the embedded groups and copy them into an app bundle. The Xcode build calls it."
    )

    @Argument(help: ArgumentHelp("The folder <app>/Contents/Resources/RuntimePayloads.", valueName: "destination"))
    var destination: String

    @Flag(help: "Fail when a payload of an embedded group is missing. Release builds use it.")
    var requireAll = false

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let context = try options.context()
        let url = URL(filePath: destination, directoryHint: .isDirectory).standardizedFileURL
        try await StepSequence.runSingle("Embed runtime payloads", console: context.console) {
            try await RuntimesEmbedStep.run(context, destination: url, requiresAll: requireAll)
        }
    }
}
