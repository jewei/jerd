import Foundation
import JerdFoundation
import JerdManifest

/// Refuses a runtime that Jerd built from source when one of its Mach-O files needs a newer macOS
/// than the app. Such a build starts on the build Mac, but not on every Mac that runs the app.
///
/// `./dev runtimes verify` does the same check with `otool` for the payloads in the app bundle.
package enum SourceBuildCheck {
    /// The universal magics `0xCAFEBABE` and `0xCAFEBABF`, as a little-endian read sees their
    /// big-endian headers.
    static let universalMagics: Set<UInt32> = [0xBEBA_FECA, 0xBFBA_FECA]
    private static let headerSize = 32

    /// One line for each Mach-O file of `files` that needs a newer macOS than `minimum`, as
    /// `<file> needs macOS <version>`. Other files are skipped. Empty when every file runs on `minimum`.
    package static func problems(
        files: some Sequence<RelativePath>, in payload: URL, minimum: MinimumMacOS
    ) throws -> [String] {
        var problems: [String] = []
        for path in files.sorted(by: { $0.string < $1.string }) {
            guard let header = try loadCommands(of: path.url(in: payload)) else { continue }
            guard header.isThin else {
                problems.append("\(path.string) is a universal file, which a source build never makes")
                continue
            }
            if let required = try MachOLoadCommands.minimumMacOS(in: header.bytes), required > minimum {
                problems.append("\(path.string) needs macOS \(required)")
            }
        }
        return problems
    }

    /// - Throws: `.invalid` that names each file and both versions, when `problems` finds one.
    package static func verify(
        _ kind: RuntimeKind, files: some Sequence<RelativePath>, in payload: URL, minimum: MinimumMacOS
    ) throws {
        let problems = try problems(files: files, in: payload, minimum: minimum)
        guard !problems.isEmpty else { return }
        throw JerdError.invalid(
            "The \(kind.title) build does not run on macOS \(minimum), the oldest macOS that Jerd supports: "
                + "\(problems.joined(separator: "; ")). Jerd installed nothing.")
    }

    /// The header and load commands of a Mach-O file, or nil for any other file.
    private static func loadCommands(of file: URL) throws -> (bytes: Data, isThin: Bool)? {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: file)
        } catch {
            throw JerdError.invalid("The built runtime file \(file.lastPathComponent) cannot be read.")
        }
        defer { try? handle.close() }
        guard let header = try handle.read(upToCount: headerSize), header.count >= 4 else { return nil }
        let bytes = [UInt8](header)
        let magic = word(bytes, at: 0)
        if universalMagics.contains(magic) { return (header, false) }
        guard magic == MachOLoadCommands.magic64, bytes.count == headerSize else { return nil }
        let commandBytes = Int(word(bytes, at: 20))
        let commands = try handle.read(upToCount: commandBytes) ?? Data()
        return (header + commands, true)
    }

    private static func word(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * UInt32($1)) }
    }
}
