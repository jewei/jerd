import Foundation
import JerdUI

/// Builds the Files section values of a service from its paths. It only checks presence.
package enum ServiceFilesProbe {
    package static func files(dataFolder: URL, log: URL) -> ServiceFiles {
        ServiceFiles(
            dataFolder: dataFolder, log: log, hasDataFolder: isDirectory(dataFolder),
            hasLog: FileManager.default.fileExists(atPath: log.path))
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
