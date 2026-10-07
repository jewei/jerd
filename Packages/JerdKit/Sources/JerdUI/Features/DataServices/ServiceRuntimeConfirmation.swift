import SwiftUI

/// The question before an on-demand runtime installation of a service page (RustFS, Mailpit): the
/// title, the facts, and the confirm button of `ServiceRuntimeCopy`. Cancel clears the request;
/// nothing downloads before the confirm. The Storage and Mail pages share it.
struct ServiceRuntimeConfirmation: ViewModifier {
    let copy: ServiceRuntimeCopy
    let request: ServiceRuntimeRequest?
    let confirm: @MainActor () -> Void
    let dismiss: @MainActor () -> Void
    @Environment(\.isQuitting) private var isQuitting

    func body(content: Content) -> some View {
        content.confirmationDialog(
            request.map(copy.confirmationTitle) ?? "", isPresented: isPresented, titleVisibility: .visible,
            presenting: request
        ) { request in
            Button(copy.confirmTitle(request)) { confirm() }
                .disabled(isQuitting)
            Button("Cancel", role: .cancel) { dismiss() }
        } message: { request in
            Text(copy.confirmationMessage(request))
        }
    }

    private var isPresented: Binding<Bool> {
        Binding {
            request != nil
        } set: { isPresented in
            if !isPresented { dismiss() }
        }
    }
}

extension View {
    /// Asks before the runtime installation that `request` names.
    func serviceRuntimeConfirmation(
        _ copy: ServiceRuntimeCopy, request: ServiceRuntimeRequest?, confirm: @escaping @MainActor () -> Void,
        dismiss: @escaping @MainActor () -> Void
    ) -> some View {
        modifier(ServiceRuntimeConfirmation(copy: copy, request: request, confirm: confirm, dismiss: dismiss))
    }
}
