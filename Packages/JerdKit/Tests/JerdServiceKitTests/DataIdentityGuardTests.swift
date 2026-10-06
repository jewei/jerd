import Foundation
import JerdFoundation
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

@Suite struct DataIdentityGuardTests {
    struct Identity: Codable, Equatable, Sendable {
        let runtime: String
    }

    static let messages = DataIdentityGuard<Identity>.Messages(
        mismatch: .invalid("Different version."), untracked: .invalid("Untracked data."))

    @Test func untouchedDataGetsTheExpectedIdentity() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let guardian = DataIdentityGuard(file: directory.path("runtime.json"), messages: Self.messages)
        try guardian.admit(Identity(runtime: "a"), dataIsUntouched: true)
        #expect(try guardian.saved() == Identity(runtime: "a"))
        #expect(mode(directory.path("runtime.json")) == 0o600)
        try guardian.admit(Identity(runtime: "a"), dataIsUntouched: false)
    }

    @Test func dataWithoutAnIdentityIsNeverAdopted() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let guardian = DataIdentityGuard(file: directory.path("runtime.json"), messages: Self.messages)
        #expect(throws: JerdError.invalid("Untracked data.")) {
            try guardian.admit(Identity(runtime: "a"), dataIsUntouched: false)
        }
        #expect(!exists(directory.path("runtime.json")))
    }

    @Test func anotherIdentityIsRefusedAndKept() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let guardian = DataIdentityGuard(file: directory.path("runtime.json"), messages: Self.messages)
        try guardian.admit(Identity(runtime: "a"), dataIsUntouched: true)
        let saved = contents(directory.path("runtime.json"))
        #expect(throws: JerdError.invalid("Different version.")) {
            try guardian.admit(Identity(runtime: "b"), dataIsUntouched: true)
        }
        #expect(contents(directory.path("runtime.json")) == saved)
    }

    @Test func anUnreadableIdentityIsCorruptAndPreserved() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        try write("{broken", to: directory.path("runtime.json"))
        let guardian = DataIdentityGuard(file: directory.path("runtime.json"), messages: Self.messages)
        #expect {
            try guardian.admit(Identity(runtime: "a"), dataIsUntouched: true)
        } throws: { ($0 as? JerdError)?.kind == .corrupt }
        #expect(text(directory.path("runtime.json")) == "{broken")
    }

    static let markerMessages = InitializationMarker<Identity>.Messages(
        mismatch: .corrupt("Marker mismatch."), interrupted: .corrupt("Interrupted."))

    @Test func aMatchingMarkerWithCompleteDataIsInitialized() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let marker = InitializationMarker(file: directory.path("initialized.json"), messages: Self.markerMessages)
        #expect(
            try marker.status(expected: Identity(runtime: "a"), dataIsComplete: false, dataMayExist: false)
                == .uninitialized)
        try marker.write(Identity(runtime: "a"))
        #expect(
            try marker.status(expected: Identity(runtime: "a"), dataIsComplete: true, dataMayExist: true)
                == .initialized)
    }

    @Test func aMarkerWithMissingDataOrAnotherIdentityIsRefused() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let marker = InitializationMarker(file: directory.path("initialized.json"), messages: Self.markerMessages)
        try marker.write(Identity(runtime: "a"))
        #expect(throws: JerdError.corrupt("Marker mismatch.")) {
            try marker.status(expected: Identity(runtime: "a"), dataIsComplete: false, dataMayExist: true)
        }
        #expect(throws: JerdError.corrupt("Marker mismatch.")) {
            try marker.status(expected: Identity(runtime: "b"), dataIsComplete: true, dataMayExist: true)
        }
    }

    @Test func partialDataWithoutAMarkerIsNeverInitializedAgain() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let marker = InitializationMarker(file: directory.path("initialized.json"), messages: Self.markerMessages)
        #expect(throws: JerdError.corrupt("Interrupted.")) {
            try marker.status(expected: Identity(runtime: "a"), dataIsComplete: true, dataMayExist: true)
        }
        let lenient = InitializationMarker<Identity>(
            file: directory.path("initialized.json"), messages: .init(mismatch: .corrupt("x"), interrupted: nil))
        #expect(
            try lenient.status(expected: Identity(runtime: "a"), dataIsComplete: true, dataMayExist: true)
                == .uninitialized)
    }

    @Test func dataFolderChecksDoNotFollowLinks() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        try FileManager.default.createDirectory(at: directory.path("real"), withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            at: directory.path("link"), withDestinationURL: directory.path("real"))
        #expect(DataFolder.isRealDirectory(directory.path("real")))
        #expect(!DataFolder.isRealDirectory(directory.path("link")))
        #expect(try DataFolder.isAbsentOrEmpty(directory.path("real")))
        #expect(try DataFolder.isAbsentOrEmpty(directory.path("missing")))
        #expect(try !DataFolder.isAbsentOrEmpty(directory.path("link")))
        try write("x", to: directory.path("real/file"))
        #expect(try !DataFolder.isAbsentOrEmpty(directory.path("real")))
        #expect(DataFolder.isRegularFile(directory.path("real/file")))
    }

    @Test(arguments: [
        ("mysql-8.4.11-arm64", true), ("8.4.11", true), (".", false), ("..", false), ("", false), ("a/b", false),
        ("a b", false), ("café", false), (String(repeating: "a", count: 100), true),
        (String(repeating: "a", count: 101), false),
    ])
    func safeIdentifiersUseOnlyPortableCharacters(value: String, valid: Bool) {
        #expect(SafeIdentifier.isValid(value) == valid)
    }

    @Test func runtimePathsMustBeAbsoluteWithoutControlCharacters() {
        #expect(SafeIdentifier.isAbsolutePath("/Applications/Jerd runtimes/mysql"))
        #expect(!SafeIdentifier.isAbsolutePath("relative/mysql"))
        #expect(!SafeIdentifier.isAbsolutePath("/bad\npath"))
    }
}
