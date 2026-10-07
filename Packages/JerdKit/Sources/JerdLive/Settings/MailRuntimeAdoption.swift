import JerdMail

/// Puts an installed Mailpit build into use with the mail manager.
///
/// The app installs Mailpit on demand, so a new user has no saved runtime. A build from Check for
/// Runtime Updates is then registered, the same way as the on-demand install: no inbox exists for
/// it, and `registerRuntime` never replaces a saved runtime. With a saved runtime the build goes
/// through the journaled update, which checks and backs up the inbox.
package enum MailRuntimeAdoption {
    package static func adopt(_ runtime: MailRuntime, manager: any MailManaging) async throws {
        if await manager.snapshot().settings.runtime == nil {
            try await manager.registerRuntime(runtime)
        } else {
            try await manager.updateRuntime(runtime)
        }
    }
}
