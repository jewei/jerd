import Foundation

extension AppState {
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
        mail.navigate = show
        // One installer serves both pages, so each page waits while the other one installs.
        databases.runtimeInstallElsewhere = { [weak self] in
            self?.runtimes.installation.map(\.kind.title)
        }
        runtimes.runtimeInstallElsewhere = { [weak self] in
            self?.databases.runtimeInstallation.map(\.offer.title)
        }
    }
}
