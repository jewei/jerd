import AppKit

/// One column of the main window's split. Its background fills the whole column, also under the
/// unified toolbar; the hosted SwiftUI content stays inside the safe area, so fixed page headers
/// and the first sidebar row start below the toolbar.
@MainActor
final class WorkspaceColumnController: NSViewController {
    private let content: NSViewController
    private let background: NSVisualEffectView.Material?

    /// - Parameter background: The material of the column, for example `.sidebar`; nil for the
    ///   window background of the detail column.
    init(content: NSViewController, background: NSVisualEffectView.Material?) {
        self.content = content
        self.background = background
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        if let background {
            let effect = NSVisualEffectView()
            effect.material = background
            effect.blendingMode = .behindWindow
            effect.state = .followsWindowActiveState
            view = effect
        } else {
            view = NSView()
        }
        addChild(content)
        view.addSubview(content.view)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        content.view.frame = view.safeAreaRect
    }
}
