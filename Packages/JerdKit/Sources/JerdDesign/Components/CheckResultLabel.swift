import SwiftUI

/// The result of one check, for example "Passed at start". Only the symbol carries the tone
/// color; the text uses the primary label color, because green text on a light form row has a
/// contrast of about 1.8:1 (WCAG asks 4.5:1). The symbol shape says passed or not run, so the
/// result never depends on color alone.
public struct CheckResultLabel: View {
    private let result: String
    private let passed: Bool

    /// - Parameter passed: True when the check ran and passed; false when it did not run.
    public init(_ result: String, passed: Bool) {
        self.result = result
        self.passed = passed
    }

    public var body: some View {
        Label {
            Text(result)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: passed ? StatusTone.ready.systemImage : "circle.dashed")
                .foregroundStyle(passed ? StatusTone.ready.color : .secondary)
        }
        .labelStyle(.titleAndIcon)
    }
}
