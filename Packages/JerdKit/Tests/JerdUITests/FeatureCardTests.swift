import AppKit
import Foundation
import JerdDesign
import JerdServiceKit
import JerdUIFixtures
import JerdWeb
import SwiftUI
import Testing

@testable import JerdUI

/// The one button rule of the dashboard cards (`CardActionRule`, JerdUI README).
@Suite("Dashboard card rule")
@MainActor
struct FeatureCardTests {
    /// The rule for every card in every state: at most two actions, lifecycle first and the
    /// Open step second, at most one primary, and Stop is never primary. (During a quit a
    /// primary action is off; `primaryActionStyle` then draws it plain.)
    static func ruleProblems(_ actions: [FeatureAction], card: String) -> [String] {
        var problems: [String] = []
        if actions.count > 2 { problems.append("\(card): \(actions.count) actions") }
        let primaries = actions.filter(\.isPrimary)
        if primaries.count > 1 { problems.append("\(card): \(primaries.count) primary actions") }
        for action in primaries where action.title.hasPrefix("Stop") {
            problems.append("\(card): \(action.title) is primary")
        }
        if actions.count == 2, !actions[1].title.hasPrefix("Open") {
            problems.append("\(card): the second action \(actions[1].title) is not an Open step")
        }
        return problems
    }

    private func titles(_ actions: [FeatureAction]) -> [String] {
        actions.map { $0.isPrimary ? "[\($0.title)]" : $0.title }
    }

    // MARK: The rule

    @Test("A stopped feature has Start as the one next step")
    func stoppedStartIsPrimary() {
        let actions = CardActionRule.actions(.start(FeatureAction(id: "start", title: "Start") {}))
        #expect(titles(actions) == ["[Start]"])
    }

    @Test("A running feature has Open as the next step and Stop as a plain button")
    func runningOpenIsPrimary() {
        let actions = CardActionRule.actions(
            .stop(FeatureAction(id: "stop", title: "Stop") {}), open: FeatureAction(id: "open", title: "Open Inbox") {})
        #expect(titles(actions) == ["Stop", "[Open Inbox]"])
    }

    @Test("Without an Open step that can run, nothing is primary while the feature stops or runs")
    func stopIsNeverPrimary() {
        let closed = FeatureAction(id: "open", title: "Open Inbox", isEnabled: false) {}
        let actions = CardActionRule.actions(.stop(FeatureAction(id: "stop", title: "Stop") {}), open: closed)
        #expect(titles(actions) == ["Stop", "Open Inbox"])
        let busy = CardActionRule.actions(.start(FeatureAction(id: "start", title: "Start", isEnabled: false) {}))
        #expect(titles(busy) == ["Start"])
    }

    // MARK: Each card and state

    @Test("Storage: Start when stopped; Stop and Open Console when running")
    func storageCard() async {
        let storage = InMemoryStorage(settings: .init(runtime: SampleServices.storageRuntime))
        let fixture = AppFixture(
            services: InMemoryServicePorts(databases: InMemoryDatabases(), storage: storage, mail: InMemoryMail()))
        defer { fixture.removeDefaults() }
        await fixture.state.launch()
        let model = fixture.state.storage
        #expect(titles(model.summary.actions) == ["[Start]"])
        #expect(model.summary.actions.map(\.spokenTitle) == ["Start Storage"])
        await model.start()?.value
        #expect(titles(model.summary.actions) == ["Stop", "[Open Console]"])
        #expect(model.summary.actions.map(\.spokenTitle) == ["Stop Storage", "Open Console"])
    }

    @Test("Mail: Start when stopped; Stop and Open Inbox when running")
    func mailCard() async {
        let mail = InMemoryMail(settings: .init(runtime: SampleServices.mailRuntime))
        let fixture = AppFixture(
            services: InMemoryServicePorts(databases: InMemoryDatabases(), storage: InMemoryStorage(), mail: mail))
        defer { fixture.removeDefaults() }
        await fixture.state.launch()
        let model = fixture.state.mail
        #expect(titles(model.summary.actions) == ["[Start]"])
        await model.start()?.value
        #expect(titles(model.summary.actions) == ["Stop", "[Open Inbox]"])
        #expect(model.summary.actions.map(\.spokenTitle) == ["Stop Mail", "Open Inbox"])
    }

    @Test("Databases: Add when empty, Start All while one is stopped, else Stop All")
    func databasesCard() async throws {
        let empty = AppFixture(services: InMemoryServicePorts(.empty))
        defer { empty.removeDefaults() }
        await empty.state.launch()
        #expect(titles(empty.state.databases.summary.actions) == ["[Add Database…]"])

        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        await fixture.state.launch()
        let model = fixture.state.databases
        #expect(titles(model.summary.actions) == ["[Start All]"])
        #expect(model.summary.actions.map(\.spokenTitle) == ["Start All Databases"])
        try #require(model.summary.actions.first).perform()
        await waitUntil { model.services.allSatisfy { model.state(of: $0.id).isRunning } && model.busyServices.isEmpty }
        #expect(titles(model.summary.actions) == ["Stop All"])
        try #require(model.summary.actions.first).perform()
        await waitUntil {
            model.services.allSatisfy { !model.state(of: $0.id).offersStop } && model.busyServices.isEmpty
        }
        #expect(titles(model.summary.actions) == ["[Start All]"])
    }

    @Test("Sites: Add when empty, Start All when stopped, Stop All and Open Site when running")
    func sitesCard() async {
        let empty = await SitesHarness.launched(
            sites: InMemorySitesPort(configuration: AppConfiguration()),
            tunnels: InMemoryTunnelsPort(configuration: .init()))
        #expect(titles(empty.model.summary.actions) == ["[Add Site…]"])

        let stopped = await SitesHarness.launched()
        #expect(titles(stopped.model.summary.actions) == ["[Start All]"])
        #expect(stopped.model.summary.actions.map(\.spokenTitle) == ["Start All Sites"])

        let one = await SitesHarness.launched(
            sites: InMemorySitesPort(environment: EnvironmentSnapshot(state: .running, siteIDs: [SampleData.studioID])))
        #expect(titles(one.model.summary.actions) == ["Stop All", "[Open Site]"])
        #expect(one.model.summary.actions.map(\.spokenTitle) == ["Stop All Sites", "Open Studio"])
        one.model.summary.actions.last?.perform()
        #expect(one.shell.openedURLs == [URL(string: "https://\(SampleData.studio.hostname)")])

        let two = await SitesHarness.launched(
            sites: InMemorySitesPort(
                environment: EnvironmentSnapshot(
                    state: .running, siteIDs: [SampleData.studioID, SampleData.northwindID])))
        // Several served sites: the first in sidebar order; the menu bar lists every one.
        let open = two.model.summary.actions.last
        #expect(open?.isPrimary == true)
        #expect(open?.spokenTitle == "Open Studio")
    }

    @Test("Every card of every dashboard scenario follows the rule", arguments: FixtureScenario.allCases)
    func everyScenarioFollowsTheRule(scenario: FixtureScenario) async {
        let host = ScenarioHost(scenario)
        await host.prepare()
        defer { host.fixture.removeDefaults() }
        for section in DashboardCards.sections {
            let actions = DashboardCards.summary(for: section, in: host.fixture.state).actions
            #expect(Self.ruleProblems(actions, card: section.title).isEmpty, "\(scenario.rawValue)")
        }
    }

    // MARK: Compact width

    /// The width of one card at the minimum window size: the page column of the detail column
    /// next to the sidebar (which the picker limits there), in two grid columns.
    static var compactCardWidth: CGFloat {
        let window = WindowMetrics.minimumSize.width
        let detail = window - SidebarWidthLimit.idealWidth(windowWidth: window)
        return (PageMetrics.columns(forWidth: detail).contentWidth - Spacing.large) / 2
    }

    private func height(of summary: FeatureSummary, section: AppSection) -> CGFloat {
        let card = FeatureCard(section: section, summary: summary) {}.frame(width: Self.compactCardWidth)
        let view = NSHostingView(rootView: card)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.compactCardWidth, height: 400), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        defer { window.close() }
        return view.fittingSize.height
    }

    @Test(
        "At the minimum window size every card keeps its actions in one row, so cards in a row match",
        arguments: [FixtureScenario.dashboard, .dashboardBusy, .dashboardEmpty, .dashboardLong])
    func compactCardsKeepOneRow(scenario: FixtureScenario) async {
        _ = NSApplication.shared
        let host = ScenarioHost(scenario)
        await host.prepare()
        defer { host.fixture.removeDefaults() }
        let oneAction = FeatureSummary(
            status: DisplayStatus("Stopped", tone: .idle), summary: "x",
            actions: [FeatureAction(id: "start", title: "Start") {}])
        for section in DashboardCards.sections {
            let summary = DashboardCards.summary(for: section, in: host.fixture.state)
            let heights = (height(of: summary, section: section), height(of: oneAction, section: section))
            // A column adds a whole button line; less is the rounding of the backing scale.
            #expect(
                abs(heights.0 - heights.1) < 8,
                "\(scenario.rawValue) \(section.title) puts its actions in a column: \(heights)")
        }
    }

    @Test("The column layout appears when two long actions do not fit")
    func longActionsUseAColumn() {
        _ = NSApplication.shared
        let long = FeatureSummary(
            status: DisplayStatus("Ready", tone: .ready), summary: "x",
            actions: [
                FeatureAction(id: "a", title: "Stop Every Service Now") {},
                FeatureAction(id: "b", title: "Open The Web Console", isPrimary: true) {},
            ])
        let short = FeatureSummary(status: long.status, summary: "x", actions: [long.actions[0]])
        #expect(height(of: long, section: .storage) > height(of: short, section: .storage))
    }
}
