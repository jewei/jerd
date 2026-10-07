import Foundation
import JerdArchive
import JerdFoundation
import JerdManifest

/// Turns a verified artifact into the files of one runtime kind, inside `context.payload`.
package protocol RuntimePreparing: Sendable {
    /// True when the preparation compiles code on this Mac. The pipeline then checks that every
    /// Mach-O file runs on `PreparationContext.minimumMacOS`.
    var buildsFromSource: Bool { get }

    func prepare(_ context: PreparationContext) async throws
}

extension RuntimePreparing {
    package var buildsFromSource: Bool { false }
}
