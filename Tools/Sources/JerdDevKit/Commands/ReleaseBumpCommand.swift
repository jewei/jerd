import ArgumentParser

/// `./dev release bump`: sets the next version and promotes the changelog for a pull request.
struct ReleaseBumpCommand: DevSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "bump",
        abstract: "Set the next version and move the unreleased notes under it. It does not commit.",
        discussion: """
            Changes Configuration/Version.xcconfig and CHANGELOG.md. The build must exceed the current build, \
            and both must exceed every release in appcast.xml. Commit the change in a pull request and \
            prepare the release from the merged commit.
            """)

    @Option(help: ArgumentHelp("The marketing version, for example 0.2.0.", valueName: "version"))
    var version: String

    @Option(help: ArgumentHelp("The build number, a positive integer.", valueName: "build"))
    var build: String

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        guard let releaseVersion = ReleaseVersion.release(version), let number = ReleaseVersion.build(build) else {
            throw DevFailure.usage("Use a numeric --version with two to four parts and a positive integer --build.")
        }
        let environment = try ReleaseEnvironment.live(try options.context())
        try await StepSequence.runSingle("Release version bump", console: environment.console) {
            try VersionBump(environment: environment).run(version: releaseVersion, build: number)
        }
    }
}
