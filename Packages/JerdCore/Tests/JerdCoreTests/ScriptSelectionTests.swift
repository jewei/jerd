import Foundation
import Testing
@testable import JerdCore

/// Path-info, case, and PHP-like requests against real PHP-FPM and Caddy.
///
/// Every target script joins `TARGET-` and `EXECUTED` at run time, so its source never contains the
/// marker. A response with the marker proves that PHP ran the target.
struct ScriptSelectionTests {
    enum Outcome: Equatable {
        /// The site's `index.php` ran with this `PATH_INFO`, `SCRIPT_NAME=/index.php`, and no `PATH_TRANSLATED`.
        case frontController(pathInfo: String)
        /// This lowercase `.php` file ran.
        case script(String)
        /// 404, and no PHP ran.
        case notFound
    }

    struct Request: CustomStringConvertible {
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

    /// A path-info request never runs the file that its path info names.
    static let requests: [Request] = [
        Request(host: laravel, path: "/index.php/storage/upload.php", outcome: .frontController(pathInfo: "/storage/upload.php")),
        Request(host: laravel, path: "/index.php/storage/shell.PHP", outcome: .frontController(pathInfo: "/storage/shell.PHP")),
        Request(host: laravel, path: "/storage/upload.php", outcome: .notFound),
        Request(host: laravel, path: "/storage/upload.php/x", outcome: .notFound),
        Request(host: laravel, path: "/storage/shell.php", outcome: .notFound),
        Request(host: projectRoot, path: "/index.php/vendor/pkg/run.php", outcome: .frontController(pathInfo: "/vendor/pkg/run.php")),
        Request(host: projectRoot, path: "/vendor/pkg/run.php", outcome: .notFound),
        Request(host: projectRoot, path: "/index.php/.hidden/x.php", outcome: .notFound),
        Request(host: projectRoot, path: "/.hidden/x.php", outcome: .notFound),
        Request(host: projectRoot, path: "/index.php/notes.txt", outcome: .frontController(pathInfo: "/notes.txt")),
        Request(host: projectRoot, path: "/notes.txt/x.php", outcome: .frontController(pathInfo: "")),
        Request(host: projectRoot, path: "/index.php/upper.PHP", outcome: .frontController(pathInfo: "/upper.PHP")),
        Request(host: projectRoot, path: "/index.php/../vendor/pkg/run.php", outcome: .notFound, pathAsIs: true),
        Request(host: projectRoot, path: "/valid.php/../vendor/pkg/run.php", outcome: .notFound, pathAsIs: true),
        // The name on disk decides, also on a case-insensitive volume.
        Request(host: projectRoot, path: "/upper.PHP", outcome: .notFound),
        Request(host: projectRoot, path: "/upper.php", outcome: .notFound),
        Request(host: projectRoot, path: "/UPPER.php", outcome: .notFound),
        Request(host: projectRoot, path: "/mixed.php", outcome: .notFound),
        Request(host: projectRoot, path: "/Valid.php", outcome: .notFound),
        // Glob characters in a request are literal.
        Request(host: projectRoot, path: "/odd%5B1%5D.php", outcome: .script("odd[1].php")),
        Request(host: projectRoot, path: "/odd%5B2%5D.php", outcome: .frontController(pathInfo: "")),
        Request(host: projectRoot, path: "/odd%5B3%5D.php", outcome: .frontController(pathInfo: "")),
        // Other PHP-like extensions are neither run nor served as source.
        Request(host: projectRoot, path: "/script.pht", outcome: .notFound),
        Request(host: projectRoot, path: "/script.phps", outcome: .notFound),
        Request(host: projectRoot, path: "/script.phpt", outcome: .notFound),
        Request(host: projectRoot, path: "/script.php7", outcome: .notFound),
        Request(host: projectRoot, path: "/script.inc", outcome: .notFound),
        // Normal front-controller, script, and static URLs still work.
        Request(host: laravel, path: "/", outcome: .frontController(pathInfo: "")),
        Request(host: laravel, path: "/route", outcome: .frontController(pathInfo: "")),
        Request(host: laravel, path: "/index.php", outcome: .frontController(pathInfo: "")),
        Request(host: laravel, path: "/index.php/route", outcome: .frontController(pathInfo: "/route")),
        Request(host: laravel, path: "/index.php/users/7/edit", outcome: .frontController(pathInfo: "/users/7/edit")),
        Request(host: projectRoot, path: "/valid.php", outcome: .script("valid.php")),
        Request(host: projectRoot, path: "/valid.php/extra", outcome: .script("valid.php")),
        Request(host: projectRoot, path: "/sub/", outcome: .script("sub/index.php"))
    ]

    @Test(.enabled(if: ProcessInfo.processInfo.environment["JERD_INTEGRATION"] == "1",
                   "Select independent PHP and Caddy binaries for the script selection test."))
    func phpRunsOnlyTheScriptThatTheRoutesSelect() async throws {
        let environment = ProcessInfo.processInfo.environment
        let root = try temporaryDirectory(" script selection")
        defer { try? FileManager.default.removeItem(at: root) }
        let sites = try Self.makeSites(in: root)
        let paths = EnginePaths(root: root.appendingPathComponent("engine"),
            socketDirectory: URL(fileURLWithPath: "/tmp/jerd-scripts-\(UUID().uuidString.prefix(12))"))
        let provider = DevelopmentRuntimeProvider()
        let runtime = try await provider.inspectPHP(cli: URL(fileURLWithPath: try #require(environment["JERD_PHP_CLI"])),
            fpm: URL(fileURLWithPath: try #require(environment["JERD_PHP_FPM"])), workDirectory: root)
        let caddy = try await provider.inspectCaddy(binary: URL(fileURLWithPath: try #require(environment["JERD_CADDY"])), workDirectory: root)
        let sockets = try ListeningSockets.bind(httpPort: 0, httpsPort: 0)
        defer { sockets.close() }
        let ports = try sockets.ports()
        let engine = ServingEngine()
        do {
            try await engine.start(sites: sites.map { SiteRuntime(site: $0, runtime: runtime) },
                caddy: caddy, paths: paths, httpsPort: ports.https, httpPort: ports.http, listeningSockets: sockets)
            var report: [String] = []
            for request in Self.requests {
                let output = root.appendingPathComponent("response-\(UUID().uuidString)")
                let result = try await LocalCommandRunner().run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/curl"),
                    arguments: ["--noproxy", "*", "--silent", "--show-error", "--max-time", "4"] + (request.pathAsIs ? ["--path-as-is"] : []) +
                        ["--cacert", paths.rootCertificate.path, "--resolve", "\(request.host):\(ports.https):127.0.0.1",
                         "--output", output.path, "--write-out", "%{http_code}", "https://\(request.host):\(ports.https)\(request.path)"],
                    directory: root), timeout: .seconds(6))
                #expect(result.status == 0, "\(request): \(result.diagnosticOutput)")
                let body = (try? Data(contentsOf: output)) ?? Data()
                report.append("\(request) -> \(result.output) \(String(decoding: body.prefix(120), as: UTF8.self))")
                Self.check(request, code: result.output, body: body)
            }
            print(report.joined(separator: "\n"))
            await engine.stop()
        } catch { await engine.stop(); throw error }
    }

    private static func check(_ request: Request, code: String, body: Data) {
        let text = String(decoding: body, as: UTF8.self)
        switch request.outcome {
        case .notFound:
            #expect(code == "404", "\(request): \(code) \(text)")
            #expect(!text.contains(marker) && !text.contains("<?php"), "\(request): \(text)")
        case .script(let name):
            #expect(code == "200" && text == "\(name)-ran", "\(request): \(code) \(text)")
        case .frontController(let pathInfo):
            let values = (try? JSONSerialization.jsonObject(with: body)) as? [String: String]
            #expect(code == "200", "\(request): \(code) \(text)")
            #expect(values == ["script": "index.php", "pathInfo": pathInfo, "scriptName": "/index.php",
                               "self": "/index.php" + pathInfo, "translated": "unset", "uri": request.path],
                    "\(request): \(text)")
        }
    }

    /// A Laravel-style site (public root and a public storage link) and a project-root site.
    private static func makeSites(in root: URL) throws -> [Site] {
        func write(_ path: String, _ text: String) throws {
            let file = root.appendingPathComponent(path)
            try PrivateFiles.directory(file.deletingLastPathComponent())
            try Data(text.utf8).write(to: file)
        }
        try write("laravel/public/index.php", frontController)
        for name in ["upload.php", "shell.PHP"] { try write("laravel/storage/app/public/\(name)", target) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("laravel/public/storage"),
            withDestinationURL: root.appendingPathComponent("laravel/storage/app/public"))
        try write("root/index.php", frontController)
        for name in ["valid.php", "odd[1].php", "odd3.php", "sub/index.php"] {
            try write("root/\(name)", "<?php echo '\(name)-' . 'ran';")
        }
        for name in ["vendor/pkg/run.php", ".hidden/x.php", "notes.txt", "upper.PHP", "mixed.Php", "script.pht",
                     "script.phps", "script.phpt", "script.php7", "script.inc", "odd[2].PHP"] {
            try write("root/\(name)", target)
        }
        var laravelSite = makeSite(root.appendingPathComponent("laravel"), hostname: laravel)
        laravelSite.documentRoot = root.appendingPathComponent("laravel/public").path
        return [laravelSite, makeSite(root.appendingPathComponent("root"), hostname: projectRoot)]
    }
}
