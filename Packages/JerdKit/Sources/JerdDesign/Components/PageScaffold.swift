import SwiftUI

/// A page with a fixed header and free scrolling content, for example dashboard cards.
/// It uses the same column as `FormPage`, so both kinds of page line up.
public struct PageScaffold<Header: View, Messages: View, Content: View>: View {
    private let header: Header
    private let messages: Messages
    private let content: Content

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
                ScrollView {
                    content
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, columns.sectionInset)
                        .padding(.vertical, Spacing.section)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

extension PageScaffold where Messages == EmptyView {
    public init(@ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self.init(header: header, messages: { EmptyView() }, content: content)
    }
}
