import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit

/// The managed-service definition of the one Mailpit inbox.
///
/// Start steps after the shared lock, record, and version checks: inbox identity and database
/// (`MailInbox`) → the launch plan. After the readiness and listener checks, `initialized.json`
/// records the runtime.
///
/// Mailpit gets an explicit database path, loopback SMTP and web listeners, a host allowlist for
/// the web service, no automatic deletion (`--max 0`), no version check, no reverse DNS, and no
/// remote CSS or fonts. Its environment is the clean base environment only, so no relay,
/// forwarding, webhook, POP3, or user configuration applies.
struct MailpitDefinition: ServiceDefinition {
    let runtime: MailRuntime
    let ports: MailPorts
    let profile: ServiceProfile
    let layout: MailLayout
    let server: any MailServerProbing

    /// - Parameters:
    ///   - dataRoot: the existing owned folder that contains `mail/`.
    ///   - server: answers the readiness questions of a running Mailpit.
    init(
        runtime: MailRuntime, ports: MailPorts, layout: MailLayout, dataRoot: URL, server: any MailServerProbing
    ) {
        self.runtime = runtime
        self.ports = ports
        self.layout = layout
        self.server = server
        profile = ServiceProfile(
            name: "Mailpit", runtimeID: runtime.id, record: layout.record, containingDirectory: dataRoot,
            log: ServiceLog(file: layout.logFile, previousFile: layout.previousLogFile), ports: ports.ordered,
            messages: MailMessages.instance)
    }

    /// `mailpit version --no-release-check` must print a line that starts with the executable
    /// path and the saved version. A version that is only part of the path cannot match.
    var versionProbe: VersionProbe {
        VersionProbe(
            request: ProcessRequest(
                executable: runtime.executable, arguments: ["version", "--no-release-check"],
                workingDirectory: layout.root),
            rule: .labelledLine(label: runtime.executable.path, version: runtime.version),
            mismatchMessage: MailMessages.versionMismatch)
    }

    var inbox: MailInbox { MailInbox(layout: layout) }

    func prepareStart(_ tools: StartTools) async throws -> LaunchPlan {
        try inbox.prepare(for: runtime)
        let readiness = MailReadinessProbe(
            runtime: runtime, database: layout.inboxDatabaseFile, ports: ports, server: server)
        return LaunchPlan(request: serverRequest, ports: Set(ports.ordered), readiness: readiness.check)
    }

    func completeStart() async throws {
        try inbox.markInitialized(runtime)
    }

    /// The exact Mailpit command line.
    var serverRequest: ProcessRequest {
        ProcessRequest(
            executable: runtime.executable,
            arguments: [
                "--database", layout.inboxDatabaseFile.path,
                "--smtp", "127.0.0.1:\(ports.smtp)",
                "--listen", "127.0.0.1:\(ports.web)",
                "--allowed-hosts", "127.0.0.1,localhost",
                "--label", "Jerd",
                "--max", "0",
                "--disable-version-check",
                "--smtp-disable-rdns",
                "--block-remote-css-and-fonts",
            ], workingDirectory: layout.root)
    }
}
