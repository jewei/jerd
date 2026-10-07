import Foundation
import JerdFoundation

/// Reads the FastCGI response of a ping in pieces, with a size limit.
///
/// Rules: every record has version 1 and request ID 1; all records together stay within 16 KiB;
/// STDOUT content is collected; other records except END_REQUEST are ignored. END_REQUEST must
/// report application status 0 and protocol status 0, and the body after the headers must be
/// exactly the ping response.
struct FastCGIResponseDecoder {
    /// The largest response, headers and padding included.
    static let limit = 16_384

    private var buffer = Data()
    private var consumed = 0
    private var output = Data()

    /// Adds received bytes. Returns true once a valid END_REQUEST arrived.
    mutating func consume(_ bytes: Data) throws -> Bool {
        buffer.append(bytes)
        while buffer.count >= 8 {
            let header = [UInt8](buffer.prefix(8))
            guard header[0] == 1, header[2] == 0, header[3] == 1 else {
                throw JerdError.processFailed("FPM returned an invalid FastCGI response.")
            }
            let length = Int(header[4]) << 8 | Int(header[5])
            let total = 8 + length + Int(header[6])
            guard consumed + total <= Self.limit else {
                throw JerdError.processFailed("The FPM readiness response is too large.")
            }
            guard buffer.count >= total else { return false }
            let body = Data(buffer.dropFirst(8).prefix(length))
            buffer = Data(buffer.dropFirst(total))
            consumed += total
            switch FastCGIPingCodec.RecordType(rawValue: header[1]) {
            case .standardOutput: output.append(body)
            case .endRequest: return try finish(body)
            default: continue
            }
        }
        return false
    }

    private func finish(_ body: Data) throws -> Bool {
        guard body.count == 8, body.prefix(5).allSatisfy({ $0 == 0 }),
            let response = String(data: output, encoding: .utf8),
            response.components(separatedBy: "\r\n\r\n").last == FPMPoolRenderer.pingResponse
        else { throw JerdError.processFailed("FPM did not return its readiness response.") }
        return true
    }
}
