/// The build settings of one group in the pin catalog: whether the app bundle embeds its payloads.
///
/// An embedded group is copied into the app and installed at first launch. The app installs the
/// pins of a group that is not embedded on demand, from the same pins, after a user action.
public struct PayloadGroupSettings: Codable, Equatable, Sendable {
    public let embedded: Bool

    public init(embedded: Bool) { self.embedded = embedded }
}
