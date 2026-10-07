import Foundation
import JerdManifest

extension RuntimesEmbedStep {
    /// The prepared support folders to embed. Each must match its pin, the deployment target of the
    /// app, and its receipt; an invalid one fails, and a missing one fails only when all are required.
    static func checkedSupport(
        _ context: DevContext, catalog: RuntimePinCatalog, requiresAll: Bool
    ) throws -> [(name: String, folder: URL)] {
        let target = try context.repository.runtimeMinimumMacOS().description
        var result: [(name: String, folder: URL)] = []
        for name in EmbeddedSupport.names(catalog) {
            let folder = EmbeddedSupport.preparedFolder(name, in: context.repository)
            switch EmbeddedSupport.state(of: name, in: folder, catalog: catalog, deploymentTarget: target) {
            case .valid:
                result.append((name, folder))
            case .invalid(let message):
                throw DevFailure.checkFailed(
                    "The prepared \(name) support library is invalid: \(message) Run ./dev runtimes prepare xz.")
            case .missing:
                guard !requiresAll else {
                    throw DevFailure.checkFailed(
                        "A Release build needs the \(name) support library for RustFS. Run ./dev runtimes prepare xz.")
                }
                context.console.warning(
                    "The app builds without the \(name) support library, so it cannot install RustFS.")
            }
        }
        return result
    }
}
