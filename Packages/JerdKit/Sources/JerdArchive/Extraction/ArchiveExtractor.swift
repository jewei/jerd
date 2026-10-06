import Darwin
import Foundation
import JerdFoundation

/// Extracts selected regular files from a tar, gzip-compressed tar, or zip archive with strict safety rules.
///
/// Every path stays inside `destination`. Links inside the archive become regular copies of their
/// target; no symbolic link is ever created. Partial output stays on failure: extract into a
/// staging folder and remove it. The work is synchronous; run it off the cooperative thread pool.
public enum ArchiveExtractor {
    /// Extracts regular files into `destination` (created with mode 0700). Links become regular copies.
    @discardableResult
    public static func extract(
        _ archive: URL, to destination: URL, policy: ExtractionPolicy
    ) throws
        -> ExtractionReport
    {
        let reader = try ArchiveReader(archive)
        try OwnedDirectory.create(destination)
        var plan = ExtractionPlan(policy: policy)
        var buffer = [UInt8](repeating: 0, count: ArchiveReader.blockSize)
        while let header = try reader.nextHeader() {
            try Task.checkCancellation()
            guard case .writeFile(let write) = try plan.admit(header) else { continue }
            let bytes = try buffer.withUnsafeMutableBytes { chunk in
                try writeData(write, from: reader, into: destination, buffer: chunk)
            }
            try plan.recordWritten(write, bytes: bytes)
        }
        var files = plan.writtenFiles
        for copy in try plan.linkCopies() {
            let source = copy.source.url(in: destination)
            let info = try regularFileStatus(of: source)
            let output = try OutputFile(copy.path.url(in: destination), mode: info.st_mode & 0o700, within: destination)
            _ = try output.copyContents(of: source, failure: ArchiveFailure.linkTargetMissing)
            try output.setModificationTime(
                EntryTimestamp(seconds: Int64(info.st_mtimespec.tv_sec), nanoseconds: info.st_mtimespec.tv_nsec))
            files.append(copy.path)
        }
        return ExtractionReport(files: files.sorted(), outputBytes: plan.outputBytes)
    }

    /// Writes the current entry data. It may not exceed its limit and must match its declared size.
    private static func writeData(
        _ write: FileWrite, from reader: ArchiveReader, into destination: URL, buffer: UnsafeMutableRawBufferPointer
    ) throws -> Int64 {
        let output = try OutputFile(write.path.url(in: destination), mode: write.mode, within: destination)
        var written: Int64 = 0
        while true {
            try Task.checkCancellation()
            let count = try reader.readData(into: buffer)
            if count == 0 { break }
            written += Int64(count)
            guard written <= write.byteLimit else { throw write.limitFailure }
            try output.write(UnsafeRawBufferPointer(rebasing: buffer[0..<count]))
        }
        if let declared = write.declaredSize, written != declared { throw ArchiveFailure.incomplete }
        if let time = write.modificationTime { try output.setModificationTime(time) }
        return written
    }

    /// A link copy keeps the mode (0700 or 0600) and the modification time of its extracted target,
    /// like a hard link would.
    private static func regularFileStatus(of source: URL) throws -> stat {
        var info = stat()
        guard lstat(source.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw ArchiveFailure.linkTargetMissing
        }
        return info
    }
}
