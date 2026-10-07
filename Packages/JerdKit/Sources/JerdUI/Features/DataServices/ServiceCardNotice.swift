import JerdDesign

/// What a service card says instead of its connection values while the service cannot run yet:
/// while Jerd prepares the bundled runtime at launch, after a failed load, and when no runtime
/// is installed. The not-installed text shows only after the load ended, because the load is
/// what installs the bundled runtime.
struct ServiceCardNotice: Equatable {
    /// The card summary.
    let text: String
    /// Why Start or Add is off: the tooltip and VoiceOver hint of the action.
    let reason: String
    /// True while Jerd prepares the runtime: the card status is "Preparing…".
    let isPreparing: Bool

    /// The card status while Jerd prepares the runtime.
    static let preparingStatus = DisplayStatus("Preparing…", tone: .busy)

    /// The notice for a feature, or nil when its runtime is ready.
    /// - Parameters:
    ///   - runtime: The runtime name, for example "Mailpit".
    ///   - settings: The settings name, for example "Mail".
    ///   - missingRuntime: The text and reason without a runtime, if the feature words them itself.
    static func notice(
        load: ServiceLoadState, hasRuntime: Bool, runtime: String, settings: String,
        missingRuntime: ServiceCardNotice? = nil
    ) -> ServiceCardNotice? {
        switch load {
        case .loading:
            return ServiceCardNotice(
                text: "Preparing \(runtime)…", reason: "Jerd is preparing \(runtime).", isPreparing: true)
        case .failed:
            let text = "\(settings) settings could not be loaded."
            return ServiceCardNotice(text: text, reason: text, isPreparing: false)
        case .loaded:
            guard !hasRuntime else { return nil }
            return missingRuntime
                ?? ServiceCardNotice(
                    text: "\(runtime) is not installed. Install it in Runtimes.",
                    reason: "Install \(runtime) in Runtimes first.", isPreparing: false)
        }
    }
}
