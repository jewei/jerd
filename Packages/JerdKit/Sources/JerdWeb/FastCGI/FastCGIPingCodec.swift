import Foundation

/// The bytes of the FastCGI request to FPM's built-in ping handler (protocol version 1, request 1).
///
/// The ping path is answered by FPM itself, so no project file runs.
public enum FastCGIPingCodec {
    /// FastCGI record types.
    enum RecordType: UInt8 {
        case beginRequest = 1
        case endRequest = 3
        case parameters = 4
        case standardInput = 5
        case standardOutput = 6
    }

    /// The CGI parameters of the ping, in order.
    static let parameters: [(String, String)] = [
        ("REQUEST_METHOD", "GET"), ("SCRIPT_NAME", FPMPoolRenderer.pingPath),
        ("SCRIPT_FILENAME", FPMPoolRenderer.pingPath), ("REQUEST_URI", FPMPoolRenderer.pingPath),
        ("SERVER_PROTOCOL", "HTTP/1.1"), ("GATEWAY_INTERFACE", "CGI/1.1"),
    ]

    /// BEGIN_REQUEST (role responder, close after the request), PARAMS, empty PARAMS, empty STDIN.
    public static func request() -> Data {
        record(.beginRequest, Data([0, 1, 0, 0, 0, 0, 0, 0])) + record(.parameters, encode(parameters))
            + record(.parameters, Data()) + record(.standardInput, Data())
    }

    /// Name-value pairs with 1-byte lengths below 128 and 4-byte lengths (high bit set) from 128.
    static func encode(_ pairs: [(String, String)]) -> Data {
        var data = Data()
        for (name, value) in pairs {
            data.append(length(name.utf8.count))
            data.append(length(value.utf8.count))
            data.append(contentsOf: name.utf8)
            data.append(contentsOf: value.utf8)
        }
        return data
    }

    /// One record without padding: `[1, type, 0, 1, length high, length low, 0, 0]` and the content.
    static func record(_ type: RecordType, _ content: Data) -> Data {
        Data([1, type.rawValue, 0, 1, UInt8(content.count >> 8), UInt8(content.count & 0xFF), 0, 0]) + content
    }

    private static func length(_ count: Int) -> Data {
        guard count >= 128 else { return Data([UInt8(count)]) }
        let value = UInt32(count) | 0x8000_0000
        return Data([UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }
}
