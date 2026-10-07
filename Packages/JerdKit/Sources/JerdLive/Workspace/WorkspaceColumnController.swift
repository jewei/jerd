import AppKit

/// One column of the main window's split. Its view fills the whole column, also under the
/// unified toolbar, and draws nothing; the hosted SwiftUI content stays inside the safe area,
/// so fixed page headers and the first sidebar row start below the toolbar.
@MainActor
final class WorkspaceColumnController: NSViewController {
    private let content: NSViewController

    init(content: NSViewController) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        view = NSView()
        addChild(content)
        view.addSubview(content.view)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        content.view.frame = view.safeAreaRect
    }
}
