import JerdDesign
import JerdUI
import Observation

/// A service feature with fixed content, for the dashboard, the menu bar, polling, and the
/// staged quit before the feature work packages land. It records each lifecycle call.
@MainActor
@Observable
public final class InMemoryFeature: WorkspaceFeature, ShutdownParticipant {
    public let section: AppSection
    public var summary: FeatureSummary
    public var menuItems: [MenuBarItem]
    public var bannerActivity: BannerActivity?
    public var pollingPolicy: PollingPolicy
    public let shutdownPhase: ShutdownPhase
    /// What `shutdown()` returns. Nil makes it wait until its task is cancelled.
    public var stopsSafely: Bool?
    public private(set) var launchCount = 0
    public private(set) var refreshCount = 0
    public private(set) var shutdownCount = 0
    public private(set) var resumeCount = 0
    /// Every lifecycle call in order, for example `storage.shutdown`, shared across features.
    @ObservationIgnored public var journal: CallJournal?

    public init(
        section: AppSection, summary: FeatureSummary, menuItems: [MenuBarItem] = [],
        shutdownPhase: ShutdownPhase, stopsSafely: Bool? = true, pollingPolicy: PollingPolicy = .services
    ) {
        self.section = section
        self.summary = summary
        self.menuItems = menuItems
        self.shutdownPhase = shutdownPhase
        self.stopsSafely = stopsSafely
        self.pollingPolicy = pollingPolicy
    }

    public var shutdownParticipants: [any ShutdownParticipant] { [self] }

    public func launch() async {
        launchCount += 1
        journal?.record("\(section.title.lowercased()).launch")
    }

    public func refresh() async {
        refreshCount += 1
    }

    public func shutdown() async -> Bool {
        shutdownCount += 1
        journal?.record("\(section.title.lowercased()).shutdown")
        guard let stopsSafely else {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
            }
            return false
        }
        return stopsSafely
    }

    public func resumeAfterCancelledQuit() {
        resumeCount += 1
        journal?.record("\(section.title.lowercased()).resume")
    }
}
