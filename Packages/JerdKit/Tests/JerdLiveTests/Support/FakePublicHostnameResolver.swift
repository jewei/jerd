import JerdTunnels

/// Answers each lookup with one status and records the hostnames.
actor FakePublicHostnameResolver: PublicHostnameResolving {
    let answer: PublicHostnameStatus
    private(set) var hostnames: [String] = []

    init(answer: PublicHostnameStatus) {
        self.answer = answer
    }

    func status(of hostname: String) async -> PublicHostnameStatus {
        hostnames.append(hostname)
        return answer
    }
}
