import Foundation
import JerdFoundation

/// Makes a RustFS binary independent of Homebrew.
///
/// Upstream RustFS for macOS links `/opt/homebrew/opt/xz/lib/liblzma.5.dylib`. Without Homebrew XZ
/// the binary does not start; with it, the runtime silently depends on Homebrew. This step copies
/// the reviewed XZ library and its license into the payload, points the reference to
/// `@loader_path/liblzma.5.dylib`, and signs the changed binary ad hoc. The release tool signs it
/// again with Developer ID. Any other library outside the system is refused.
package struct LZMALinker {
    package static let libraryName = "liblzma.5.dylib"
    package static let licenseName = "XZ-LICENSE.txt"
    package static let bundledReference = "@loader_path/liblzma.5.dylib"

    package let context: PreparationContext

    package init(context: PreparationContext) { self.context = context }

    /// True for a reference that macOS or the payload itself provides.
    package static func isProvided(_ name: String) -> Bool {
        ["/usr/lib/", "/System/Library/", "@loader_path/", "@executable_path/", "@rpath/"].contains {
            name.hasPrefix($0)
        }
    }

    package func bundleLibraryIfNeeded(for binary: URL) async throws {
        let data = try await BlockingWork.run { try Data(contentsOf: binary) }
        let external = try MachOLoadCommands.libraries(in: data).filter { !Self.isProvided($0.name) }
        guard !external.isEmpty else { return }
        if let other = external.first(where: { URL(fileURLWithPath: $0.name).lastPathComponent != Self.libraryName }) {
            throw JerdError.invalid("This RustFS release needs \(other.name), which Jerd cannot supply.")
        }
        guard let lzma = context.tools.lzma else {
            throw JerdError.unavailable(
                "This RustFS release needs the XZ library from Homebrew. Jerd needs its bundled XZ library to install it."
            )
        }
        let payload = context.payload
        try await BlockingWork.run {
            var changed = data
            for reference in external {
                changed = try MachOLoadCommands.rename(reference, to: Self.bundledReference, in: changed)
            }
            try Self.replace(binary, with: changed)
            try Self.copyPrivate(lzma.library, to: payload.appendingPathComponent(Self.libraryName))
            try Self.copyPrivate(lzma.license, to: payload.appendingPathComponent(Self.licenseName))
        }
        try await context.run("/usr/bin/codesign", ["--force", "--sign", "-", binary.path], in: context.staging)
    }

    private static func replace(_ binary: URL, with data: Data) throws {
        try AtomicFile.write(data, to: binary, durability: .standard)
        guard chmod(binary.path, 0o700) == 0 else {
            throw JerdError.unavailable("Cannot protect \(binary.path) (\(SystemError.describe(errno))).")
        }
    }

    private static func copyPrivate(_ source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
        guard chmod(destination.path, 0o600) == 0 else {
            throw JerdError.unavailable("Cannot protect \(destination.path) (\(SystemError.describe(errno))).")
        }
    }
}
