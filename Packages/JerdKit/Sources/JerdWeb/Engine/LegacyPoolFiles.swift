import Darwin
import Foundation
import JerdFoundation

/// Removes the first-pool files of the old layout, which now lives in `php/<runtime UUID>/`.
///
/// The old app wrote its first pool to `configuration/php-fpm.conf`, `configuration/php.ini`,
/// and `logs/fpm.log` (spec B 7.5). No run reads them now, so they only mislead a person who
/// reads the folder (review web-r1 L6). Call this only while the engine holds the records lock
/// and no recorded process can live. A file is removed only when Jerd provably wrote it: the
/// two configuration files must be private regular files with the old generated text, and the
/// log must be a regular file of this user. Every other item is kept.
enum LegacyPoolFiles {
    /// The old generated files are a few hundred bytes. A larger file is not one of them.
    static let sizeLimit = 65_536

    static func remove(from environment: EnvironmentLayout) throws {
        if isGenerated(environment.fpmConfigurationFile, isGeneratedPool) {
            try AtomicFile.remove(environment.fpmConfigurationFile)
        }
        if isGenerated(environment.phpINIFile, isGeneratedINI) {
            try AtomicFile.remove(environment.phpINIFile)
        }
        if isOwnRegularFile(environment.fpmLogFile) {
            try AtomicFile.remove(environment.fpmLogFile)
        }
    }

    /// The old pool file begins like every pool file that Jerd renders.
    static func isGeneratedPool(_ text: String) -> Bool {
        text.hasPrefix("[global]\ndaemonize = no\n") && text.contains("\n[jerd]\nlisten = ")
            && text.contains("\nping.path = \(FPMPoolRenderer.pingPath)\n")
    }

    /// The old FPM `php.ini` is the shared section, then the FPM limits, and an optional trust section.
    static func isGeneratedINI(_ text: String) -> Bool {
        text.hasPrefix(PHPIniPolicy.common + "memory_limit = 256M\nupload_max_filesize = 32M\n")
    }

    /// An unreadable, foreign, or unexpected file is kept, which is the safe direction.
    private static func isGenerated(_ file: URL, _ rule: (String) -> Bool) -> Bool {
        guard FileProbe.presence(at: file) == .present,
            let data = try? AtomicFile.read(file, limit: sizeLimit)
        else { return false }
        return rule(String(decoding: data, as: UTF8.self))
    }

    private static func isOwnRegularFile(_ file: URL) -> Bool {
        var info = stat()
        guard lstat(file.path, &info) == 0 else { return false }
        return info.st_mode & S_IFMT == S_IFREG && info.st_uid == geteuid()
    }
}
