import AppKit
import Observation

enum AppIconChoice: String, CaseIterable, Identifiable {
    case original, monogram, rainbow, elephant, dots, stack, lock
    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: "Original"; case .monogram: "Monogram"; case .rainbow: "Rainbow hook"
        case .elephant: "Elephant"; case .dots: "Dot matrix"; case .stack: "Site stack"; case .lock: "Secure J"
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
        icon = AppIconChoice(rawValue: defaults.string(forKey: "appIcon") ?? "") ?? .original
    }
    func image(for choice: AppIconChoice) -> NSImage? {
        if let cached = icons[choice] { return cached }
        let url = choice == .original ? Bundle.main.url(forResource: "AppIcon", withExtension: "icns") :
            Bundle.main.url(forResource: "Icon-\(choice.rawValue)", withExtension: "png")
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
