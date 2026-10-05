import Foundation
import JerdArchive
import JerdFoundation
import JerdManifest

/// Turns a verified artifact into the files of one runtime kind, inside `context.payload`.
package protocol RuntimePreparing: Sendable {
    func prepare(_ context: PreparationContext) async throws
}
