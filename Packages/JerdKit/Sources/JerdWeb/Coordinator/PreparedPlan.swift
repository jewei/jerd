import Foundation

/// A one-use proof that a plan passed preflight with these exact executables.
///
/// The coordinator accepts it once, only when it issued it, and only when the plan is equivalent
/// and the executable stamps are unchanged. So a token can wait through an approval without a
/// second preflight (spec B 7.1.8), but it never hides a changed path or a replaced binary.
public struct PreparedPlan: Sendable {
    let id: UUID
    let issuer: UUID
    public let plan: ServingPlan
    let stamps: [String: ExecutableStamp]
}
