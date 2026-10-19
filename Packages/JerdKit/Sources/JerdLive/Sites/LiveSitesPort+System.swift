import JerdWeb

extension LiveSitesPort {
    /// Stops the sites first, because the helper owns their ports, then registers it again.
    /// Host entries and CA trust stay.
    package func reconnectHelper() async throws {
        await sites.requestStop()
        try await helper.reconnect()
    }

    /// Stops the sites, removes the host entries and the CA trust through the gateway (which
    /// records the removal), then unregisters the helper.
    package func removeSystemSetup() async throws {
        await sites.requestStop()
        try await gateway.removeSetup()
        try await helper.unregister()
    }

    /// The fingerprint of Jerd's CA for `.test` names, made when it is missing.
    package func prepareCAMigration() async throws -> String {
        try await gateway.prepareCAMigration().fingerprint
    }

    /// Stops the sites, because the helper refuses changes while they hold the ports, then
    /// replaces the CA. The model starts the sites again, also after a failed update.
    package func migrateCA() async throws {
        await sites.requestStop()
        try await gateway.migrateCA()
    }

    package func openLoginItems() async {
        await loginItems.openLoginItems()
    }
}
