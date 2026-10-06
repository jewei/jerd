import Testing

@testable import JerdUI

@Suite("Dashboard card actions")
@MainActor
struct FeatureCardTests {
    private let actions = [
        FeatureAction(id: "storage.stop", title: "Stop Storage") {},
        FeatureAction(id: "storage.console", title: "Open Console", isPrimary: true) {},
        FeatureAction(id: "storage.refresh", title: "Refresh") {},
    ]

    @Test(
        "Every card layout keeps every action, as a button or in the More menu",
        arguments: FeatureCard.ActionLayout.allCases)
    func everyActionStays(layout: FeatureCard.ActionLayout) {
        let arrangement = FeatureCard.arrangement(of: actions, in: layout)
        let shown = (arrangement.buttons + arrangement.menu).map(\.id)
        #expect(Set(shown) == Set(actions.map(\.id)))
        #expect(shown.count == actions.count)
    }

    @Test("A narrow card keeps the next step as its button and moves the others into More")
    func overflowKeepsNextStep() {
        let arrangement = FeatureCard.arrangement(of: actions, in: .overflow)
        #expect(arrangement.buttons.map(\.id) == ["storage.console"])
        #expect(arrangement.menu.map(\.id) == ["storage.stop", "storage.refresh"])
        let plain = FeatureCard.arrangement(of: Array(actions.prefix(1)), in: .overflow)
        #expect(plain.buttons.map(\.id) == ["storage.stop"])
        #expect(plain.menu.isEmpty)
    }
}
