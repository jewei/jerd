import Foundation
import JerdFoundation
import JerdServiceKit
import JerdTestSupport
import Testing

@Suite struct MarkerFileTests {
    struct Marker: Codable, Equatable, Sendable {
        let runtime: String
        let build: Int
    }

    private func inode(_ file: URL) throws -> Int? {
        try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? Int
    }

    /// The compact format has no stable key order, so an equal marker is never written again.
    @Test func anEqualMarkerKeepsTheSavedBytesAndFile() throws {
        let directory = try TemporaryDirectory(" marker ü")
        defer { directory.remove() }
        let saved = Data(#"{"build":2,"runtime":"8.4"}"#.utf8)
        let file = try directory.file("initialized.json", saved)
        let before = try inode(file)
        #expect(try !MarkerFile.writeIfChanged(Marker(runtime: "8.4", build: 2), to: file))
        #expect(try Data(contentsOf: file) == saved)
        #expect(try inode(file) == before)
    }

    @Test func aDifferentOrMissingMarkerIsWritten() throws {
        let directory = try TemporaryDirectory(" marker ü")
        defer { directory.remove() }
        let file = directory.path("initialized.json")
        #expect(try MarkerFile.writeIfChanged(Marker(runtime: "8.4", build: 2), to: file))
        #expect(try MarkerFile.writeIfChanged(Marker(runtime: "8.5", build: 1), to: file))
        #expect(try MarkerFile.read(Marker.self, from: file) == Marker(runtime: "8.5", build: 1))
    }

    @Test func anUndecodableSavedMarkerIsCorruptAndStaysInPlace() throws {
        let directory = try TemporaryDirectory(" marker ü")
        defer { directory.remove() }
        let saved = Data("not json".utf8)
        let file = try directory.file("initialized.json", saved)
        let error = #expect(throws: JerdError.self) {
            try MarkerFile.writeIfChanged(Marker(runtime: "8.4", build: 2), to: file)
        }
        #expect(error?.kind == .corrupt)
        #expect(error?.message.hasPrefix("Cannot read initialized.json. The file was preserved.") == true)
        #expect(try Data(contentsOf: file) == saved)
    }
}
