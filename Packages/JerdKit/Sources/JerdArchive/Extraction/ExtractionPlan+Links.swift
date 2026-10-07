import JerdFoundation

extension ExtractionPlan {
    /// Resolves each recorded link to its final extracted file, within the output budget.
    /// Call it once, after every entry is admitted and every file is written.
    package mutating func linkCopies() throws -> [LinkCopy] {
        var copies: [LinkCopy] = []
        for path in links.keys.sorted() {
            try Task.checkCancellation()
            let source = try finalTarget(of: path)
            guard let size = fileSizes[source] else { throw ArchiveFailure.linkTargetMissing }
            guard size <= policy.outputLimit - outputBytes else { throw ArchiveFailure.outputTooLargeAfterLinks }
            outputBytes += size
            copies.append(LinkCopy(path: path, source: source))
        }
        return copies
    }

    /// The target components of a link entry after root stripping, or nil when the entry is not a link.
    ///
    /// A symbolic link resolves from its own folder, a hard link from the archive top. The target
    /// must stay inside the archive (and inside the root when the root is stripped).
    func linkTarget(of header: ArchiveEntryHeader, stored: RelativePath) throws -> [String]? {
        let link: String
        let base: [String]
        if header.type == .symbolicLink {
            link = header.symlinkTarget ?? ""
            base = Array(stored.components.dropLast())
        } else if let hardlink = header.hardlinkTarget {
            link = hardlink
            base = []
        } else {
            return nil
        }
        // A link without a target gets its own message.
        guard !link.isEmpty else { throw ArchiveFailure.emptyLink }
        let resolved = try Self.resolve(link, from: base)
        guard policy.stripsRoot else { return resolved }
        guard resolved.first == root else { throw ArchiveFailure.linkLeavesRoot }
        return Array(resolved.dropFirst())
    }

    /// Resolves `link` lexically against `base`. `..` may not climb above the archive top.
    static func resolve(_ link: String, from base: [String]) throws -> [String] {
        guard !link.hasPrefix("/"), !link.contains("\\"),
            !link.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { throw ArchiveFailure.unsafeLink }
        var result = base
        for part in link.split(separator: "/") where part != "." {
            if part == ".." {
                guard !result.isEmpty else { throw ArchiveFailure.linkLeavesRoot }
                result.removeLast()
            } else {
                result.append(String(part))
            }
        }
        guard !result.isEmpty else { throw ArchiveFailure.emptyLink }
        return result
    }

    private func finalTarget(of path: RelativePath) throws -> RelativePath {
        var visited: Set<RelativePath> = [path]
        var target = links[path] ?? path
        while let next = links[target] {
            guard visited.insert(target).inserted else { throw ArchiveFailure.linkCycle }
            target = next
        }
        return target
    }
}
