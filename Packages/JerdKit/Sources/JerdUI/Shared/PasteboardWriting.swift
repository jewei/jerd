/// Writes text to the general pasteboard. JerdLive implements it with `NSPasteboard`.
@MainActor
public protocol PasteboardWriting: AnyObject {
    func write(_ text: String)
}
