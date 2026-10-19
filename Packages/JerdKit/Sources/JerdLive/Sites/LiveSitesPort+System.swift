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

    /// Stops the sites, replaces the CA, and starts again the sites that ran before. A failed
    /// start after a done replacement is reported like any other start.
    package func migrateCA() async throws {
        let running = await environment().siteIDs
        await sites.requestStop()
        try await gateway.migrateCA()
        if !running.isEmpty { _ = try await run(running) }
    }

    package func openLoginItems() async {
        await loginItems.openLoginItems()
    }
}
