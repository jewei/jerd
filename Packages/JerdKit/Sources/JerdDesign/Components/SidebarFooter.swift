import SwiftUI

/// The one sidebar footer pattern: an Add button (or Add menu) on the leading side and an
/// optional caption, such as "2 sites · 1 running", on the trailing side.
/// Place it with `.safeAreaInset(edge: .bottom)` on the sidebar list.
public struct SidebarFooter<MenuItems: View>: View {
    private let addTitle: String
    private let caption: String?
    private let action: (@MainActor () -> Void)?
    private let menuItems: MenuItems

    /// A footer whose Add control opens a menu, for example "Add site…" and "Add tunnel…".
    public init(addTitle: String, caption: String? = nil, @ViewBuilder menu: () -> MenuItems) {
        self.addTitle = addTitle
        self.caption = caption
        self.action = nil
        self.menuItems = menu()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: Spacing.small) {
                addControl
                Spacer(minLength: Spacing.small)
                if let caption {
                    Text(caption)
                        .textRole(.caption)
                        .monospacedDigit()
                        .lineLimit(1)
                        .help(caption)
                }
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small)
        }
    }

    @ViewBuilder private var addControl: some View {
        if let action {
            Button(action: action) { addLabel }
                .buttonStyle(.borderless)
                .help(addTitle)
                .accessibilityLabel(addTitle)
        } else {
            Menu {
                menuItems
            } label: {
                addLabel
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .help(addTitle)
            .accessibilityLabel(addTitle)
        }
    }

    private var addLabel: some View {
        Image(systemName: "plus")
            .font(.body.weight(.medium))
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
    }
}

extension SidebarFooter where MenuItems == EmptyView {
    /// A footer whose Add control performs one action, for example "Add service…".
    public init(addTitle: String, caption: String? = nil, action: @escaping @MainActor () -> Void) {
        self.addTitle = addTitle
        self.caption = caption
        self.action = action
        self.menuItems = EmptyView()
    }
}
