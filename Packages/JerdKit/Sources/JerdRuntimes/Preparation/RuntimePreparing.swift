import Foundation
import JerdArchive
import JerdFoundation
import JerdManifest

/// Turns a verified artifact into the files of one runtime kind, inside `context.payload`.
package protocol RuntimePreparing: Sendable {
    func prepare(_ context: PreparationContext) async throws
}

/// The one preparer of each kind, shared by managed updates and the build of bundled payloads.
package enum RuntimePreparers {
    package static func preparer(for kind: RuntimeKind) -> any RuntimePreparing {
        switch kind {
        case .php: PHPPreparer()
        case .caddy, .mailpit, .cloudflared, .rustfs: SingleBinaryPreparer()
        case .composer: ComposerPharPreparer()
        case .laravel: LaravelComposerResolver()
        case .mysql: MySQLTarPreparer()
        case .postgresql: PostgresAppPreparer()
        case .redis: RedisSourceBuilder()
        }
    }

    /// Extracts with `policy` off the cooperative pool.
    package static func extract(_ archive: URL, to destination: URL, policy: ExtractionPolicy) async throws {
        _ = try await BlockingWork.run { try ArchiveExtractor.extract(archive, to: destination, policy: policy) }
    }

    /// Requires `names` to exist as regular files in `folder`, so a changed archive layout fails clearly.
    package static func requireFiles(_ names: [String], in folder: URL, kind: RuntimeKind) throws {
        for name in names {
            var info = stat()
            guard lstat(folder.appendingPathComponent(name).path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
                throw JerdError.invalid("The \(kind.title) package does not contain \(name).")
            }
        }
    }
}
