import Foundation

extension UpdateCaseRun {
    /// Writes and signs version 1 and version 2, the signed archive, and the signed feed, and then
    /// applies the change that the case tests.
    func prepare(_ testCase: UpdateCase, in folder: Folder, base: URL, bundleIdentifier: String) async throws {
        let settings = try UpdateTestBundle.sparkleSettings(fromJerdInfoPlist: fixture.jerdInfoPlist)
        for (version, app) in [("1", folder.installedApp), ("2", folder.newApp)] {
            let bundle = UpdateTestBundle(
                bundleIdentifier: bundleIdentifier, version: version, feedURL: base.appending(path: "appcast.xml"),
                publicKey: fixture.publicKey, resultFile: folder.events, refusesFirstQuit: testCase.refusesFirstQuit)
            let written = try bundle.write(
                in: app.deletingLastPathComponent(), executable: fixture.binary, sparkleSettings: settings)
            try await context.runChecked(plan.copyFramework(into: written), output: .capture)
            try await context.runChecked(plan.sign(written, identity: fixture.identity), output: .capture)
        }
        try await context.runChecked(plan.zip(folder.newApp, to: folder.archive), output: .capture)
        let signed = try await context.runChecked(plan.signArchive(folder.archive, key: fixture.key), output: .capture)
        let signature = signed.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !signature.isEmpty else { throw DevFailure.checkFailed("sign_update printed no archive signature.") }
        let length = try FileManager.default.attributesOfItem(atPath: folder.archive.path)[.size] as? Int64 ?? 0
        let archive = UpdateTestFeed.Archive(
            url: base.appending(path: "update.zip"), length: length, signature: signature)
        try Data(UpdateTestFeed.text(archive: testCase.offersUpdate ? archive : nil).utf8).write(to: folder.feed)
        try await context.runChecked(plan.signFeed(folder.feed, key: fixture.key), output: .capture)
        switch testCase {
        case .alteredFeed:
            try UpdateTestFeed.altered(Data(contentsOf: folder.feed)).write(to: folder.feed)
        case .alteredArchive:
            try UpdateTestFeed.flipBit(in: folder.archive)
        case .noUpdate, .success, .refusedQuit:
            break
        }
    }
}
