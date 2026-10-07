import Foundation

/// The exact commands of `./dev check updates`, as pure values.
struct UpdateFixturePlan: Sendable {
    let repository: Repository
    let toolchain: Toolchain

    /// The fixture source, compiled at run time. It is not part of the Tools package.
    var fixtureSource: URL { repository.path("Tools/Fixtures/AppUpdateTest.swift") }
    /// The slice of the resolved Sparkle package that holds `Sparkle.framework`.
    var frameworkFolder: URL { repository.sparkleArtifacts.appending(path: "Sparkle.xcframework/macos-arm64_x86_64") }
    var framework: URL { frameworkFolder.appending(path: "Sparkle.framework") }
    var signUpdate: URL { repository.sparkleTools.appending(path: "sign_update") }

    func compile(to binary: URL) -> Invocation {
        Invocation(
            executable: toolchain.xcrun,
            arguments: [
                "swiftc", "-swift-version", "6", "-F", frameworkFolder.path, "-framework", "Sparkle",
                "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks", fixtureSource.path,
                "-o", binary.path,
            ],
            workingDirectory: repository.root, timeout: TimeLimit.build)
    }

    /// Writes a new private test key (mode 0600) and prints its public key.
    func generateKey(binary: URL, key: URL, inherited: [String: String]) -> Invocation {
        var environment = inherited
        environment["DYLD_FRAMEWORK_PATH"] = frameworkFolder.path
        return Invocation(
            executable: binary, arguments: ["generate-test-key", key.path], environment: environment,
            timeout: TimeLimit.probe)
    }

    func copyFramework(into app: URL) -> Invocation {
        Invocation(
            executable: SystemProgram.ditto,
            arguments: [framework.path, app.appending(path: "Contents/Frameworks/Sparkle.framework").path],
            timeout: TimeLimit.appCopy)
    }

    /// Signs the test app itself. Sparkle inside it is signed before, as in a release, so no `--deep`.
    func sign(_ app: URL, identity: String) -> Invocation {
        Invocation(
            executable: SystemProgram.codesign,
            arguments: ["--force", "--options", "runtime", "--sign", identity, app.path],
            timeout: TimeLimit.codeSigning)
    }

    func zip(_ app: URL, to archive: URL) -> Invocation {
        Invocation(
            executable: SystemProgram.ditto,
            arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", app.path, archive.path],
            timeout: TimeLimit.appCopy)
    }

    /// Prints only the EdDSA signature of the archive.
    func signArchive(_ archive: URL, key: URL) -> Invocation {
        Invocation(
            executable: signUpdate, arguments: ["--ed-key-file", key.path, "-p", archive.path],
            timeout: TimeLimit.codeSigning)
    }

    /// Appends the signature block to the feed file.
    func signFeed(_ feed: URL, key: URL) -> Invocation {
        Invocation(
            executable: signUpdate, arguments: ["--ed-key-file", key.path, feed.path], timeout: TimeLimit.codeSigning)
    }

    /// Starts the installed version 1. It ends after Sparkle quits it or after its final event.
    func launch(_ app: URL) -> Invocation {
        Invocation(
            executable: app.appending(path: "Contents/MacOS/\(UpdateTestBundle.executableName)"), arguments: [],
            timeout: TimeLimit.harnessCase)
    }

    /// Removes the preferences that Sparkle wrote for the temporary bundle identifier.
    func deleteDefaults(bundleIdentifier: String) -> Invocation {
        Invocation(
            executable: SystemProgram.defaults, arguments: ["delete", bundleIdentifier], timeout: TimeLimit.probe)
    }
}
