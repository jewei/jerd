/// Lets other work run until `condition` is true, or gives up after about two seconds.
/// Tests then check the state, so a missed condition fails the test instead of hanging it.
@MainActor
func waitUntil(_ condition: @MainActor () -> Bool) async {
    for turn in 0..<2_000 where !condition() {
        await Task.yield()
        if turn > 50 {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}
