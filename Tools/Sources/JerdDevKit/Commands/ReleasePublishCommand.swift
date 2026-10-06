import ArgumentParser

/// `./dev release publish`: starts the publication of a prepared candidate.
struct ReleasePublishCommand: DevSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "publish",
        abstract: "Publish a prepared candidate: release, assets, and a pull request with the feed.",
        discussion: """
            Validates the candidate, requires its source commit on origin/main, creates a draft release, \
            checks the uploaded assets, publishes the release, and opens a pull request with the signed \
            feed. After the merge, ./dev release resume waits until the public feed URL serves the feed.
            """)

    @Argument(help: ArgumentHelp("The candidate folder in .build/releases.", valueName: "directory"))
    var directory: String

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        try await Self.publish(directory, options: options, resuming: false)
    }

    static func publish(_ directory: String, options: GlobalOptions, resuming: Bool) async throws {
        let environment = ReleaseEnvironment.live(try options.context())
        let layout = try CandidateStore.existing(directory, workingDirectory: ReleaseValidateCommand.workingDirectory)
        try await StepSequence.runSingle("Release publication", console: environment.console) {
            let outcome = try await ReleasePublisher(environment: environment, layout: layout).run(resuming: resuming)
            report(outcome, layout: layout, console: environment.console)
            if outcome == .feedNotYetPublic {
                throw DevFailure.checkFailed("The public feed does not serve the release yet. Resume later.")
            }
        }
    }

    static func report(_ outcome: ReleasePublisher.Outcome, layout: CandidateLayout, console: Console) {
        switch outcome {
        case .published:
            console.success("The update is public. Run git pull --ff-only to update the local checkout.")
        case .waitingForMerge(let number):
            console.success("Merge pull request #\(number), then run ./dev release resume \(layout.root.path).")
        case .feedNotYetPublic:
            console.warning("The feed is merged, but the public URL does not serve it yet.")
        }
    }
}
