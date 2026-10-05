import AppKit
import JerdDesign

/// The `jerd-snapshots` command: parses options, then lists or renders catalog entries.
@MainActor
struct SnapshotCommand {
    let catalog: SnapshotCatalog

    /// Runs the command and returns the process exit status.
    func run(arguments: [String]) -> Int32 {
        let options: SnapshotOptions
        do {
            options = try SnapshotOptions.parse(arguments)
        } catch {
            printError("\(error)\n\(SnapshotOptions.usage)")
            return 64
        }
        if options.showHelp {
            print(SnapshotOptions.usage)
            return 0
        }
        if let problem = catalogProblem(filters: options.filters) {
            printError(problem)
            return 1
        }
        let entries = catalog.entries(matching: options.filters)
        if options.listOnly {
            list(entries)
            return 0
        }
        return render(entries, to: URL(fileURLWithPath: options.output, isDirectory: true))
    }

    private func catalogProblem(filters: [String]) -> String? {
        let duplicates = catalog.duplicateNames
        if !duplicates.isEmpty {
            return "Snapshot names are used more than once: \(duplicates.joined(separator: ", "))."
        }
        let unmatched = catalog.unmatchedFilters(filters)
        if !unmatched.isEmpty {
            return "No snapshot matches \(unmatched.joined(separator: ", ")). Use --list to see the names."
        }
        return nil
    }

    private func list(_ entries: [SnapshotEntry]) {
        for entry in entries {
            let sizes = entry.sizes.map { "\($0.name) \(Int($0.width))×\(Int($0.height))" }
            print("\(entry.name)\t\(sizes.joined(separator: ", "))")
        }
    }

    private func render(_ entries: [SnapshotEntry], to output: URL) -> Int32 {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let renderer = SnapshotRenderer()
        var count = 0
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for entry in entries {
                for rendering in try renderer.renderings(of: entry) {
                    try rendering.pngData.write(to: output.appending(path: rendering.fileName), options: .atomic)
                    count += 1
                }
            }
        } catch {
            printError("Snapshots failed: \(error)")
            return 1
        }
        print("Rendered \(count) snapshots in \(output.path(percentEncoded: false))")
        return 0
    }

    private func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
