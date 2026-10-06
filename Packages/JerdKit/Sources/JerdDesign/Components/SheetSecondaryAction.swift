/// A button on the leading side of a sheet footer, for work inside the sheet that does not end
/// it, for example Inspect Again or Refresh. The HIG keeps such a button apart from the buttons
/// that end the sheet, so the default button stays on the far right.
public struct SheetSecondaryAction {
    public let title: String
    public let isEnabled: Bool
    public let perform: @MainActor () -> Void

    public init(_ title: String, isEnabled: Bool = true, perform: @escaping @MainActor () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.perform = perform
    }
}
