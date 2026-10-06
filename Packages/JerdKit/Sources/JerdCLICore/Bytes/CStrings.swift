import Darwin

/// Copies between C strings and byte arrays without a text decoding, so no byte changes.
///
/// The launcher is a pass-through wrapper: PHP must get the exact bytes that the shell gave the
/// launcher, also bytes that are not valid UTF-8. `String(cString:)` repairs such bytes to U+FFFD,
/// so user arguments and environment entries never go through `String`.
enum CStrings {
    /// The bytes of one NUL-terminated C string, without the NUL.
    static func bytes(_ pointer: UnsafePointer<CChar>) -> [UInt8] {
        let count = strlen(pointer)
        return pointer.withMemoryRebound(to: UInt8.self, capacity: count) {
            Array(UnsafeBufferPointer(start: $0, count: count))
        }
    }

    /// The items of a NULL-terminated C string vector, for example `argv` or `environ`.
    static func list(_ vector: UnsafePointer<UnsafeMutablePointer<CChar>?>?) -> [[UInt8]] {
        guard let vector else { return [] }
        var items: [[UInt8]] = []
        var index = 0
        while let item = vector[index] {
            items.append(bytes(item))
            index += 1
        }
        return items
    }

    /// Calls `body` with a NULL-terminated vector of C copies of `items`. The copies live only
    /// during the call.
    static func withVector<Result>(
        _ items: [[UInt8]], _ body: (UnsafePointer<UnsafeMutablePointer<CChar>?>) -> Result
    ) -> Result {
        let vector = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: items.count + 1)
        for (index, item) in items.enumerated() { vector[index] = copy(item) }
        vector[items.count] = nil
        defer {
            for index in 0..<items.count { vector[index]?.deallocate() }
            vector.deallocate()
        }
        return body(UnsafePointer(vector))
    }

    /// True when `bytes` are valid UTF-8. A byte order mark is valid text and stays.
    static func isUTF8(_ bytes: some Collection<UInt8>) -> Bool {
        String(decoding: bytes, as: UTF8.self).utf8.elementsEqual(bytes)
    }

    /// A NUL-terminated copy of `bytes`. A NUL inside `bytes` ends the C string there, as the
    /// kernel reads it; the shell cannot pass such a byte.
    private static func copy(_ bytes: [UInt8]) -> UnsafeMutablePointer<CChar> {
        let pointer = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count + 1)
        for (offset, byte) in bytes.enumerated() { pointer[offset] = CChar(bitPattern: byte) }
        pointer[bytes.count] = 0
        return pointer
    }
}
