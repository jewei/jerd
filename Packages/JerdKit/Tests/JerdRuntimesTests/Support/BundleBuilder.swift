import Darwin
import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes

/// Writes a `RuntimePayloads` folder as the build would: a catalog and one receipt per payload.
struct BundleBuilder {
    /// One payload file: its text and whether it is executable.
    struct File {
        let path: String
        let text: String
        var executable = false
    }

    let root: URL
    var architecture = CPUArchitecture.arm64
    private(set) var pins: [RuntimePin] = []
    private(set) var supportSources: [String: PinnedSupportSource] = [:]

    init(root: URL) { self.root = root }

    /// Adds a payload. The first executable file is the receipt executable.
    mutating func add(
        _ kind: RuntimeKind, id: String, version: String, reportedVersion: String? = nil, files: [File],
        secondary: String? = nil, embedded: Bool? = nil
    ) throws {
        let page = try URL.runtime("https://github.com/example/releases")
        let pin: RuntimePin
        if kind == .laravel {
            let project = PinnedComposerProject(directory: try path("laravel-installer"), lockSHA256: digest("c"))
            pin = RuntimePin(
                id: id, kind: kind, version: version, archive: nil, composerProject: project, releasePage: page)
        } else {
            let archive = PinnedArchive(
                url: try .runtime("https://github.com/example/\(id).tar.gz"), size: 10, sha256: digest("c"))
            let signature =
                kind == .mysql
                ? PinnedFile(url: try .runtime("https://cdn.mysql.com/\(id).asc"), sizeLimit: 900, sha256: digest("d"))
                : nil
            pin = RuntimePin(
                id: id, kind: kind, version: version, archive: archive, signature: signature, releasePage: page,
                embedded: embedded)
        }
        pins.append(pin)
        let folder = root.appendingPathComponent(pin.group?.rawValue ?? "none").appendingPathComponent(id)
        var records: [RelativePath: PayloadFileRecord] = [:]
        for file in files {
            let url = folder.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(file.text.utf8).write(to: url)
            chmod(url.path, file.executable ? 0o755 : 0o644)
            records[try path(file.path)] = PayloadFileRecord(
                sha256: FileDigest.hexSHA256(of: Data(file.text.utf8)), executable: file.executable)
        }
        let executable = try path(files.first(where: \.executable)?.path ?? files[0].path)
        let receipt = PayloadReceipt(
            id: id, kind: kind, version: reportedVersion ?? version, releaseVersion: version,
            architecture: architecture,
            archiveSHA256: digest("c"), executable: executable, secondaryExecutable: try secondary.map(path),
            files: records)
        try receipt.encoded().write(to: folder.appendingPathComponent(PayloadReceipt.fileName))
    }

    /// Adds the XZ support source to the catalog and its folder `support/xz` with a receipt, as the
    /// build embeds it. `recorded` overrides digests in the receipt.
    mutating func addXZ(
        version: String = "5.8.4", files: [String: String] = ["liblzma.5.dylib": "lzma", "XZ-LICENSE.txt": "0BSD"],
        recorded: [String: String] = [:]
    ) throws {
        let archive = PinnedArchive(
            url: try .runtime("https://github.com/tukaani-project/xz/xz-\(version).tar.gz"), size: 10,
            sha256: digest("e"))
        supportSources["xz"] = PinnedSupportSource(version: version, archive: archive)
        let folder = BundledSupportLibrary.folder("xz", in: root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var digests: [String: String] = [:]
        for (name, text) in files {
            try Data(text.utf8).write(to: folder.appendingPathComponent(name))
            digests[name] = recorded[name] ?? FileDigest.hexSHA256(of: Data(text.utf8))
        }
        let receipt = SupportReceipt(
            name: "xz", version: version, archiveSHA256: digest("e"), deploymentTarget: "14.0", files: digests)
        try receipt.encoded().write(to: folder.appendingPathComponent(SupportReceipt.fileName))
    }

    func writeCatalog() throws {
        let catalog = RuntimePinCatalog(architecture: architecture, pins: pins, supportSources: supportSources)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(catalog).write(to: root.appendingPathComponent(RuntimePinCatalog.fileName))
    }

    /// The four development payloads with small files.
    mutating func addDevelopment(phpVersion: String = "8.6.1", phpExtras: [File] = []) throws {
        let branch = RuntimeVersion(phpVersion)?.prefix(2) ?? "8.6"
        try add(
            .php, id: "php-\(phpVersion)-arm64", version: phpVersion,
            files: [
                File(path: "php-native-\(branch)", text: "cli", executable: true),
                File(path: "php-native-fpm-\(branch)", text: "fpm", executable: true),
            ] + phpExtras, secondary: "php-native-fpm-\(branch)")
        try add(
            .caddy, id: "caddy-2.11.4-arm64", version: "2.11.4",
            files: [File(path: "caddy", text: "c", executable: true)])
        try add(.composer, id: "composer-2.10.3", version: "2.10.3", files: [File(path: "composer.phar", text: "phar")])
        try add(
            .laravel, id: "laravel-installer-5.32.0", version: "5.32.0",
            files: [File(path: "vendor/laravel/installer/bin/laravel", text: "laravel")])
    }

    private func path(_ text: String) throws -> RelativePath {
        guard let path = RelativePath(text) else { throw JerdError.invalid("Bad test path \(text).") }
        return path
    }
}
