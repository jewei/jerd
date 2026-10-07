import Darwin
import Foundation
import JerdFoundation

/// Where the bytes of a transfer go: memory, or an open file descriptor that the fetcher owns.
enum TransferSink: Sendable {
    case memory
    case file(Int32)

    /// Writes one chunk to the file. Memory chunks are kept by the transfer state.
    /// - Returns: 0 on success, else the `errno` of the failed write.
    func write(_ chunk: Data) -> Int32 {
        guard case .file(let descriptor) = self else { return 0 }
        return DescriptorIO.writeAll(chunk, to: descriptor)
    }
}
