import Darwin
import Foundation
import JerdFoundation

/// The planned new bytes of one zsh startup file, with its original bytes for backup and rollback.
struct ShellFileChange: Equatable, Sendable {
    /// The mode of a startup file that the setup creates.
    static let newFileMode: mode_t = 0o600

    let file: URL
    /// The bytes before the setup, or nil when the file did not exist.
    let original: Data?
    let updated: Data
    /// The permission bits that the replacement keeps.
    let mode: mode_t

    /// Plans the change of `file` from its current bytes.
    /// - Throws: `.invalid` for text that is not UTF-8 or a malformed Jerd block.
    init(file: URL, original: Data?, mode: mode_t) throws {
        guard let text = String(data: original ?? Data(), encoding: .utf8) else {
            throw JerdError.invalid(
                "\(file.path) is not UTF-8 text. It was preserved. Add the Jerd PATH block yourself.")
        }
        guard ShellPathBlockEditor.state(of: text) != .malformed else {
            throw JerdError.invalid(
                "The Jerd PATH block in \(file.path) needs manual review. It was preserved. "
                    + "Keep one block between its two marker lines, then set up the commands again.")
        }
        self.file = file
        self.original = original
        self.updated = Data(try ShellPathBlockEditor.apply(to: text).utf8)
        self.mode = mode
    }

    /// True when the setup must write the file.
    var changesFile: Bool { original != updated }

    /// The fixed stage name beside the file: `<name>.jerd-tmp`.
    var stage: URL {
        file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + ".jerd-tmp")
    }
}
