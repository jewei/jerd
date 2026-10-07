/// Every user-visible message of the tunnel area, in one place. The wording keeps the meaning of earlier builds.
package enum TunnelMessage {
    // Registration and settings
    package static let invalidName = "Enter a name of 1 to 100 characters and a metrics port above 1023."
    package static let invalidHostname =
        "Enter a public hostname in lower case, such as preview.example.com. Do not include a scheme or path."
    package static let addressHostname =
        "Enter the public hostname of the Cloudflare route, such as preview.example.com. An IP address is not a hostname."
    package static let invalidOrigin = "Use one registered site or a local HTTP or HTTPS address without credentials."
    package static let invalidConfiguration =
        "Tunnel settings have an unsupported format, duplicate records, or duplicate metrics ports."
    package static let invalidRuntime = "The cloudflared runtime record is invalid."
    package static let settingsName = "tunnel settings"

    // Tokens
    package static let tokenCharacters = "Paste the tunnel token without spaces or a command."
    package static let tokenFormat =
        "The token format is invalid. Copy the token for an existing remotely managed Cloudflare tunnel."
    package static let duplicateTunnel = "This Cloudflare tunnel is already saved in Jerd."
    package static let tokenRequired = "Enter the existing tunnel token."
    package static let tokenMissing = "The tunnel token is missing. Edit this tunnel to add its token."

    // Supervisor guards
    package static let notLoaded = "Load tunnel settings before changing a tunnel."
    package static let busy = "Wait for the current tunnel operation to finish."
    package static let runtimeInUse = "Stop all tunnels before changing cloudflared."
    package static let stopBeforeEdit = "Stop the tunnel before changing its settings."
    package static let stopBeforeRemove = "Stop the tunnel before removing it from Jerd."
    package static let notRegistered = "The tunnel is not registered."
    package static let alreadyActive = "This tunnel already has a connection or a pending operation."
    package static let runtimeMissing = "Install or select cloudflared before connecting."
    package static let noLog = "No connection log yet."
    package static let cancelled = "The tunnel operation was cancelled."

    // Connection failures
    package static let tokenRejected = "Cloudflare rejected the tunnel token. Edit this tunnel to replace its token."
    package static let tokenRejectedPrefix = "Cloudflare rejected the token. "
    package static let processExited = "The tunnel process exited. Select Connect to try again."
    package static let unexpectedListener =
        "The tunnel opened an unexpected listener. Jerd requested a graceful stop. Check its log before retrying."
    package static func failedStarts(_ count: Int, lastError: String?) -> String {
        let text =
            "The tunnel process failed to start \(count) times in a row, so Jerd stopped the retries. "
            + "Read the tunnel log, then select Connect."
        return lastError.map { text + " Last error: " + $0 } ?? text
    }

    // Connector
    package static let executableName = "Select an executable named cloudflared."
    package static let noVersion = "The selected executable did not report a cloudflared version."
    package static let previousProcess = "The previous tunnel process must stop first."
    package static let lockUnavailable = "Cannot lock the tunnel files."
    package static let lockBusy = "Another Jerd session controls this tunnel."
    package static let versionMismatch = "The cloudflared executable does not match the saved version."
    package static let exitedEarly = "The tunnel process exited before its identity could be checked."
    package static let notStopped =
        "The tunnel has not stopped. Its process is still tracked. Retry Stop; Jerd did not force it to exit."

    // Keychain
    package static func keychainRead(_ status: Int32) -> String {
        "Cannot read the tunnel token from Keychain (\(status))."
    }
    package static let keychainAdd = "Cannot save the tunnel token in Keychain."
    package static func keychainUpdate(_ status: Int32) -> String {
        "Cannot update the tunnel token in Keychain (\(status))."
    }
    package static func keychainRemove(_ status: Int32) -> String {
        "Cannot remove the tunnel token from Keychain (\(status))."
    }
}
