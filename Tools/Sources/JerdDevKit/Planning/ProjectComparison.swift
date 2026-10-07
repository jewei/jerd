import Foundation

/// Compares a freshly generated Xcode project with the committed one, file by file.
enum ProjectComparison {
    /// One way in which the committed project differs from the generated project.
    enum Difference: Equatable, CustomStringConvertible {
        case changed(String)
        case notCommitted(String)
        case notGenerated(String)

        var description: String {
            switch self {
            case .changed(let path): "\(path) differs from the generated file."
            case .notCommitted(let path): "\(path) is generated but not committed."
            case .notGenerated(let path): "\(path) is committed but XcodeGen does not make it."
            }
        }
    }

    /// Committed files that XcodeGen does not make and that belong in the project folder.
    static func isExpectedExtraFile(_ path: String) -> Bool {
        path == "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
            || path.split(separator: "/").contains("xcuserdata")
            || path.hasSuffix(".DS_Store")
    }

    /// - Parameters: Both maps use paths relative to the `.xcodeproj` folder.
    static func differences(generated: [String: Data], committed: [String: Data]) -> [Difference] {
        var result: [Difference] = []
        for path in generated.keys.sorted() {
            guard let committedData = committed[path] else {
                result.append(.notCommitted(path))
                continue
            }
            if committedData != generated[path] {
                result.append(.changed(path))
            }
        }
        for path in committed.keys.sorted() where generated[path] == nil && !isExpectedExtraFile(path) {
            result.append(.notGenerated(path))
        }
        return result
    }
}
