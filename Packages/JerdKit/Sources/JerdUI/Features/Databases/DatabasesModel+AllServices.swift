extension DatabasesModel {
    /// Starts every service that can start now. Each start runs as its own control, so each
    /// service shows its own result.
    public func startAll() {
        for service in services where canStart(service.id) {
            start(service.id)
        }
    }

    /// Stops every service that can stop now.
    public func stopAll() {
        for service in services where canStop(service.id) {
            stop(service.id)
        }
    }
}
