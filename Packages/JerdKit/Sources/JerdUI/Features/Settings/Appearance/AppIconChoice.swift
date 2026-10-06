/// A shipped app icon design. The raw values are saved under the `appIcon` defaults key and
/// name the bundle images `Icon-<raw value>.png`; they must not change.
public enum AppIconChoice: String, CaseIterable, Identifiable, Hashable, Sendable {
    case rainbow
    case monogram
    case elephant
    case dots

    public var id: String { rawValue }

    /// The name under the tile in the icon picker.
    public var title: String {
        switch self {
        case .rainbow: "Rainbow hook"
        case .monogram: "Monogram"
        case .elephant: "Elephant"
        case .dots: "Dot matrix"
        }
    }

    /// The bundle image name, without the `png` extension.
    public var imageName: String { "Icon-\(rawValue)" }

    /// Reads a saved value. Earlier builds saved `original`, `stack`, and `lock`; those, unknown
    /// values, and a missing value all read as the default, Rainbow hook.
    public init(storedValue: String?) {
        self = storedValue.flatMap(AppIconChoice.init(rawValue:)) ?? .rainbow
    }
}
