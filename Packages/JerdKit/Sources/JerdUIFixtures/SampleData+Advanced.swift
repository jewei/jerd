import Foundation
import JerdProcess
import JerdServiceKit
import JerdSystem
import JerdUI
import JerdWeb

extension SampleData {
    public static let findings = [
        RecoveryFinding(
            id: "Mail", title: "Mail", detail: "Mailpit from a previous session is still running as process 4182.",
            state: .recoverable),
        RecoveryFinding(
            id: "Database/1F3A0000-0000-4000-8000-000000000001", title: "Database 1F3A0000",
            detail: "The saved processes of this database have stopped.", state: .stale),
        RecoveryFinding(
            id: "Storage", title: "Storage",
            detail: "Jerd cannot prove that process 5120 belongs to this record. Stop it in Activity Monitor.",
            state: .manual),
    ]

    public static let backups = [
        RetainedBackup(
            id: "Mail/6C1E2D3F-0000-4000-8000-000000000002", service: "Mail",
            directory: URL(fileURLWithPath: "\(user)/Library/Application Support/Jerd/mail/backups/6C1E2D3F"),
            bytes: 18_874_368, detail: "Kept by the Mailpit 1.27.7 update on 6 October 2026.", isProtected: false),
        RetainedBackup(
            id: "Storage/9A8B7C6D-0000-4000-8000-000000000003", service: "Storage",
            directory: URL(fileURLWithPath: "\(user)/Library/Application Support/Jerd/storage/backups/9A8B7C6D"),
            bytes: nil, detail: "A pending recovery protects this backup.", isProtected: true),
    ]

    public static let registrations = LocalRuntimeRegistrations(
        php: [
            DevelopmentRuntime(
                id: php84ID, cliPath: "\(user)/Library/Application Support/Jerd/runtime-updates/php-8.4.12/bin/php",
                fpmPath: "\(user)/Library/Application Support/Jerd/runtime-updates/php-8.4.12/sbin/php-fpm",
                version: "8.4.12", architectures: [.arm64], cliExtensions: ["Core", "curl", "intl", "mbstring", "pdo_mysql"],
                fpmExtensions: ["Core", "curl", "intl", "mbstring", "opcache", "pdo_mysql"], inspectedAt: now),
            DevelopmentRuntime(
                id: php83ID, cliPath: "/opt/homebrew/opt/php@8.3/bin/php", fpmPath: "/opt/homebrew/opt/php@8.3/sbin/php-fpm",
                version: "8.3.24", architectures: [.arm64], cliExtensions: ["Core", "curl"], fpmExtensions: ["Core", "curl"],
                inspectedAt: now),
        ],
        defaultPHPID: php84ID, caddyVersion: "2.10.2",
        setupMessage: "PHP, Caddy, Composer, and the Laravel installer are installed and managed by Jerd.")

    public static let httpsRecovery = SystemRecoveryStatus(
        id: "5d41402abc4b2a76b9719d911017c592", operation: "Configure", phase: "Trust",
        details: ["The hosts section was written.", "The CA trust change did not finish."], canRestore: true,
        canRemove: true, installationID: php84ID, certificateDER: Data("Jerd sample CA".utf8),
        previousHostnames: ["studio.test"], intendedHostnames: ["studio.test", "api.test"], policies: [])
}
