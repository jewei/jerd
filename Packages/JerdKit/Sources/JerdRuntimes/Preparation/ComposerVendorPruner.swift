import Darwin
import Foundation
import JerdFoundation

/// Removes the files that `ComposerVendorRule` leaves out, before the payload records its files.
///
/// It never follows a link: the payload scan refuses links later anyway. A folder that is empty
/// after the removal goes too, so the payload has no empty package folders.
package enum ComposerVendorPruner {
    /// Removes the left-out files below `vendor` and returns how many it removed. A missing
    /// `vendor` folder removes nothing; the version probe then reports the broken installation.
    @discardableResult
    package static func prune(vendor: URL) throws -> Int {
        var info = stat()
        guard lstat(vendor.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return 0 }
        var removed = 0
        try visit(vendor, path: [], removed: &removed)
        return removed
    }

    /// Visits one folder and returns true when it is empty after the removal.
    @discardableResult
    private static func visit(_ folder: URL, path: [String], removed: inout Int) throws -> Bool {
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        var remaining = names.count
        for name in names {
            try Task.checkCancellation()
            let entry = folder.appendingPathComponent(name)
            var info = stat()
            guard lstat(entry.path, &info) == 0 else {
                throw JerdError.invalid("Cannot read \(entry.path) (\(SystemError.describe(errno))).")
            }
            let type = info.st_mode & S_IFMT
            if type == S_IFDIR {
                guard try visit(entry, path: path + [name], removed: &removed) else { continue }
            } else if type != S_IFREG || !ComposerVendorRule.isLeftOut(path + [name]) {
                continue
            } else {
                removed += 1
            }
            try FileManager.default.removeItem(at: entry)
            remaining -= 1
        }
        return remaining == 0
    }
}
