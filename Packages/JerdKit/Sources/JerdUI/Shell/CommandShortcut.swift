import SwiftUI

/// A keyboard shortcut as a comparable value.
public struct CommandShortcut: Equatable, Sendable {
    public let key: Character
    public let modifiers: EventModifiers

    public init(_ key: Character, modifiers: EventModifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    /// The SwiftUI shortcut.
    public var keyboardShortcut: KeyboardShortcut {
        KeyboardShortcut(KeyEquivalent(key), modifiers: modifiers)
    }
}
