import JerdMail

/// The mail manager calls that the live ports use. `MailManager` is the live type.
package protocol MailManaging: Sendable {
    func load() async throws -> MailSettings
    func snapshot() async -> MailSnapshot
    func registerRuntime(_ runtime: MailRuntime) async throws
    func suggestedPorts() async throws -> MailPorts
    func edit(ports: MailPorts) async throws
    func start() async throws
    func stop() async throws
    func sendTestEmail() async throws
}

extension MailManager: MailManaging {}
