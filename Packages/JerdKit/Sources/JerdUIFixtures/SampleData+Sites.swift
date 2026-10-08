import Foundation
import JerdFoundation
import JerdTunnels
import JerdWeb

extension SampleData {
    public static let studioID = UUID(uuidString: "5C0D1E2F-3A4B-4C5D-8E6F-708192A3B4C5") ?? UUID()
    public static let northwindID = UUID(uuidString: "6D1E2F30-4B5C-4D6E-9F70-8192A3B4C5D6") ?? UUID()
    public static let legacyID = UUID(uuidString: "7E2F3041-5C6D-4E7F-A081-92A3B4C5D6E7") ?? UUID()
    public static let previewTunnelID = UUID(uuidString: "8F304152-6D7E-4F80-B192-A3B4C5D6E7F8") ?? UUID()
    public static let docsTunnelID = UUID(uuidString: "90415263-7E8F-4091-82A3-B4C5D6E7F809") ?? UUID()
    /// The SHA-256 of the sample installation CA.
    public static let caFingerprint = "9f2c4be17a03d5e86c41f0b29d7a3e5c18b06f4d2a97e3c50b1d8f6a4c2e9b70"
    /// A site that a tunnel still names after the site was removed.
    public static let removedSiteID = UUID(uuidString: "B2C3D4E5-F607-4182-93A4-B5C6D7E8F901") ?? UUID()
    /// The ID of the sample installation.
    public static let installationID = UUID(uuidString: "A1B2C3D4-E5F6-4071-8293-A4B5C6D7E8F9") ?? UUID()
    /// The sample installation CA, as an approval names it.
    public static let authority = InstallationAuthority(installationID: installationID, fingerprint: caFingerprint)

    public static let studio = Site(
        id: studioID, displayName: "Studio", projectPath: "\(user)/Projects/studio",
        documentRoot: "\(user)/Projects/studio/public", hostname: "studio.test")
    public static let northwind = Site(
        id: northwindID, displayName: "Northwind Shop", projectPath: "\(user)/Projects/northwind",
        documentRoot: "\(user)/Projects/northwind/public", hostname: "northwind.test", phpSelection: .pinned(php83ID))
    public static let legacy = Site(
        id: legacyID, displayName: "Legacy Blog", projectPath: "\(user)/Sites/legacy-blog",
        documentRoot: "\(user)/Sites/legacy-blog", hostname: "legacy-blog.test", isEnabled: false)

    /// Three sites, two PHP runtimes, and Caddy.
    public static let siteConfiguration = AppConfiguration(
        sites: [studio, northwind, legacy], runtimes: registrations.php, defaultRuntimeID: php84ID,
        caddy: CaddyRuntime(
            path: "\(user)/Library/Application Support/Jerd/runtimes/caddy", version: "v2.10.2", architectures: [.arm64]
        ))

    /// A setup that approves every sample hostname.
    public static let approvedSetup = HTTPSSetupStatus(
        hostnames: ["legacy-blog.test", "northwind.test", "studio.test"], installationID: installationID,
        certificateSHA256: caFingerprint,
        hostsConfigured: true, trustConfigured: true, trustPolicy: .serverTLS)

    /// The helper still runs the code from before an app update, and its automatic restart did not help.
    public static let staleHelperFailure = JerdError.unavailable(
        "Jerd restarted its system helper, but the helper still does not match this copy of Jerd. Click "
            + "Reconnect Helper… to try again. If it fails again, install Jerd again from its disk image "
            + "into Applications. (NSCocoaErrorDomain 4102)"
    ).with(.reconnectHelper)

    /// The user turned the helper off in Login Items & Extensions.
    public static let helperOffFailure = JerdError.unavailable(
        "The Jerd helper is turned off. Turn on Jerd in System Settings → General → Login Items & Extensions, "
            + "then try again. Host entries and certificate settings stay."
    ).with(.openLoginItems)

    /// Many sites with long names, for truncation.
    public static let longSiteConfiguration: AppConfiguration = {
        var configuration = siteConfiguration
        configuration.sites = (1...24).map { index in
            let name = "northwind-storefront-staging-\(index)"
            return Site(
                id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index)) ?? UUID(),
                displayName: "Northwind Storefront Staging Environment \(index)",
                projectPath: "\(user)/Projects/clients/northwind/storefronts/\(name)",
                documentRoot: "\(user)/Projects/clients/northwind/storefronts/\(name)/public",
                hostname: "\(name).test", isEnabled: index <= 18)
        }
        return configuration
    }()

    public static let previewTunnel = TunnelRegistration(
        id: previewTunnelID, name: "Studio preview", hostname: "preview.example.com", siteID: studioID,
        startOnLaunch: true, metricsPort: 20_241)
    public static let docsTunnel = TunnelRegistration(
        id: docsTunnelID, name: "Docs staging", hostname: "docs.example.com", originURL: "http://127.0.0.1:8000",
        metricsPort: 20_242)

    public static let tunnelConfiguration = TunnelConfiguration(
        runtime: TunnelRuntime(
            version: "2025.9.1",
            directory: URL(fileURLWithPath: "\(user)/Library/Application Support/Jerd/runtimes/cloudflared")),
        tunnels: [previewTunnel, docsTunnel])

    public static let tunnelLog = """
        2026-10-06T09:40:12Z INF Starting tunnel tunnelID=[redacted]
        2026-10-06T09:40:12Z INF Version 2025.9.1
        2026-10-06T09:40:13Z INF Registered tunnel connection connIndex=0 location=lhr01 protocol=quic
        2026-10-06T09:40:13Z INF Registered tunnel connection connIndex=1 location=ams02 protocol=quic
        """

    /// A long connector log with wide lines, for scrolling and wrapping.
    public static let longTunnelLog: String = (0..<60).map { index in
        let second = String(format: "%02d", index % 60)
        return index.isMultiple(of: 7)
            ? "2026-10-06T09:41:\(second)Z WRN Connection terminated error=\"timeout: no recent network activity\" "
                + "connIndex=\(index % 4) event=0 ip=198.41.192.\(index) originService=https://studio.test"
            : "2026-10-06T09:41:\(second)Z INF Registered tunnel connection connIndex=\(index % 4) location=lhr01"
    }.joined(separator: "\n")
}
