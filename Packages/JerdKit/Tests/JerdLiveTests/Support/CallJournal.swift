/// The calls of several fakes in one order, so a test can prove the order across them.
actor CallJournal {
    private(set) var entries: [String] = []

    func record(_ entry: String) {
        entries.append(entry)
    }
}
