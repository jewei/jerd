import Foundation
import Testing

/// Tests that draw AppKit windows run only when `JERD_WINDOW_TESTS=1`
/// (`./dev test --integration windows`, and CI). A default local run then draws no window and
/// leaves WindowServer and the screen alone.
public enum WindowTests {
    public static let isEnabled = ProcessInfo.processInfo.environment["JERD_WINDOW_TESTS"] == "1"
}

extension Trait where Self == ConditionTrait {
    /// Marks a suite or test that draws windows, so it runs only with `JERD_WINDOW_TESTS=1`.
    public static var drawsWindows: Self {
        .enabled(if: WindowTests.isEnabled, "Set JERD_WINDOW_TESTS=1, or run ./dev test --integration windows.")
    }
}
