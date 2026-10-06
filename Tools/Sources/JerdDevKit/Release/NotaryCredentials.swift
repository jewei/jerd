/// The `notarytool` Keychain profile and, optionally, the Keychain that holds it.
struct NotaryCredentials: Equatable, Sendable {
    let profile: String
    let keychain: String?

    init(profile: String, keychain: String?) throws {
        guard !profile.isEmpty, !profile.hasPrefix("-") else {
            throw DevFailure.usage("Name the notarytool Keychain profile with --notary-profile.")
        }
        guard keychain.map({ $0.hasPrefix("/") }) ?? true else {
            throw DevFailure.usage("Use an absolute path for --keychain.")
        }
        self.profile = profile
        self.keychain = keychain
    }

    /// The authentication arguments of every `notarytool` call.
    var arguments: [String] {
        ["--keychain-profile", profile] + (keychain.map { ["--keychain", $0] } ?? [])
    }
}
