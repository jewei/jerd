import Foundation
import JerdFoundation
import JerdManifest

/// Rules R1–R5: which releases Jerd may install on a Mac. Pure; one candidate at a time.
public struct ReleasePolicy: Sendable {
    /// The largest archive that a release may name.
    public static let archiveLimit: Int64 = 800_000_000
    /// The kinds whose publisher signature Jerd can verify with a pinned key.
    public static let signedKinds: Set<RuntimeKind> = [.mysql]

    public let platform: HostPlatform
    public let allowlist: HostAllowlist

    public init(platform: HostPlatform = .current, allowlist: HostAllowlist = .runtimeSources) {
        self.platform = platform
        self.allowlist = allowlist
    }

    /// Accepts or rejects one release. A catalog drops rejected candidates and keeps the others.
    public func check(_ release: RuntimeRelease) -> ReleaseRejection? {
        guard RuntimeVersion(release.version) != nil else { return .incomplete }
        if let sha256 = release.archiveSHA256, !FileDigest.isSHA256Hex(sha256) { return .incomplete }
        if let rejection = checkArtifact(release) { return rejection }
        let urls = [release.releasePage] + (release.signatureURL.map { [$0] } ?? [])
        guard urls.allSatisfy(allowlist.allows) else { return .unsupportedURL }
        guard release.architecture == platform.architecture,
            release.minimumOSMajor.map({ platform.osMajor >= $0 }) ?? true
        else { return .incompatible }
        return nil
    }

    /// - Throws: the rejection as a `JerdError`.
    public func validate(_ release: RuntimeRelease) throws {
        if let rejection = check(release) { throw rejection.error }
    }

    private func checkArtifact(_ release: RuntimeRelease) -> ReleaseRejection? {
        switch release.artifact {
        case .archive(let url, let size):
            guard (1...Self.archiveLimit).contains(size.limit) else { return .incomplete }
            guard release.archiveSHA256 != nil || hasPinnedSignature(release) else { return .unverifiable }
            if release.signatureURL != nil, !Self.signedKinds.contains(release.kind) { return .unverifiable }
            return allowlist.allows(url) ? nil : .unsupportedURL
        case .composerPackage:
            guard release.kind == .laravel, release.archiveSHA256 == nil, release.signatureURL == nil else {
                return .unverifiable
            }
            return nil
        case .lockedComposerProject(let directory):
            guard release.kind == .laravel, directory.isFileURL, release.archiveSHA256 != nil else {
                return .unverifiable
            }
            return nil
        }
    }

    private func hasPinnedSignature(_ release: RuntimeRelease) -> Bool {
        release.signatureURL != nil && Self.signedKinds.contains(release.kind)
    }
}
