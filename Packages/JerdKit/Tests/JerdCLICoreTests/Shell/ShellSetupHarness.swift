import Foundation
import JerdFoundation
import JerdWeb

@testable import JerdCLICore

/// A temporary home with a complete Jerd installation for the shell setup. Never the real home.
struct ShellSetupHarness {
    static let original = Data("# User settings\nexport EDITOR=vi\n".utf8)
    static let launcherBytes = Data("test launcher".utf8)

    let fixture: CLIFixture
    let php: DevelopmentRuntime
    let launcher: URL

    init(zshrc: Data? = original) throws {
        fixture = try CLIFixture()
        php = try fixture.installPHP("8.5")
        try fixture.saveDefault(php)
        try fixture.installCompanions()
        launcher = try fixture.directory.file("Jerd.app/Contents/MacOS/JerdCLI", Self.launcherBytes, mode: 0o755)
        if let zshrc { try fixture.directory.file("home/.zshrc", zshrc, mode: 0o644) }
    }

    var home: URL { fixture.home }
    var layout: DataLayout { fixture.layout }
    var zshrc: URL { home.appendingPathComponent(".zshrc") }
    var zprofile: URL { home.appendingPathComponent(".zprofile") }
    var bin: URL { layout.binDirectory }

    func remove() { fixture.remove() }

    func installer(
        signatures: FakeSignatureCheck = FakeSignatureCheck(),
        at date: Date = Date(timeIntervalSince1970: 1_772_600_767)
    ) -> ShellSetupInstaller {
        ShellSetupInstaller(
            layout: layout, home: home, launcher: launcher, signatures: signatures, now: { date },
            timeZone: TimeZone(identifier: "UTC") ?? .current)
    }

    /// Every item below the home folder (paths relative to it), to prove that nothing changed.
    func snapshot() -> [String: Data] {
        var items: [String: Data] = [:]
        let base = home.path
        guard let walker = FileManager.default.enumerator(atPath: base) else { return items }
        while let relative = walker.nextObject() as? String {
            let url = home.appendingPathComponent(relative)
            if let target = linkText(url) {
                items[relative] = Data("link:\(target)".utf8)
            } else {
                items[relative] = contents(url) ?? Data("folder".utf8)
            }
        }
        return items
    }
}
