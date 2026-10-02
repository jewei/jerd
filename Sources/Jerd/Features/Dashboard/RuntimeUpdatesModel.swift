import Foundation
import Observation
import JerdCore

@MainActor @Observable
final class RuntimeUpdatesModel {
    var checks: [RuntimeKind: RuntimeUpdateCheck] = [:]
    var selections: [RuntimeKind: String] = [:]
    var installed: [ManagedRuntime] = []
    var companions: CLICompanions?
    var isChecking = false
    var installing: RuntimeKind?
    var progress: RuntimeInstallProgress?
    var messages: [RuntimeKind: String] = [:]
    var errors: [RuntimeKind: String] = [:]
    var loadError: String?
    var isShuttingDown = false
    private var isActivating = false
    private var loaded = false
    private var checkTask: Task<Void, Never>?
    private var work: Task<Void, Never>?
    let installer = RuntimeInstaller(directory: JSONConfigurationStore.applicationDirectory.appendingPathComponent("runtime-updates"))
    private let catalog = RuntimeUpdateCatalog()

    func load() {
        guard !loaded else { return }
        loaded = true
        Task { await refreshInstalled() }
    }
    func refreshInstalled() async {
        do {
            installed = try await installer.installed()
            companions = try await installer.companions()
            loadError = nil
        } catch { loadError = error.localizedDescription }
    }

    func check(model: AppModel) {
        guard !isChecking, !isShuttingDown else { return }
        isChecking = true
        let defaultPHP = model.configuration.runtimes.first { $0.id == model.configuration.defaultRuntimeID }?.version
        checkTask = Task {
            defer { isChecking = false }
            await withTaskGroup(of: RuntimeUpdateCheck.self) { group in
                var pending = RuntimeKind.allCases.makeIterator()
                for _ in 0..<3 {
                    if let kind = pending.next() { group.addTask { [catalog] in await catalog.check(kind) } }
                }
                for await result in group {
                    if Task.isCancelled { group.cancelAll(); break }
                    checks[result.kind] = result
                    if selections[result.kind] == nil || !result.releases.contains(where: { $0.id == selections[result.kind] }) {
                        let branch = defaultPHP?.split(separator: ".").prefix(2).joined(separator: ".")
                        let preferred = result.kind == .php ? result.releases.first { $0.version.hasPrefix((branch ?? "") + ".") } : nil
                        selections[result.kind] = (preferred ?? result.releases.first)?.id
                    }
                    if let kind = pending.next() { group.addTask { [catalog] in await catalog.check(kind) } }
                }
            }
        }
    }
    func selectedRelease(_ kind: RuntimeKind) -> RuntimeRelease? { checks[kind]?.releases.first { $0.id == selections[kind] } }

    func install(_ release: RuntimeRelease, model: AppModel, useAsDefault: Bool = true) {
        guard installing == nil, !isShuttingDown, !model.isBusy else { return }
        let generation: Int
        do { generation = try model.beginBackgroundWork() }
        catch { errors[release.kind] = error.localizedDescription; return }
        installing = release.kind; errors[release.kind] = nil; messages[release.kind] = nil
        let php = model.configuration.runtimes.first { $0.id == model.configuration.defaultRuntimeID }
        work = Task {
            defer {
                model.endBackgroundWork(generation)
                installing = nil; progress = nil; isActivating = false; work = nil
            }
            do {
                let runtime = try await installer.install(release, php: php, companions: companions) { [weak self] value in
                    Task { @MainActor in self?.progress = value }
                }
                try Task.checkCancellation()
                isActivating = true
                try await model.activateRuntime(runtime, useAsDefault: useAsDefault)
                messages[release.kind] = switch release.kind {
                case .mysql, .postgresql, .redis: "Installed \(runtime.version). Select it when adding a database service. Existing services keep their selected version."
                case .php: useAsDefault ? "PHP \(runtime.version) is the default. Pinned sites keep their selected version." : "PHP \(runtime.version) is available in each site's PHP selection."
                default: "Updated to \(runtime.version)."
                }
            } catch is CancellationError { messages[release.kind] = "Installation cancelled." }
            catch { errors[release.kind] = error.localizedDescription }
            await refreshInstalled()
        }
    }
    func cancelInstall() { if !isActivating { work?.cancel() } }
    var canCancel: Bool { installing != nil && !isActivating }
    func finishBeforeQuit() async {
        isShuttingDown = true
        checkTask?.cancel()
        if !isActivating { work?.cancel() }
        await work?.value
        await checkTask?.value
    }
    func resumeAfterCancelledQuit() { isShuttingDown = false }

    func installedVersions(_ kind: RuntimeKind, model: AppModel) -> [String] {
        let values: [String]
        switch kind {
        case .php: values = model.configuration.runtimes.map(\.version)
        case .caddy: values = model.configuration.caddy.map { [String($0.version.split(separator: " ").first ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "v"))] } ?? []
        case .composer: values = companions?.composerVersion.map { [$0] } ?? []
        case .laravel: values = companions?.laravelVersion.map { [$0] } ?? []
        case .mysql, .postgresql, .redis: values = model.databases.configuration.runtimes.filter { $0.engine.rawValue == kind.rawValue }.map(\.version)
        case .mailpit: values = model.mail.configuration.runtime.map { [$0.version] } ?? []
        case .rustfs: values = model.storage.configuration.runtime.map { [$0.version] } ?? []
        }
        return Set(values).sorted { (RuntimeVersion($0) ?? RuntimeVersion("0.0")!) > (RuntimeVersion($1) ?? RuntimeVersion("0.0")!) }
    }
    func isInstalled(_ release: RuntimeRelease, model: AppModel) -> Bool {
        if release.kind == .postgresql {
            // The bootstrap is Postgres.app 2.9.6, which provides PostgreSQL 18.6.
            // Later downloads retain both the package and engine versions in their receipt.
            return installed.contains { downloaded in
                downloaded.id == release.id && model.databases.configuration.runtimes.contains { $0.path == downloaded.directory.path }
            } ||
                (release.version == "2.9.6" && installedVersions(.postgresql, model: model).contains("18.6"))
        }
        return installedVersions(release.kind, model: model).contains(release.version)
    }
}
