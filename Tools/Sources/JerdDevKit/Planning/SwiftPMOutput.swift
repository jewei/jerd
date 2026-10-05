/// Recognizes the build progress lines of `swift test` and `swift run`. Quiet output hides them;
/// compiler diagnostics stay visible.
enum SwiftPMOutput {
    static func isProgress(_ line: String) -> Bool {
        if line.hasPrefix("Building for ") || line.hasPrefix("Build complete!") {
            return true
        }
        return line.hasPrefix("[") && line.contains("]")
    }
}
