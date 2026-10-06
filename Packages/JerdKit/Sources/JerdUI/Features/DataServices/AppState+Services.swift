extension AppState {
    /// Lets the service models show another place in the window, for example Runtimes or a
    /// new database, without a reference to the whole app state.
    func connectServiceNavigation() {
        let show: @MainActor (Destination) -> Void = { [weak self] destination in
            self?.navigation.show(destination)
        }
        databases.navigate = show
        storage.navigate = show
        mail.navigate = show
    }
}
