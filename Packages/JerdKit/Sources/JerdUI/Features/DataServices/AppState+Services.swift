import Foundation

extension AppState {
    /// The pages that install pinned runtimes through the one shared installer.
    enum RuntimeInstallPage {
        case runtimes
        case databases
        case storage
        case mail
    }

    /// Lets the service models show another place in the window, for example Runtimes or a
    /// new database, and read the selected database, without a reference to the whole app state.
    func connectServiceNavigation() {
        let show: @MainActor (Destination) -> Void = { [weak self] destination in
            self?.navigation.show(destination)
        }
        databases.navigate = show
        databases.selectedService = { [weak self] in
            guard case .database(let id) = self?.navigation.selection(in: .databases) else { return nil }
            return id
        }
        storage.navigate = show
        // The card and the menu bar ask to install RustFS on the Storage page, in the front window.
        storage.presentPage = { [weak self] in
            self?.open(.section(.storage))
        }
        mail.navigate = show
        // The card and the menu bar ask to install Mailpit on the Mail page, in the front window.
        mail.presentPage = { [weak self] in
            self?.open(.section(.mail))
        }
        // One installer serves the four pages, so each page waits while another one installs.
        databases.runtimeInstallElsewhere = { [weak self] in
            self?.runtimeInstallReason(excluding: .databases)
        }
        storage.runtimeInstallElsewhere = { [weak self] in
            self?.runtimeInstallReason(excluding: .storage)
        }
        mail.runtimeInstallElsewhere = { [weak self] in
            self?.runtimeInstallReason(excluding: .mail)
        }
        runtimes.runtimeInstallElsewhere = { [weak self] in
            self?.runtimeInstallReason(excluding: .runtimes)
        }
    }

    /// Why an install on `page` waits: another page installs a runtime now. Nil when none does.
    func runtimeInstallReason(excluding page: RuntimeInstallPage) -> String? {
        if page != .runtimes, let installation = runtimes.installation {
            return RuntimeInstallCopy.waits(for: "Runtimes", installing: installation.kind.title)
        }
        if page != .databases, let installation = databases.runtimeInstallation {
            return RuntimeInstallCopy.waits(for: "The Databases page", installing: installation.offer.title)
        }
        if page != .storage, let installation = storage.runtimeInstallation {
            return RuntimeInstallCopy.waits(for: "The Storage page", installing: installation.offer.title)
        }
        if page != .mail, let installation = mail.runtimeInstallation {
            return RuntimeInstallCopy.waits(for: "The Mail page", installing: installation.offer.title)
        }
        return nil
    }
}
