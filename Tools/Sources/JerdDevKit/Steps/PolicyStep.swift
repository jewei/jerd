/// Checks every repository policy and reports all findings before it fails.
enum PolicyStep {
    static func run(_ context: DevContext, policies: [RepositoryPolicy] = RepositoryPolicy.all) throws {
        var failedPolicies: [String] = []
        for policy in policies {
            let findings: [PolicyFinding]
            do {
                findings = try policy.findings(context.repository)
            } catch let failure as DevFailure {
                findings = [PolicyFinding(file: policy.title, message: failure.message)]
            }
            if findings.isEmpty {
                context.console.success(policy.title)
            } else {
                failedPolicies.append(policy.title)
                findings.forEach { context.console.error($0.description) }
            }
        }
        guard failedPolicies.isEmpty else {
            throw DevFailure.checkFailed("These policies failed: \(failedPolicies.joined(separator: "; ")).")
        }
    }
}
