import SwiftUI

/// One entry of the menu bar menu. A submenu draws its entries with this view again.
struct MenuBarItemView: View {
    let item: MenuBarItem

    var body: some View {
        switch item.kind {
        case .action(let action):
            actionButton(action)
        case .text(let text):
            Text(text)
        case .submenu(let title, let items):
            Menu(title) {
                ForEach(items) { child in
                    MenuBarItemView(item: child)
                }
            }
        case .divider:
            Divider()
        }
    }

    @ViewBuilder private func actionButton(_ action: FeatureAction) -> some View {
        let button = Button(action.title, action: action.perform)
            .disabled(!action.isEnabled)
        if let shortcut = item.shortcut {
            button.keyboardShortcut(shortcut.keyboardShortcut)
        } else {
            button
        }
    }
}
