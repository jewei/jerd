import Foundation
import JerdSnapshotSupport

// Renders SwiftUI views to PNG files offscreen. See Sources/JerdSnapshotSupport/README.md.
// Nothing here may touch AppKit before the command fixes the process settings.
let status = await SnapshotCommand(catalog: .jerd).run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(status)
