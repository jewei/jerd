import Foundation
import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("Appearance settings and defaults compatibility")
@MainActor
struct AppearanceTests {
    @Test("Absent keys read as menu bar on, Dock on, and Rainbow hook")
    func defaultsWhenAbsent() {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        let model = fixture.state.appearance
        #expect(model.showMenuBar)
        #expect(model.showDock)
        #expect(model.icon == .rainbow)
    }

    @Test(
        "Saved icon values read as their design; old and unknown values read as Rainbow hook",
        arguments: [
            ("rainbow", AppIconChoice.rainbow), ("monogram", .monogram), ("elephant", .elephant), ("dots", .dots),
            ("original", .rainbow), ("stack", .rainbow), ("lock", .rainbow), ("unknown", .rainbow),
        ])
    func iconCompatibility(stored: String, expected: AppIconChoice) {
        let fixture = AppFixture { $0.set(stored, forKey: "appIcon") }
        defer { fixture.removeDefaults() }
        #expect(fixture.state.appearance.icon == expected)
        #expect(fixture.defaults.string(forKey: "appIcon") == stored)
    }

    @Test("Saved Bool values of the old app are read")
    func boolCompatibility() {
        let fixture = AppFixture { defaults in
            defaults.set(false, forKey: "showMenuBar")
            defaults.set(false, forKey: "showDock")
        }
        defer { fixture.removeDefaults() }
        #expect(!fixture.state.appearance.showMenuBar)
        #expect(!fixture.state.appearance.showDock)
        #expect(fixture.state.appearance.isHiddenEverywhere)
    }

    @Test("Each change is saved with the same key and value form, and applied")
    func changesSaveAndApply() {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        let model = fixture.state.appearance
        model.showMenuBar = false
        model.showDock = false
        model.icon = .elephant
        #expect(fixture.defaults.object(forKey: "showMenuBar") as? Bool == false)
        #expect(fixture.defaults.object(forKey: "showDock") as? Bool == false)
        #expect(fixture.defaults.string(forKey: "appIcon") == "elephant")
        #expect(fixture.shell.dockStates == [false])
        #expect(fixture.shell.icons == [.elephant])
    }

    @Test("Icon choices keep their order, titles, and image names")
    func iconChoices() {
        #expect(AppIconChoice.allCases.map(\.rawValue) == ["rainbow", "monogram", "elephant", "dots"])
        #expect(AppIconChoice.allCases.map(\.title) == ["Rainbow hook", "Monogram", "Elephant", "Dot matrix"])
        #expect(AppIconChoice.dots.imageName == "Icon-dots")
        #expect(AppIconChoice(storedValue: nil) == .rainbow)
    }

    @Test("Every shipped icon design has a fixture image")
    func fixtureImages() {
        let images = BundleIconImages()
        #expect(AppIconChoice.allCases.allSatisfy { images.image(for: $0) != nil })
    }
}
