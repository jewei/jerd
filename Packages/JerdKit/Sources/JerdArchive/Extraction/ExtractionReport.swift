import JerdFoundation

/// The result of an extraction: every file written (links included) and the bytes written.
public struct ExtractionReport: Sendable, Equatable {
    /// Every extracted file, sorted. Link copies are regular files and are included.
    public let files: [RelativePath]
    /// The bytes of all extracted files.
    public let outputBytes: Int64

    public init(files: [RelativePath], outputBytes: Int64) {
        self.files = files
        self.outputBytes = outputBytes
    }
}
