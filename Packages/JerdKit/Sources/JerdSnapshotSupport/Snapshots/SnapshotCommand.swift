import Foundation

/// The `jerd-snapshots` command: parses options, then lists or renders catalog entries.
///
/// A run renders the light and dark variants in this process. Increase Contrast is a process
/// setting that AppKit reads at start, so the command renders the contrast variants in a
/// second process (`--contrast-pass`) that starts with Increase Contrast on.
@MainActor
package struct SnapshotCommand {
    private let catalog: SnapshotCatalog
    private let host: any SnapshotHosting

    package init(catalog: SnapshotCatalog, host: any SnapshotHosting = SnapshotProcessHost()) {
        self.catalog = catalog
        self.host = host
    }

    /// Runs the command and returns the process exit status.
    package func run(arguments: [String]) async -> Int32 {
        await status(arguments: arguments).rawValue
    }

    private func status(arguments: [String]) async -> SnapshotExitStatus {
        let options: SnapshotOptions
        do {
            options = try SnapshotOptions.parse(arguments)
        } catch {
            host.writeError("\(error)\n\(SnapshotOptions.usage)")
            return .usage
        }
        if options.showHelp {
            host.write(SnapshotOptions.usage)
            return .success
        }
        if let problem = catalogProblem(filters: options.filters) {
            host.writeError(problem.message)
            return problem.status
        }
        let entries = catalog.entries(matching: options.filters)
        if options.listOnly {
            list(entries)
            return .success
        }
        host.prepareProcess(contrast: options.contrast)
        return await render(entries, options: options)
    }

    private func catalogProblem(filters: [String]) -> (message: String, status: SnapshotExitStatus)? {
        let duplicates = catalog.duplicateNames
        if !duplicates.isEmpty {
            return ("Snapshot names are used more than once: \(duplicates.joined(separator: ", ")).", .failure)
        }
        let unmatched = catalog.unmatchedFilters(filters)
        if !unmatched.isEmpty {
            return ("No snapshot matches \(unmatched.joined(separator: ", ")). Use --list to see the names.", .usage)
        }
        return nil
    }

    private func list(_ entries: [SnapshotEntry]) {
        for entry in entries {
            host.write("\(entry.name)\t\(entry.sizes.map(\.listDescription).joined(separator: ", "))")
        }
    }

    private func render(_ entries: [SnapshotEntry], options: SnapshotOptions) async -> SnapshotExitStatus {
        let folder = SnapshotOutputFolder(url: URL(fileURLWithPath: options.output))
        let renderer = SnapshotRenderer()
        var count = 0
        do {
            try folder.create()
            for entry in entries {
                for rendering in try await renderer.renderings(of: entry, contrast: options.contrast) {
                    try folder.write(rendering)
                    count += 1
                }
            }
        } catch {
            host.writeError("Snapshots failed: \(error)")
            return .failure
        }
        let kind = options.contrast == .increased ? "Increase Contrast snapshots" : "snapshots"
        host.write("Rendered \(count) \(kind) in \(folder.url.path(percentEncoded: false))")
        guard options.contrast == .standard else { return .success }
        return finishStandardPass(entries, options: options, folder: folder)
    }

    /// Starts the contrast pass when an entry needs it, then removes stale files after a full run.
    private func finishStandardPass(
        _ entries: [SnapshotEntry], options: SnapshotOptions, folder: SnapshotOutputFolder
    ) -> SnapshotExitStatus {
        let contrastNames = entries.filter { entry in entry.appearances.contains { $0.contrast == .increased } }
            .map(\.name)
        if !contrastNames.isEmpty {
            let arguments = ["--contrast-pass", "--output", options.output] + contrastNames
            let status = host.runContrastPass(arguments: arguments)
            guard status == 0 else {
                host.writeError("The Increase Contrast pass failed with exit status \(status).")
                return .failure
            }
        }
        guard options.filters.isEmpty else { return .success }
        do {
            let removed = try folder.removeStalePNGs(keeping: catalog.fileNames)
            if !removed.isEmpty {
                host.write("Removed \(removed.count) stale snapshots: \(removed.joined(separator: ", "))")
            }
        } catch {
            host.writeError("Stale snapshots could not be removed: \(error)")
            return .failure
        }
        return .success
    }
}
