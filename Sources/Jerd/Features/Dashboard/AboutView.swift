import SwiftUI
import AppKit

struct AboutView: View {
    let model: AppModel
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"

    var body: some View {
        GroupedPane {
            HStack(spacing: 20) {
                if let icon = model.appearance.image(for: model.appearance.icon) {
                    Image(nsImage: icon).resizable().scaledToFit().frame(width: 80, height: 80)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Jerd").font(.system(size: 28, weight: .bold)).accessibilityAddTraits(.isHeader)
                    Text("Local PHP development. At home on your Mac.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("Version \(version) · Build \(build)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary).textSelection(.enabled)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.quaternary.opacity(0.5), in: Capsule())
                }
                Spacer()
            }
            .padding(.horizontal, 30).padding(.vertical, 24)
        } content: {
            Section {
                ControlRow("Jerd updates", detail: model.appUpdates.message) {
                    Button("Check for updates", systemImage: "arrow.clockwise") { model.appUpdates.checkForUpdates() }
                        .accessibilityLabel("Check for app updates")
                        .disabled(!model.appUpdates.canCheckForUpdates)
                }
                if let error = model.appUpdates.errorMessage { InlineMessage(error) }
                Toggle("Automatically check for app updates", isOn: Binding(
                    get: { model.appUpdates.automaticallyChecks },
                    set: { model.appUpdates.setAutomaticChecks($0) }))
                    .toggleStyle(.switch)
                    .disabled(!model.appUpdates.canChangePreferences)
                if let checked = model.appUpdates.lastCheck {
                    ValueRow("Last check", checked.formatted(date: .abbreviated, time: .shortened))
                }
                ControlRow("PHP and other runtimes") {
                    Button("Manage runtimes") { model.showDashboard(.runtimes) }
                }
            } header: { Text("Updates") } footer: {
                Text("Installation requires your approval. An app update restarts Jerd and stops its local services.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Versions") {
                ValueRow("Jerd", "\(version) (\(build))")
                ValueRow("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
                ValueRow("App architecture", architecture)
            }

            Section {
                ForEach(credits) { credit in
                    LabeledContent {
                        Text(credit.role).foregroundStyle(.secondary)
                    } label: {
                        Link(destination: credit.url) {
                            HStack(spacing: 6) {
                                Text(credit.name)
                                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.tertiary).accessibilityHidden(true)
                            }
                        }
                    }
                }
            } header: { Text("Credits") } footer: {
                Text("Made by Jerd contributors. These projects belong to their respective authors. Their license terms apply. License notices are included with the managed runtimes.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section {
                Text("Jerd is intended for local development. It does not isolate project code from your user account. Use trusted projects and keep backups of important data. Jerd is an independent project and is not affiliated with Laravel or the projects listed above.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } header: { Text("Disclaimer") } footer: {
                Text(Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "Copyright © 2026 Jerd contributors")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var architecture: String {
        #if arch(arm64)
        "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        "Intel (x86_64)"
        #else
        "Unknown"
        #endif
    }

    private struct Credit: Identifiable {
        let name: String
        let role: String
        let url: URL
        var id: String { name }
    }

    private var credits: [Credit] {
        [
            Credit(name: "PHP", role: "PHP CLI and PHP-FPM", url: URL(string: "https://www.php.net/")!),
            Credit(name: "Lerd PHP builds", role: "Native PHP packages", url: URL(string: "https://github.com/lerd-env/php")!),
            Credit(name: "Caddy", role: "Local web server and TLS", url: URL(string: "https://caddyserver.com/")!),
            Credit(name: "cloudflared", role: "Cloudflare Tunnel connector", url: URL(string: "https://github.com/cloudflare/cloudflared")!),
            Credit(name: "Composer", role: "PHP dependency manager", url: URL(string: "https://getcomposer.org/")!),
            Credit(name: "Laravel", role: "Application installer", url: URL(string: "https://laravel.com/")!),
            Credit(name: "MySQL", role: "Database server", url: URL(string: "https://www.mysql.com/")!),
            Credit(name: "PostgreSQL", role: "Database server", url: URL(string: "https://www.postgresql.org/")!),
            Credit(name: "Postgres.app", role: "Native PostgreSQL packages", url: URL(string: "https://postgresapp.com/")!),
            Credit(name: "Redis", role: "In-memory data store", url: URL(string: "https://redis.io/")!),
            Credit(name: "Mailpit", role: "Local mail capture", url: URL(string: "https://mailpit.axllent.org/")!),
            Credit(name: "RustFS", role: "S3-compatible object storage", url: URL(string: "https://rustfs.com/")!),
            Credit(name: "libarchive", role: "Runtime archive extraction", url: URL(string: "https://www.libarchive.org/")!),
            Credit(name: "Sparkle", role: "Signed app updates", url: URL(string: "https://sparkle-project.org/")!)
        ]
    }
}
