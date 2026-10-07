/// A weak reference to the app state. `AppState.init` gives it to the closures of the models
/// that it builds before `self` exists, and fills it in as its last step.
@MainActor
final class AppStateHandle {
    weak var state: AppState?
}
