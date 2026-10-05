import JerdTunnels
import Testing

@Suite struct TunnelAuthFailureClassifierTests {
    /// Lines in the form that cloudflared prints when Cloudflare refuses the token or the tunnel credentials.
    static let rejections = [
        "Provided Tunnel token is not valid.",
        "2026-09-03T10:15:42Z ERR Provided Tunnel token is not valid.",
        "2026-09-03T10:15:42Z ERR Register tunnel error from server side error=\"Unauthorized: Failed to get tunnel\" "
            + "connIndex=0 event=0 ip=198.41.200.13",
        "2026-09-03T10:15:42Z ERR Serve tunnel error error=\"Unauthorized: Failed to get tunnel\" connIndex=0 "
            + "event=0 ip=198.41.200.13",
        "2023-03-13T08:21:47Z ERR Register tunnel error from server side error=\"Unauthorized: Invalid tunnel secret\" "
            + "connIndex=0 ip=198.41.192.227",
        "2026-09-03T10:15:42.123+02:00 ERR Register tunnel error from server side error=\"Unauthorized: Tunnel not "
            + "found\" connIndex=1",
    ]

    /// Lines that mention authorization but are not a token rejection: origin answers, access logs,
    /// user paths, and quoted text inside other messages.
    static let otherLines = [
        "2026-09-03T10:15:42Z ERR  error=\"Unauthorized\" cfRay=8c1f originService=http://127.0.0.1:8000",
        "2026-09-03T10:15:42Z DBG GET https://preview.example.com/admin HTTP/1.1 status=401 Unauthorized",
        "2026-09-03T10:15:42Z INF Request to /unauthorized returned 401",
        "2026-09-03T10:15:42Z ERR Request failed error=\"authentication failed for user admin\" originService=x",
        "2026-09-03T10:15:42Z INF Received message: Provided Tunnel token is not valid.",
        "2026-09-03T10:15:42Z ERR invalid tunnel token in request header",
        "2026-09-03T10:15:42Z WRN Register tunnel error from server side error=\"Unauthorized: x\"",
        "2026-09-03T10:15:42Z ERR Register tunnel error from server side error=\"connection refused\"",
        "2026-09-03T10:15:42Z INF Registered tunnel connection connIndex=0 location=fra08 protocol=quic",
    ]

    @Test(arguments: rejections)
    func aRejectionLineIsRecognized(_ line: String) {
        #expect(TunnelAuthFailureClassifier.rejectsToken(line))
        #expect(TunnelAuthFailureClassifier.rejectsToken("2026-09-03T10:15:40Z INF Starting tunnel\n\(line)\n"))
    }

    /// Fix of spec E 7.1.3: any line with "unauthorized" stopped the connector as "token rejected".
    @Test(arguments: otherLines)
    func otherLinesAreNotARejection(_ line: String) {
        #expect(!TunnelAuthFailureClassifier.rejectsToken(line))
    }

    @Test func emptyOutputIsNotARejection() {
        #expect(!TunnelAuthFailureClassifier.rejectsToken(""))
    }
}
