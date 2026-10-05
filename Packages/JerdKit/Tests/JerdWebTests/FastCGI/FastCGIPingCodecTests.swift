import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct FastCGIPingCodecTests {
    @Test func theRequestHasTheFourRecordsInOrder() {
        let request = [UInt8](FastCGIPingCodec.request())
        #expect(Array(request[0..<16]) == [1, 1, 0, 1, 0, 8, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0])
        #expect(Array(request[16..<20]) == [1, 4, 0, 1])
        let length = Int(request[20]) << 8 | Int(request[21])
        let parameters = Data(request[24..<(24 + length)])
        #expect(parameters == FastCGIPingCodec.encode(FastCGIPingCodec.parameters))
        #expect(Array(request[(24 + length)...]) == [1, 4, 0, 1, 0, 0, 0, 0, 1, 5, 0, 1, 0, 0, 0, 0])
        let text = String(decoding: parameters, as: UTF8.self)
        #expect(text.contains("REQUEST_METHODGET") && text.contains("SCRIPT_FILENAME/.jerd/fpm-ping"))
    }

    @Test func shortAndLongLengthsUseOneOrFourBytes() {
        #expect([UInt8](FastCGIPingCodec.encode([("AB", "xyz")])) == [2, 3, 65, 66, 120, 121, 122])
        let long = String(repeating: "v", count: 200)
        let encoded = [UInt8](FastCGIPingCodec.encode([("N", long)]))
        #expect(Array(encoded[0..<5]) == [1, 0x80, 0, 0, 200])
        #expect(encoded.count == 5 + 1 + 200)
    }

    @Test func aCompleteResponseIsAcceptedAlsoInSmallPieces() throws {
        let response = FakeFPMServer.record(7, Data("stderr".utf8), padding: 3) + FakeFPMServer.response()
        var whole = FastCGIResponseDecoder()
        #expect(try whole.consume(response))
        var pieces = FastCGIResponseDecoder()
        var finished = false
        for byte in response { finished = try pieces.consume(Data([byte])) }
        #expect(finished)
    }

    @Test func anIncompleteResponseNeedsMoreBytes() throws {
        var decoder = FastCGIResponseDecoder()
        #expect(try !decoder.consume(FakeFPMServer.response().dropLast(3)))
    }

    @Test(arguments: [
        FakeFPMServer.record(6, Data(), version: 2), FakeFPMServer.record(6, Data(), requestID: 2),
    ])
    func aWrongVersionOrRequestIDIsInvalid(_ bytes: Data) {
        var decoder = FastCGIResponseDecoder()
        #expect(throws: JerdError.processFailed("FPM returned an invalid FastCGI response.")) {
            try decoder.consume(bytes)
        }
    }

    @Test func aResponseAbove16KiBIsRefusedAtItsHeader() throws {
        var decoder = FastCGIResponseDecoder()
        _ = try decoder.consume(FakeFPMServer.record(6, Data(repeating: 65, count: 16_000)))
        #expect(throws: JerdError.processFailed("The FPM readiness response is too large.")) {
            try decoder.consume(FakeFPMServer.record(6, Data(repeating: 65, count: 400)).prefix(8))
        }
    }

    @Test(arguments: [
        FakeFPMServer.response(appStatus: 1), FakeFPMServer.response(body: "PHP output"),
        FakeFPMServer.record(6, Data([0xFF, 0xFE])) + FakeFPMServer.record(3, Data(count: 8)),
        FakeFPMServer.record(6, Data("Jerd FPM is ready.".utf8)) + FakeFPMServer.record(3, Data(count: 4)),
    ])
    func aWrongEndOrBodyIsNotTheReadinessResponse(_ bytes: Data) {
        var decoder = FastCGIResponseDecoder()
        #expect(throws: JerdError.processFailed("FPM did not return its readiness response.")) {
            try decoder.consume(bytes)
        }
    }
}
