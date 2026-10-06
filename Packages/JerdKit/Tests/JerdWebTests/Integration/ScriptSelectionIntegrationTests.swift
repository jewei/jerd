import Foundation
import JerdFoundation
import JerdProcess
import JerdTestSupport
import Testing

@testable import JerdWeb

/// Requests that try to run a script other than the routed one, against real PHP-FPM and Caddy.
///
/// Every target script prints `TARGET-` and `EXECUTED` joined at run time, so its source text never
/// contains the marker. A response that contains the marker proves that PHP ran the target.
@Suite(.enabled(if: IntegrationRun.enabled, "Set JERD_INTEGRATION=1 and select PHP CLI, PHP-FPM, and Caddy."))
struct ScriptSelectionIntegrationTests {
    /// What one request must produce.
    enum Outcome: Equatable {
        /// The site's `index.php` ran with this `PATH_INFO`, `SCRIPT_NAME=/index.php`, and no
        /// `PATH_TRANSLATED`.
        case frontController(pathInfo: String)
        /// This lowercase `.php` file ran (a normal script).
        case script(String)
        /// 404, and no PHP ran.
        case notFound
    }

    struct Attack: CustomStringConvertible {
        let host: String
        let path: String
        let outcome: Outcome
        var pathAsIs = false

        var description: String { "\(host)\(path)" }
    }

    static let laravel = "laravel-scripts.test"
    static let projectRoot = "root-scripts.test"
    static let marker = "TARGET-EXECUTED"
    static let target = "<?php echo 'TARGET-' . 'EXECUTED';"
    static let frontController = """
        <?php
        header('Content-Type: application/json');
        echo json_encode([
            'script' => basename(__FILE__), 'pathInfo' => $_SERVER['PATH_INFO'] ?? '',
            'scriptName' => $_SERVER['SCRIPT_NAME'] ?? '', 'self' => $_SERVER['PHP_SELF'] ?? '',
            'translated' => $_SERVER['PATH_TRANSLATED'] ?? 'unset', 'uri' => $_SERVER['REQUEST_URI'] ?? '',
        ]);
        """

    /// The requests and their outcomes. A path-info request never runs the file it names.
    static let attacks: [Attack] = [
        // Path info into public storage (uploads) and into private folders.
        Attack(
            host: laravel, path: "/index.php/storage/upload.php",
            outcome: .frontController(pathInfo: "/storage/upload.php")),
        Attack(
            host: laravel, path: "/index.php/storage/shell.PHP",
            outcome: .frontController(pathInfo: "/storage/shell.PHP")),
        Attack(host: laravel, path: "/storage/upload.php", outcome: .notFound),
        Attack(host: laravel, path: "/storage/upload.php/x", outcome: .notFound),
        Attack(host: laravel, path: "/storage/shell.php", outcome: .notFound),
        Attack(
            host: projectRoot, path: "/index.php/vendor/pkg/run.php",
            outcome: .frontController(pathInfo: "/vendor/pkg/run.php")),
        Attack(host: projectRoot, path: "/vendor/pkg/run.php", outcome: .notFound),
        Attack(host: projectRoot, path: "/index.php/.hidden/x.php", outcome: .notFound),
        Attack(host: projectRoot, path: "/.hidden/x.php", outcome: .notFound),
        Attack(host: projectRoot, path: "/index.php/notes.txt", outcome: .frontController(pathInfo: "/notes.txt")),
        Attack(host: projectRoot, path: "/notes.txt/x.php", outcome: .frontController(pathInfo: "")),
        Attack(host: projectRoot, path: "/index.php/upper.PHP", outcome: .frontController(pathInfo: "/upper.PHP")),
        Attack(host: projectRoot, path: "/index.php/../vendor/pkg/run.php", outcome: .notFound, pathAsIs: true),
        Attack(host: projectRoot, path: "/valid.php/../vendor/pkg/run.php", outcome: .notFound, pathAsIs: true),
        // The on-disk name decides, also on a case-insensitive volume.
        Attack(host: projectRoot, path: "/upper.PHP", outcome: .notFound),
        Attack(host: projectRoot, path: "/upper.php", outcome: .notFound),
        Attack(host: projectRoot, path: "/UPPER.php", outcome: .notFound),
        Attack(host: projectRoot, path: "/mixed.php", outcome: .notFound),
        Attack(host: projectRoot, path: "/Valid.php", outcome: .notFound),
        // Glob characters in a request are literal: `odd[3].php` never selects `odd3.php`, and
        // `odd[2].php` never selects `odd[2].PHP`. A name that does not exist goes to the front controller.
        Attack(host: projectRoot, path: "/odd%5B1%5D.php", outcome: .script("odd[1].php")),
        Attack(host: projectRoot, path: "/odd%5B2%5D.php", outcome: .frontController(pathInfo: "")),
        Attack(host: projectRoot, path: "/odd%5B3%5D.php", outcome: .frontController(pathInfo: "")),
        // Other PHP-like extensions are neither run nor served as source.
        Attack(host: projectRoot, path: "/script.pht", outcome: .notFound),
        Attack(host: projectRoot, path: "/script.phps", outcome: .notFound),
        Attack(host: projectRoot, path: "/script.phpt", outcome: .notFound),
        Attack(host: projectRoot, path: "/script.php7", outcome: .notFound),
        Attack(host: projectRoot, path: "/.well-known/script.pht", outcome: .notFound),
        // Normal front-controller and script URLs still work.
        Attack(host: laravel, path: "/", outcome: .frontController(pathInfo: "")),
        Attack(host: laravel, path: "/route", outcome: .frontController(pathInfo: "")),
        Attack(host: laravel, path: "/index.php", outcome: .frontController(pathInfo: "")),
        Attack(host: laravel, path: "/index.php/route", outcome: .frontController(pathInfo: "/route")),
        Attack(host: laravel, path: "/index.php/users/7/edit", outcome: .frontController(pathInfo: "/users/7/edit")),
        Attack(host: projectRoot, path: "/valid.php", outcome: .script("valid.php")),
        Attack(host: projectRoot, path: "/valid.php/extra", outcome: .script("valid.php")),
    ]

    @Test func phpRunsOnlyTheScriptThatTheRoutesSelect() async throws {
        let folder = try TemporaryDirectory(" script selection")
        defer { folder.remove() }
        let sites = try Self.makeSites(in: folder)
        let runtime = try await IntegrationRun.runtime(in: folder)
        let plan = ServingPlan(
            sites: sites.map { PlannedSite(site: $0, runtime: runtime) },
            caddy: try await IntegrationRun.caddy(in: folder))
        let layout = IntegrationRun.layout(in: folder)
        let listeners = try TestListeners()
        defer { listeners.close() }
        let engine = EngineRunner()
        _ = try await engine.start(
            plan, layout: layout,
            binding: ListenerBinding(httpsPort: listeners.httpsPort, httpPort: listeners.httpPort, inherited: true),
            listeners: listeners.inherited)
        var report: [String] = []
        for attack in Self.attacks {
            let extra = attack.pathAsIs ? ["--path-as-is"] : []
            let response = try await IntegrationRun.request(
                attack.host, attack.path, port: listeners.httpsPort, layout: layout, extra: extra)
            report.append("\(attack) -> \(response.code) \(String(decoding: response.body.prefix(100), as: UTF8.self))")
            Self.check(attack, response)
        }
        await engine.stop()
        print(report.joined(separator: "\n"))
    }

    private static func check(_ attack: Attack, _ response: (code: String, body: Data)) {
        let text = String(decoding: response.body, as: UTF8.self)
        switch attack.outcome {
        case .notFound:
            #expect(response.code.hasPrefix("404 "), "\(attack): \(response.code) \(text)")
            #expect(!text.contains(marker) && !text.contains("<?php"), "\(attack): \(text)")
        case .script(let name):
            #expect(response.code.hasPrefix("200 ") && text == "\(name)-ran", "\(attack): \(response.code) \(text)")
        case .frontController(let pathInfo):
            let body = (try? JSONSerialization.jsonObject(with: response.body)) as? [String: String]
            #expect(response.code.hasPrefix("200 "), "\(attack): \(response.code) \(text)")
            let expected = [
                "script": "index.php", "pathInfo": pathInfo, "scriptName": "/index.php",
                "self": "/index.php" + pathInfo,
                "translated": "unset", "uri": attack.path,
            ]
            #expect(body == expected, "\(attack): \(text)")
        }
    }

    /// A Laravel-style site (public root and a public storage link) and a project-root site.
    private static func makeSites(in folder: TemporaryDirectory) throws -> [Site] {
        try folder.file("laravel/public/index.php", frontController)
        for name in ["upload.php", "shell.PHP"] { try folder.file("laravel/storage/app/public/\(name)", target) }
        try FileManager.default.createSymbolicLink(
            at: folder.path("laravel/public/storage"), withDestinationURL: folder.path("laravel/storage/app/public"))
        try folder.file("root/index.php", frontController)
        try folder.file("root/valid.php", "<?php echo 'valid.php-' . 'ran';")
        try folder.file("root/odd[1].php", "<?php echo 'odd[1].php-' . 'ran';")
        try folder.file("root/odd3.php", "<?php echo 'odd3.php-' . 'ran';")
        for name in [
            "vendor/pkg/run.php", ".hidden/x.php", "notes.txt", "upper.PHP", "mixed.Php", "script.pht", "script.phps",
            "script.phpt", "script.php7", ".well-known/script.pht", "odd[2].PHP",
        ] {
            try folder.file("root/\(name)", target)
        }
        return [
            Samples.site(folder.path("laravel"), hostname: laravel, documentRoot: folder.path("laravel/public")),
            Samples.site(folder.path("root"), hostname: projectRoot),
        ]
    }
}
