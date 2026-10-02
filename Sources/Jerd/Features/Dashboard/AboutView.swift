import SwiftUI
import AppKit

struct AboutView: View {
    let model: AppModel
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("About").font(.largeTitle.bold())
                HStack(spacing: 18) {
                    if let icon = model.appearance.image(for: model.appearance.icon) {
                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 80, height: 80)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Jerd").font(.title.bold())
                        Text("A local PHP development environment for macOS.").foregroundStyle(.secondary)
                        Text("Version \(version) · Build \(build)").font(.callout).textSelection(.enabled)
                    }
                }

                GroupBox("App updates") {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Jerd updates", systemImage: "arrow.triangle.2.circlepath").font(.headline)
                        Text(model.appUpdates.message)
                            .foregroundStyle(.secondary)
                        if let error = model.appUpdates.errorMessage {
                            Text(error).foregroundStyle(.red).textSelection(.enabled)
                        }
                        Button("Check for app updates") { model.appUpdates.checkForUpdates() }
                            .disabled(!model.appUpdates.canCheckForUpdates)
                        Toggle("Automatically check for app updates", isOn: Binding(
                            get: { model.appUpdates.automaticallyChecks },
                            set: { model.appUpdates.setAutomaticChecks($0) }))
                            .disabled(!model.appUpdates.canChangePreferences)
                        if let checked = model.appUpdates.lastCheck {
                            Text("Last check: \(checked.formatted(date: .abbreviated, time: .shortened))")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Text("Installation requires your approval. An app update restarts Jerd and stops its local services.")
                            .font(.callout).foregroundStyle(.secondary)
                        Divider()
                        Text("PHP and other runtime updates are available in Runtimes.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Manage runtimes") { model.showDashboard(.runtimes) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }

                GroupBox("Versions") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("Jerd", value: "\(version) (\(build))")
                        LabeledContent("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                        LabeledContent("App architecture", value: architecture)
                    }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(12)
                }

                GroupBox("Credits") {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Made by Jerd contributors. Jerd uses these open-source projects:")
                            .foregroundStyle(.secondary)
                        ForEach(credits) { credit in
                            HStack(alignment: .firstTextBaseline) {
                                Link(credit.name, destination: credit.url)
                                Spacer(minLength: 16)
                                Text(credit.role).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                            }
                        }
                        Divider()
                        Text("These projects belong to their respective authors. Their license terms apply. License notices are included with the managed runtimes.")
                            .font(.callout).foregroundStyle(.secondary)
                    }.padding(12)
                }

                GroupBox("Disclaimer") {
                    Text("Jerd is intended for local development. It does not isolate project code from your user account. Use trusted projects and keep backups of important data. Jerd is an independent project and is not affiliated with Laravel or the projects listed above.")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }
                Text(Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "Copyright © 2026 Jerd contributors")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 900, alignment: .leading).padding(30).frame(maxWidth: .infinity, alignment: .topLeading)
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
