import Foundation

// Renders SwiftUI views to PNG files offscreen. See Sources/JerdDesign/README.md.
let status = MainActor.assumeIsolated {
    SnapshotCommand(catalog: .jerd).run(arguments: Array(CommandLine.arguments.dropFirst()))
}
exit(status)
