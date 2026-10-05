/// A program that `./dev` needs, with the exact install hint for a missing copy.
enum Prerequisite: CaseIterable, Sendable {
    case xcode
    case swift
    case swiftFormat
    case xcodeGen
    case gitHubCLI

    var name: String {
        switch self {
        case .xcode: "Xcode"
        case .swift: "Swift 6"
        case .swiftFormat: "swift-format"
        case .xcodeGen: "XcodeGen"
        case .gitHubCLI: "GitHub CLI (gh)"
        }
    }

    /// Only release publishing needs the GitHub CLI, so `doctor` reports it for information only.
    var isRequired: Bool { self != .gitHubCLI }

    var installHint: String {
        let selectXcode = "sudo xcode-select --switch /Applications/Xcode.app"
        switch self {
        case .xcode:
            return "Install the Xcode version in .xcode-version from "
                + "https://developer.apple.com/download/applications/, then run: \(selectXcode)"
        case .swift, .swiftFormat:
            return "It comes with Xcode 16 or later. Select that Xcode: \(selectXcode)"
        case .xcodeGen:
            return "Install the version in Tools/xcodegen-version: brew install xcodegen "
                + "(or download it from https://github.com/yonaskolb/XcodeGen/releases)"
        case .gitHubCLI:
            return "Install it only for release publishing: brew install gh"
        }
    }

    var missingMessage: String { "\(name) is missing. \(installHint)" }
}
