import Darwin
import Foundation
import JerdFoundation

/// Finds the active-run records on disk, from the fixed scans of a `DataLayout`.
///
/// A folder with a wrong type or owner gives one failure entry for its part only, so healthy
/// services still appear. Names that are not UUIDs are ignored; linked instance folders and linked
/// record files are skipped.
enum RecordLocationScanner {
    /// One scan result, in display order.
    enum Entry: Equatable, Sendable {
        case location(RecordLocation)
        case failure(id: String, title: String, message: String)
    }

    static func scan(_ layout: DataLayout) -> [Entry] {
        layout.recordScans.flatMap { scan($0, root: layout.root) }
    }

    /// The locations only, for lookups by ID.
    static func locations(_ layout: DataLayout) -> [RecordLocation] {
        scan(layout).compactMap { entry in
            if case .location(let location) = entry { return location }
            return nil
        }
    }

    private static func scan(_ scan: RecordScan, root: URL) -> [Entry] {
        guard FileProbe.presence(at: scan.directory) != .absent else { return [] }
        do {
            try OwnedDirectory.requireContained(scan.directory, in: root)
            switch scan.arrangement {
            case .single(let location):
                return FileProbe.presence(at: location.recordFile).mayExist ? [.location(location)] : []
            case .folderPerInstance(let locate):
                return try instances(in: scan.directory).compactMap { id, url in
                    folderEntry(id: id, folder: url, family: scan.family, root: root, locate: locate)
                }
            case .filePerInstance(let fileExtension, let locate):
                return try instances(in: scan.directory, fileExtension: fileExtension).compactMap { id, url in
                    isLink(url) ? nil : .location(locate(id, url))
                }
            }
        } catch {
            let message = FailureDetail.describe(error)
            return [.failure(id: scan.family.displayName, title: scan.family.displayName, message: message)]
        }
    }

    /// True when `url` is a symbolic link. Linked children are skipped, as in old builds.
    private static func isLink(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == S_IFLNK
    }

    private static func folderEntry(
        id: UUID, folder: URL, family: RecordFamily, root: URL, locate: RecordScan.Locate
    ) -> Entry? {
        var info = stat()
        guard lstat(folder.path, &info) == 0, !isLink(folder) else { return nil }
        let location = locate(id, folder)
        do {
            try OwnedDirectory.requireContained(folder, in: root)
        } catch {
            return .failure(id: location.id, title: Self.title(location), message: FailureDetail.describe(error))
        }
        return FileProbe.presence(at: location.recordFile).mayExist ? .location(location) : nil
    }

    /// Children whose name (without `fileExtension`, when given) is a UUID, sorted by UUID text.
    private static func instances(in directory: URL, fileExtension: String? = nil) throws -> [(UUID, URL)] {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let found = names.compactMap { name -> (UUID, URL)? in
            let url = directory.appendingPathComponent(name)
            if let fileExtension {
                guard url.pathExtension == fileExtension else { return nil }
                return UUID(uuidString: url.deletingPathExtension().lastPathComponent).map { ($0, url) }
            }
            return UUID(uuidString: name).map { ($0, url) }
        }
        return found.sorted { $0.0.uuidString < $1.0.uuidString }
    }

    /// The short display name of a location, for example "Database 1F3A0000".
    static func title(_ location: RecordLocation) -> String {
        guard let instance = location.instance else { return location.displayName }
        return "\(location.displayName) \(instance.uuidString.prefix(8))"
    }
}
