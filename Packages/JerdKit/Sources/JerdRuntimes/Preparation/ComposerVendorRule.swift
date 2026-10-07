import Foundation

/// The files of a Composer `vendor/` folder that the Laravel installer never reads at run time.
///
/// Composer dist archives already leave out most tests, but they keep documentation, changelogs,
/// repository settings, test helpers, Windows programs, and every Carbon translation. The rule
/// looks only at the files of a package (`vendor/<vendor>/<package>/…`), never at Composer's own
/// `vendor/composer` and `vendor/bin`. A license or notice file always stays, at any depth, so the
/// payload keeps every license text that the packages ship.
package enum ComposerVendorRule {
    /// Folders directly inside a package that hold documentation, examples, CI settings, or tests.
    package static let leftOutPackageFolders: Set<String> = [
        ".github", ".gitlab", "doc", "docs", "example", "examples", "test", "tests",
    ]
    /// Name starts of documentation files directly inside a package.
    package static let documentationNames = [
        "changelog", "changes", "code_of_conduct", "contributing", "readme", "security", "upgrade",
    ]
    /// Extensions of documentation files; a PHP class such as `Security.php` never matches.
    package static let documentationExtensions: Set<String> = ["", "markdown", "md", "rst", "txt"]
    /// Static-analysis and test settings, and maintainer scripts, directly inside a package.
    package static let developmentFiles: Set<String> = [
        "phpstan.neon", "phpstan.neon.dist", "phpunit.xml", "phpunit.xml.dist", "psalm.xml", "psalm.xml.dist",
        "release.sh",
    ]
    /// Programs that only Windows runs. Jerd runs on macOS only.
    package static let windowsExtensions: Set<String> = ["bat", "cmd", "exe"]
    /// Name starts of files that always stay.
    package static let licenseNames = ["copying", "copyright", "licence", "license", "notice"]
    /// Carbon's translations. The installer never sets a Carbon locale, so only English stays.
    package static let carbonTranslationFolder = ["nesbot", "carbon", "src", "Carbon", "Lang"]
    package static let carbonKeptTranslation = "en.php"

    /// Whether the file at `components`, relative to `vendor/`, is left out of the payload.
    package static func isLeftOut(_ components: [String]) -> Bool {
        guard components.count >= 3, components[0] != "composer", components[0] != "bin",
            let name = components.last
        else { return false }
        let lowercased = name.lowercased()
        let pathExtension = (lowercased as NSString).pathExtension
        if licenseNames.contains(where: lowercased.hasPrefix) { return false }
        if windowsExtensions.contains(pathExtension) || isCarbonTranslation(components) { return true }
        if components.count > 3 { return leftOutPackageFolders.contains(components[2].lowercased()) }
        if lowercased.hasPrefix(".") || pathExtension == "neon" || developmentFiles.contains(lowercased) {
            return true
        }
        let stem = (lowercased as NSString).deletingPathExtension
        return documentationExtensions.contains(pathExtension)
            && documentationNames.contains { stem == $0 || stem.hasPrefix($0 + "-") || stem.hasPrefix($0 + "_") }
    }

    private static func isCarbonTranslation(_ components: [String]) -> Bool {
        components.count == carbonTranslationFolder.count + 1
            && Array(components.dropLast()) == carbonTranslationFolder
            && components.last != carbonKeptTranslation
    }
}
