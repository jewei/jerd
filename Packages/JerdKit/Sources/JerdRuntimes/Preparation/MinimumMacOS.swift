import Foundation

/// The oldest macOS that a runtime which Jerd builds from source must run on: the minimum of the app.
///
/// A compiler targets the macOS of the build Mac unless it gets a deployment target, so a Redis built
/// on a new macOS would not start on the older systems that the app supports.
public struct MinimumMacOS: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    /// The minimum of JerdKit itself (`platforms` in `Package.swift`), for a process without an app
    /// bundle, such as a test run.
    public static let jerdKitMinimum = MinimumMacOS(major: 14, minor: 0)

    /// `LSMinimumSystemVersion` of the app's Info.plist, which Xcode writes from
    /// `MACOSX_DEPLOYMENT_TARGET`.
    public static let infoPlistKey = "LSMinimumSystemVersion"

    public init(major: Int, minor: Int, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses `14`, `14.0`, or `14.0.1`.
    public init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard (1...4).contains(part.count), part.utf8.allSatisfy({ (48...57).contains($0) }),
                let number = Int(part)
            else { return nil }
            numbers.append(number)
        }
        numbers += Array(repeating: 0, count: 3 - numbers.count)
        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2])
    }

    /// The minimum of the app in `bundle`, or the JerdKit minimum when the bundle has no valid value.
    public static func of(_ bundle: Bundle) -> MinimumMacOS {
        (bundle.object(forInfoDictionaryKey: infoPlistKey) as? String).flatMap(MinimumMacOS.init) ?? jerdKitMinimum
    }

    /// `14.0`, or `14.0.1` when the patch is not zero: the form of `MACOSX_DEPLOYMENT_TARGET`.
    public var description: String { patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)" }

    /// The compiler and linker flag that sets the minimum, for builds that ignore the environment.
    public var compilerFlag: String { "-mmacosx-version-min=\(description)" }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
