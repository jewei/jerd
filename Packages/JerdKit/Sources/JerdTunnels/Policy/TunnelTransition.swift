/// The result of one reduction: the next lifecycle and the step to run.
package struct TunnelTransition: Equatable, Sendable {
    package let lifecycle: TunnelLifecycle
    package let step: TunnelStep

    package init(_ lifecycle: TunnelLifecycle, _ step: TunnelStep) {
        self.lifecycle = lifecycle
        self.step = step
    }
}
