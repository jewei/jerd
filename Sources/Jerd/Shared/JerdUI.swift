import SwiftUI
import JerdCore

/// Keep the sidebar control in one toolbar position while the columns resize.
struct JerdSplitView<Sidebar: View, Detail: View>: View {
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder var sidebar: Sidebar
    @ViewBuilder var detail: Detail

    private var sidebarAction: String {
        columnVisibility == .detailOnly ? "Show sidebar" : "Hide sidebar"
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar.toolbar(removing: .sidebarToggle)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(sidebarAction, systemImage: "sidebar.left") {
                    var transaction = Transaction(animation: reduceMotion ? nil : .easeInOut(duration: 0.25))
                    transaction.disablesAnimations = reduceMotion
                    withTransaction(transaction) {
                        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                    }
                }
                .help(sidebarAction)
            }
        }
    }
}

/// Shared visual vocabulary for service state. Each tone has a distinct symbol,
/// so state never depends on color alone.
enum StatusTone {
    case ready, busy, idle, failed, attention

    var color: Color {
        switch self {
        case .ready: .green
        case .busy: .orange
        case .idle: .secondary
        case .failed: .red
        case .attention: .orange
        }
    }

    var symbol: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .busy: "clock"
        case .idle: "stop.circle"
        case .failed: "exclamationmark.triangle.fill"
        case .attention: "exclamationmark.circle.fill"
        }
    }

    static func service(running: Bool, busy: Bool, failed: Bool) -> StatusTone {
        if failed { return .failed }
        if busy { return .busy }
        return running ? .ready : .idle
    }
}

extension EnvironmentState {
    var tone: StatusTone {
        switch self {
        case .running: .ready
        case .starting: .busy
        case .stopped: .idle
        case .setupRequired: .attention
        case .failed: .failed
        }
    }
}

extension DatabaseState {
    var tone: StatusTone {
        if case .failed = self { return .failed }
        return .service(running: self == .running, busy: isBusy, failed: false)
    }
}

extension MailState {
    var tone: StatusTone {
        if case .failed = self { return .failed }
        return .service(running: self == .running, busy: self == .starting || self == .stopping, failed: false)
    }
}

extension StorageState {
    var tone: StatusTone {
        if case .failed = self { return .failed }
        return .service(running: self == .running, busy: self == .starting || self == .stopping, failed: false)
    }
}

/// Capsule badge for page headers and cards.
struct StatusBadge: View {
    let title: String
    let tone: StatusTone

    var body: some View {
        HStack(spacing: 5) {
            if tone == .busy {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: tone.symbol).foregroundStyle(tone.color)
            }
            Text(title).foregroundStyle(.primary)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(tone.color.opacity(tone == .idle ? 0.12 : 0.16), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status")
        .accessibilityValue(title)
    }
}

/// Compact indicator for sidebar rows.
struct StatusIndicator: View {
    let title: String
    let tone: StatusTone

    var body: some View {
        Group {
            if tone == .busy {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: tone.symbol).foregroundStyle(tone.color)
            }
        }
        .font(.callout)
        .frame(width: 16)
        .help(title)
        .accessibilityLabel("Status")
        .accessibilityValue(title)
    }
}

/// Two-line sidebar row with a trailing status indicator.
struct SidebarRow: View {
    let title: String
    let subtitle: String
    let status: String
    let tone: StatusTone
    var dimmed = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium).foregroundStyle(dimmed ? .secondary : .primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            StatusIndicator(title: status, tone: tone)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

/// Fixed header above a scrolling pane: title, status, summary, and primary actions.
struct PaneHeader<Actions: View>: View {
    let title: String
    var subtitle: String?
    var status: (title: String, tone: StatusTone)?
    @ViewBuilder var actions: Actions

    init(_ title: String, subtitle: String? = nil, status: (title: String, tone: StatusTone)? = nil,
         @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.title = title; self.subtitle = subtitle; self.status = status; self.actions = actions()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                titleBlock
                Spacer(minLength: 0)
                actionRow
            }
            VStack(alignment: .leading, spacing: 12) {
                titleBlock
                actionRow
            }
        }
        .padding(.horizontal, 30).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                Text(title).font(.title2.bold())
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
                if let status { StatusBadge(title: status.title, tone: status.tone) }
            }
            if let subtitle {
                Text(subtitle).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) { actions }.fixedSize()
    }
}

extension View {
    /// Uses the prominent style only while the action is available, so a disabled
    /// control never looks like the next step.
    func primaryAction(_ enabled: Bool) -> some View {
        buttonStyle(.borderedProminent).tint(enabled ? nil : Color.secondary).disabled(!enabled)
    }
}

/// Inline message with an icon, so meaning does not depend on color alone.
struct InlineMessage: View {
    enum Kind { case error, info, success }
    let text: String
    var kind: Kind = .error

    init(_ text: String, kind: Kind = .error) { self.text = text; self.kind = kind }

    var body: some View {
        Label {
            Text(text).foregroundStyle(kind == .error ? Color.primary : Color.secondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var symbol: String {
        switch kind {
        case .error: "exclamationmark.triangle.fill"
        case .info: "info.circle"
        case .success: "checkmark.circle.fill"
        }
    }
    private var color: Color {
        switch kind {
        case .error: .red
        case .info: .secondary
        case .success: .green
        }
    }
}

/// Selectable label/value row for grouped forms. Long values truncate in the middle
/// and show the full value in a tooltip.
struct ValueRow: View {
    let label: String
    let value: String
    var monospaced = false

    init(_ label: String, _ value: String, monospaced: Bool = false) {
        self.label = label; self.value = value; self.monospaced = monospaced
    }

    var body: some View {
        LabeledContent(label) {
            Text(value)
                .font(monospaced ? .body.monospaced() : .body)
                .lineLimit(1).truncationMode(.middle)
                .textSelection(.enabled)
                .help(value)
        }
    }
}

/// Row with a title, optional detail, and trailing controls. Unlike LabeledContent,
/// it keeps each control's own accessibility name.
struct ControlRow<Controls: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var controls: Controls

    init(_ title: String, detail: String? = nil, @ViewBuilder controls: () -> Controls) {
        self.title = title; self.detail = detail; self.controls = controls()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) { controls }.fixedSize()
        }
    }
}

/// Label/value row with a trailing action button.
struct ActionRow<Value: View>: View {
    let label: String
    let action: String
    var symbol: String?
    let perform: () -> Void
    @ViewBuilder var value: Value

    init(_ label: String, action: String, symbol: String? = nil, perform: @escaping () -> Void,
         @ViewBuilder value: () -> Value = { EmptyView() }) {
        self.label = label; self.action = action; self.symbol = symbol; self.perform = perform; self.value = value()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
            Spacer(minLength: 12)
            value
            Group {
                if let symbol { Button(action, systemImage: symbol, action: perform) }
                else { Button(action, action: perform) }
            }.fixedSize()
        }
    }
}

/// Path row: middle-truncated, selectable path with a Finder action.
struct PathRow: View {
    let label: String
    let path: String
    var action = "Show in Finder"
    let reveal: () -> Void

    var body: some View {
        ActionRow(label, action: action, perform: reveal) {
            Text(path).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled).help(path)
        }
    }
}

/// Common layout for pages: fixed header, divider, grouped form, and an optional
/// confirmation toast that does not move the content.
struct GroupedPane<Header: View, Content: View>: View {
    var feedback: String?
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    init(feedback: String? = nil, @ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self.feedback = feedback; self.header = header(); self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Match the readable width of grouped forms, so the header and the
            // sections stay aligned in wide windows.
            header.frame(maxWidth: 744).frame(maxWidth: .infinity)
            Divider()
            Form { content }
                .formStyle(.grouped)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            ZStack {
                if let feedback {
                    Label(feedback, systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.separator))
                        .padding(.bottom, 16)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: feedback)
        }
        .onChange(of: feedback) { _, message in
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
    }
}

/// Common sheet layout: title, optional explanation, grouped form, and a footer.
struct SheetScaffold<Content: View, Footer: View>: View {
    let title: String
    var message: String?
    var width: CGFloat = 520
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.title3.bold()).accessibilityAddTraits(.isHeader)
                if let message { Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            .padding(.horizontal, 20).padding(.top, 20)
            Form { content }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            Divider()
            HStack(spacing: 8) { footer }
                .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: width)
    }
}
