/// Decides from cloudflared's own output that Cloudflare rejected the tunnel token.
///
/// Earlier builds matched words such as "unauthorized" anywhere in the log, so an origin that
/// answered 401 stopped the connector as "token rejected". This classifier accepts
/// only whole cloudflared log lines, anchored at the line start:
///
/// - `[<timestamp>] [ERR|FTL] Provided Tunnel token is not valid.` (the token does not decode).
/// - `[<timestamp>] ERR Register tunnel error from server side error="Unauthorized: …"` and
///   `[<timestamp>] ERR Serve tunnel error error="Unauthorized: …"` (the edge refused the tunnel
///   credentials, for example "Failed to get tunnel" or "Invalid tunnel secret").
///
/// Pass only the output of the current connector run, so an old rejection cannot stop a new run.
package enum TunnelAuthFailureClassifier {
    /// True when one line of `output` is a token rejection.
    package static func rejectsToken(_ output: String) -> Bool {
        let invalidToken =
            #/(?:\d{4}-\d{2}-\d{2}T[0-9:.]+(?:Z|[+-][0-9:]+)\s+)?(?:(?:ERR|FTL)\s+)?Provided Tunnel token is not valid\.?\s*/#
        let edgeRejection =
            #/(?:\d{4}-\d{2}-\d{2}T[0-9:.]+(?:Z|[+-][0-9:]+)\s+)?ERR\s+(?:Register tunnel error from server side|Serve tunnel error)\s+error="Unauthorized: /#
        return output.split(whereSeparator: \.isNewline).contains { line in
            line.wholeMatch(of: invalidToken) != nil || line.prefixMatch(of: edgeRejection) != nil
        }
    }
}
