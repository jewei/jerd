import Foundation
import CArchive

/// Extracts only regular files. Internal archive links become regular copies.
enum RuntimeArchive {
    static func extract(_ source: URL, to destination: URL, stripRoot: Bool = false, outputLimit: Int64 = 2_000_000_000,
                        selected: (String) -> Bool = { _ in true }) throws {
        guard let reader = archive_read_new() else { throw JerdError.unavailable("Cannot open the runtime archive.") }
        defer { archive_read_free(reader) }
        archive_read_support_filter_gzip(reader)
        archive_read_support_format_tar(reader)
        archive_read_support_format_zip(reader)
        guard archive_read_open_filename(reader, source.path, 1_048_576) == ARCHIVE_OK else {
            throw JerdError.invalid("The runtime archive cannot be read.")
        }
        try PrivateFiles.directory(destination)
        var entry: OpaquePointer?
        var files = Set<String>(), names = Set<String>()
        var links: [String: String] = [:]
        var fileSizes: [String: Int64] = [:]
        var archiveRoot: String?
        var count = 0, total: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while true {
            try Task.checkCancellation()
            let status = archive_read_next_header(reader, &entry)
            if status == ARCHIVE_EOF { break }
            guard status == ARCHIVE_OK, let entry, let rawName = archive_entry_pathname_utf8(entry) else {
                throw JerdError.invalid("The runtime archive has an invalid entry.")
            }
            count += 1
            guard count <= 100_000 else { throw JerdError.invalid("The runtime archive has too many files.") }
            let components = try path(String(cString: rawName))
            if stripRoot {
                if archiveRoot == nil { archiveRoot = components.first }
                guard components.first == archiveRoot else { throw JerdError.invalid("The runtime archive has more than one root.") }
            }
            let name = (stripRoot ? Array(components.dropFirst()) : components).joined(separator: "/")
            let type = archive_entry_filetype(entry)
            guard !name.isEmpty else {
                guard type == 0o040000 else { throw JerdError.invalid("The runtime archive root is not a directory.") }
                continue
            }
            let symlink = archive_entry_symlink_utf8(entry).map { String(cString: $0) }
            let hardlink = archive_entry_hardlink_utf8(entry).map { String(cString: $0) }
            var target: String?
            if let link = symlink ?? hardlink {
                let base = symlink == nil ? [] : Array(components.dropLast())
                let resolved = try resolve(link, relativeTo: base)
                if stripRoot, resolved.first != archiveRoot { throw JerdError.invalid("An archive link leaves its root.") }
                target = (stripRoot ? Array(resolved.dropFirst()) : resolved).joined(separator: "/")
            }
            guard type == 0o100000 || type == 0o040000 || type == 0o120000 || hardlink != nil else {
                throw JerdError.invalid("The runtime archive has an unsupported file type.")
            }
            let size = archive_entry_size(entry)
            guard size >= 0, size <= 512_000_000 else { throw JerdError.invalid("An archive file exceeds its size limit.") }
            total += size
            guard total <= outputLimit else { throw JerdError.invalid("The runtime archive exceeds its size limit.") }
            guard selected(name), type != 0o040000 else { continue }
            let key = name.precomposedStringWithCanonicalMapping.lowercased()
            guard names.insert(key).inserted else { throw JerdError.invalid("The archive contains duplicate file paths.") }
            if let target { links[name] = target; continue }
            guard type == 0o100000 else { throw JerdError.invalid("The runtime archive link is invalid.") }
            let output = destination.appendingPathComponent(name)
            try PrivateFiles.directory(output.deletingLastPathComponent())
            let mode = archive_entry_perm(entry) & 0o111 == 0 ? 0o600 : 0o700
            let descriptor = open(output.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(mode))
            guard descriptor >= 0 else { throw JerdError.invalid("Cannot create an archive file.") }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            var written: Int64 = 0
            do {
                while true {
                    let read = archive_read_data(reader, &buffer, buffer.count)
                    guard read >= 0 else { throw JerdError.invalid("The runtime archive is damaged.") }
                    if read == 0 { break }
                    written += Int64(read)
                    guard written <= size else { throw JerdError.invalid("An archive file exceeds its declared size.") }
                    try handle.write(contentsOf: Data(buffer.prefix(read)))
                    try Task.checkCancellation()
                }
                try handle.close()
            } catch { try? handle.close(); throw error }
            guard written == size else { throw JerdError.invalid("An archive file is incomplete.") }
            files.insert(name)
            fileSizes[name] = written
        }
        for (name, initial) in links {
            try Task.checkCancellation()
            var target = initial, visited: Set<String> = [name]
            while let next = links[target] {
                guard visited.insert(target).inserted else { throw JerdError.invalid("The archive has a link cycle.") }
                target = next
            }
            guard files.contains(target) else { throw JerdError.invalid("An archive link does not refer to an included file.") }
            let size = fileSizes[target]!
            guard size <= outputLimit - total else { throw JerdError.invalid("The runtime archive exceeds its size limit after copying links.") }
            total += size
            let output = destination.appendingPathComponent(name)
            try PrivateFiles.directory(output.deletingLastPathComponent())
            try FileManager.default.copyItem(at: destination.appendingPathComponent(target), to: output)
        }
    }

    private static func path(_ value: String) throws -> [String] {
        guard !value.hasPrefix("/"), !value.contains("\\"), !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw JerdError.invalid("The archive contains an unsafe path.")
        }
        let parts = value.split(separator: "/").map(String.init).filter { $0 != "." }
        guard !parts.isEmpty, !parts.contains("..") else { throw JerdError.invalid("The archive contains an unsafe path.") }
        return parts
    }
    private static func resolve(_ link: String, relativeTo base: [String]) throws -> [String] {
        guard !link.hasPrefix("/"), !link.contains("\\"), !link.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw JerdError.invalid("An archive link is unsafe.")
        }
        var result = base
        for part in link.split(separator: "/") {
            if part == "." { continue }
            if part == ".." {
                guard !result.isEmpty else { throw JerdError.invalid("An archive link leaves its root.") }
                result.removeLast()
            } else { result.append(String(part)) }
        }
        guard !result.isEmpty else { throw JerdError.invalid("An archive link is empty.") }
        return result
    }
}
