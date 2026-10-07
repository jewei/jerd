import Foundation

/// The one format of a byte count for the user, for example `168 MB` or `122.5 MB`. The number and
/// its unit are joined by a no-break space, so a line never breaks between them.
public enum ByteText {
    public static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            .replacingOccurrences(of: " ", with: "\u{00A0}")
    }
}
