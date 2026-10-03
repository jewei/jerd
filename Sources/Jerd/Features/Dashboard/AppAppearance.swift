import AppKit
import Observation

enum AppIconChoice: String, CaseIterable, Identifiable {
    case rainbow, monogram, elephant, dots
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rainbow: "Rainbow hook"; case .monogram: "Monogram"
        case .elephant: "Elephant"; case .dots: "Dot matrix"
        }
    }
}

@MainActor @Observable
final class AppAppearance {
    var showMenuBar: Bool { didSet { defaults.set(showMenuBar, forKey: "showMenuBar") } }
    var showDock: Bool { didSet { defaults.set(showDock, forKey: "showDock"); applyDock() } }
    var icon: AppIconChoice {
        didSet { defaults.set(icon.rawValue, forKey: "appIcon"); applyIcon() }
    }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var icons: [AppIconChoice: NSImage] = [:]
    @ObservationIgnored private var menuIcons: [AppIconChoice: NSImage] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showMenuBar = defaults.object(forKey: "showMenuBar") as? Bool ?? true
        showDock = defaults.object(forKey: "showDock") as? Bool ?? true
        // Use Rainbow hook for new settings and removed icon choices.
        icon = AppIconChoice(rawValue: defaults.string(forKey: "appIcon") ?? "") ?? .rainbow
    }
    func image(for choice: AppIconChoice) -> NSImage? {
        if let cached = icons[choice] { return cached }
        let url = Bundle.main.url(forResource: "Icon-\(choice.rawValue)", withExtension: "png")
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        icons[choice] = image
        return image
    }
    var menuImage: NSImage? {
        if let cached = menuIcons[icon] { return cached }
        guard let image = image(for: icon)?.copy() as? NSImage else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        menuIcons[icon] = image
        return image
    }
    func apply() { applyDock(); applyIcon() }
    private func applyDock() { NSApp.setActivationPolicy(showDock ? .regular : .accessory) }
    private func applyIcon() { if let image = image(for: icon) { NSApp.applicationIconImage = image } }
}
