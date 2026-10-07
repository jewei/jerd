import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import Testing

@Suite struct ComposerVendorRuleTests {
    @Test(arguments: [
        // Documentation, changelogs, and repository settings at the package root.
        "symfony/console/README.md", "symfony/console/CHANGELOG.md", "nesbot/carbon/readme.md",
        "nesbot/carbon/SECURITY.md", "laravel/framework/UPGRADE-11.0.md", "psr/container/.gitignore",
        "nesbot/carbon/.phpstorm.meta.php",
        "psr/simple-cache/.editorconfig", "voku/portable-ascii/.deepsource.toml", "nesbot/carbon/extension.neon",
        "vendor/package/phpunit.xml.dist", "laravel/installer/release.sh", "vendor/package/CONTRIBUTING",
        // Folders of documentation, CI, examples, and tests, at the package root.
        "doctrine/inflector/docs/en/index.rst", "vendor/package/.github/workflows/ci.yml",
        "vendor/package/tests/ExampleTest.php", "symfony/translation/Test/ProviderTestCase.php",
        "vendor/package/examples/demo.php",
        // Windows programs, and Carbon translations other than English.
        "symfony/console/Resources/bin/hiddeninput.exe", "nesbot/carbon/bin/carbon.bat",
        "nesbot/carbon/src/Carbon/Lang/de.php", "nesbot/carbon/src/Carbon/Lang/en_US.php",
    ])
    func leavesOutFilesThatTheInstallerNeverReads(_ path: String) {
        #expect(ComposerVendorRule.isLeftOut(path.split(separator: "/").map(String.init)))
    }

    @Test(arguments: [
        // License and notice files stay at any depth, also inside a left-out folder.
        "symfony/console/LICENSE", "laravel/installer/LICENSE.md", "voku/portable-ascii/LICENSE.txt",
        "vendor/package/docs/LICENSE", "vendor/package/NOTICE", "vendor/package/COPYING",
        // Code and run-time data.
        "laravel/installer/src/NewCommand.php", "laravel/installer/bin/laravel", "laravel/installer/composer.json",
        "symfony/console/Resources/completion.bash", "symfony/translation/Resources/schemas/xml.xsd",
        "symfony/security-core/Security.php", "illuminate/support/Testing/Fakes/Fake.php",
        "symfony/console/Tester/CommandTester.php", "vendor/package/src/Tests/Rule.php",
        "nesbot/carbon/src/Carbon/Lang/en.php", "nesbot/carbon/src/Carbon/Carbon.php",
        "voku/portable-ascii/src/voku/helper/data/ascii_by_languages.php",
        // Composer's own files are never touched.
        "composer/installed.json", "composer/LICENSE", "bin/laravel", "bin/README.md", "autoload.php",
    ])
    func keepsLicensesCodeAndComposerFiles(_ path: String) {
        #expect(!ComposerVendorRule.isLeftOut(path.split(separator: "/").map(String.init)))
    }

    @Test func prunerRemovesLeftOutFilesAndTheFoldersThatBecomeEmpty() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        for file in [
            "vendor/autoload.php", "vendor/a/b/README.md", "vendor/a/b/LICENSE", "vendor/a/b/src/Code.php",
            "vendor/a/b/docs/guide.md", "vendor/a/b/docs/LICENSE", "vendor/a/b/tests/unit/BTest.php",
            "vendor/composer/README.md",
        ] {
            try folder.write("x", to: file)
        }
        let removed = try ComposerVendorPruner.prune(vendor: folder.path("vendor"))
        #expect(removed == 3)
        let remaining = try PayloadScanner.scan(folder.url).keys.map(\.description).sorted()
        #expect(
            remaining == [
                "vendor/a/b/LICENSE", "vendor/a/b/docs/LICENSE", "vendor/a/b/src/Code.php", "vendor/autoload.php",
                "vendor/composer/README.md",
            ])
        #expect(FileProbe.presence(at: folder.path("vendor/a/b/tests")) == .absent)
    }

    @Test func prunerIgnoresAMissingVendorFolder() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        #expect(try ComposerVendorPruner.prune(vendor: folder.path("vendor")) == 0)
    }
}
