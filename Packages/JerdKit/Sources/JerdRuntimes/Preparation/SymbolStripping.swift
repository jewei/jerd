import Foundation
import JerdFoundation
import JerdManifest

/// The pinned rule that removes local symbols from some prepared executables, so the app download
/// is smaller. Nothing that a runtime needs at run time changes.
///
/// `strip -x` removes the local symbols and keeps every global symbol, which dynamic loading and
/// crash reports need. `strip -S` removes only debug symbols, and these builds carry almost none
/// (PHP 8.5 CLI: 3.8 MB less with `-x`, 16 bytes more with `-S`). Each listed file carries an
/// ad-hoc linker signature, which `strip` writes again. Left out: files with a publisher signature
/// that Jerd checks (Postgres.app, MySQL), Caddy (`strip` refuses its symbol table), RustFS (no
/// gain, and `strip` breaks its signature), and the PHP scripts of Composer and Laravel.
package enum SymbolStripping {
    /// When a preparation strips.
    package enum Requirement: Sendable, Equatable {
        /// Always strip, and fail without the tool: `./dev runtimes prepare`, which requires Xcode.
        case required
        /// Strip only when this Mac has a developer folder, so an update in the app never asks for
        /// the Command Line Tools. A build without stripping is still complete and recorded as is.
        case whenDeveloperToolsExist
    }

    package static let strip = URL(fileURLWithPath: "/usr/bin/strip")
    package static let arguments = ["-x"]
    package static let codesign = URL(fileURLWithPath: "/usr/bin/codesign")
    package static let xcodeSelect = URL(fileURLWithPath: "/usr/bin/xcode-select")
    package static let timeout: Duration = .seconds(300)

    /// The executables to strip in a payload of `kind`, relative to the payload. Empty: none.
    package static func executables(for kind: RuntimeKind, version: String) throws -> [RelativePath] {
        let paths: [String]
        switch kind {
        case .php:
            let (cli, fpm) = try PHPPreparer.executables(version: version)
            paths = [cli, fpm]
        case .mailpit: paths = ["mailpit"]
        case .redis: paths = ["bin/redis-server", "bin/redis-cli"]
        case .caddy, .cloudflared, .composer, .laravel, .mysql, .postgresql, .rustfs: paths = []
        }
        return try paths.map { path in
            guard let relative = RelativePath(path) else {
                throw JerdError.invalid("The runtime path \(path) is unsafe.")
            }
            return relative
        }
    }

    /// The message when a stripped file no longer has a valid signature.
    package static func brokenSignature(_ path: RelativePath, kind: RuntimeKind) -> JerdError {
        JerdError.invalid(
            "Removing the symbols of \(kind.title) \(path.string) broke its signature. Jerd installed nothing.")
    }
}
