import JerdDesign

/// Sample values for the component gallery, taken from real Jerd states.
enum GallerySamples {
    static let statuses: [DisplayStatus] = [
        DisplayStatus("Ready", tone: .ready),
        DisplayStatus("Starting…", tone: .busy),
        DisplayStatus("Stopped", tone: .idle),
        DisplayStatus("Setup required", tone: .attention),
        DisplayStatus("Failed", tone: .failed),
    ]

    static let tintSymbols: [(tint: ServiceTint, systemImage: String)] = [
        (.sites, "globe"),
        (.tunnels, "network"),
        (.databases, "cylinder.split.1x2"),
        (.storage, "externaldrive.badge.icloud"),
        (.mail, "envelope"),
        (.runtimes, "shippingbox"),
        (.appearance, "paintbrush"),
        (.neutral, "gearshape"),
    ]

    static let longPath = "/Users/developer/Projects/clients/northwind-traders/storefront-2026/public"
    static let longTitle = "Northwind Traders storefront with a very long project name"

    /// The end of a MySQL log after a failed start, with paths relative to the data folder.
    static let failureLogLines = [
        "2026-10-06T22:13:01.512Z 0 [ERROR] [MY-010273] [Server] Could not create unix socket lock file data/mysql.sock.lock.",
        "2026-10-06T22:13:01.512Z 0 [ERROR] [MY-010268] [Server] Unable to setup unix socket lock file.",
        "2026-10-06T22:13:01.513Z 0 [ERROR] [MY-010119] [Server] Aborting",
    ]

    static func noAction() {}
}
