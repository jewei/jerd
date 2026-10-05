import SwiftUI

/// A page with a fixed header and a scrolling grouped form. The header, banners, and form
/// sections share one centered column (see `PageMetrics`), at every window width.
public struct FormPage<Header: View, Messages: View, Content: View>: View {
    private let header: Header
    private let messages: Messages
    private let content: Content

    /// - Parameters:
    ///   - header: Usually a `PageHeader`.
    ///   - messages: Page banners, usually `InlineMessage` with the banner style. They stay
    ///     visible while the form scrolls.
    ///   - content: Form sections.
    public init(
        @ViewBuilder header: () -> Header, @ViewBuilder messages: () -> Messages,
        @ViewBuilder content: () -> Content
    ) {
        self.header = header()
        self.messages = messages()
        self.content = content()
    }

    public var body: some View {
        GeometryReader { geometry in
            let columns = PageMetrics.columns(forWidth: geometry.size.width)
            VStack(spacing: 0) {
                PageTop(columns: columns, header: header, messages: messages)
                // The form draws no background of its own, so the header, the form, and
                // other page kinds all show one window background.
                Form { content }
                    .formStyle(.grouped)
                    .scrollContentBackground(.hidden)
                    .contentMargins(.horizontal, columns.formMargin, for: .scrollContent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

extension FormPage where Messages == EmptyView {
    public init(@ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self.init(header: header, messages: { EmptyView() }, content: content)
    }
}
