import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("Command-line tools model")
@MainActor
struct CommandLineToolsModelTests {
    @Test("Install asks first, then shows the report and the new state")
    func installAfterConfirmation() async {
        let port = InMemoryCommandLineTools(state: .outdated)
        let model = CommandLineToolsModel(port: port)
        await model.load()
        #expect(model.actionTitle == "Update Command-Line Tools…")
        model.requestInstall()
        #expect(model.isConfirming)
        #expect(await port.installCount == 0)
        await model.install()?.value
        #expect(!model.isConfirming)
        #expect(model.report == InMemoryCommandLineTools.report)
        #expect(model.state == .installed)
    }

    @Test("A failed install shows its reason and no report")
    func installFailure() async {
        let port = InMemoryCommandLineTools()
        await port.configure { $0.failure = "~/.zshrc is a symbolic link. Add the PATH block yourself." }
        let model = CommandLineToolsModel(port: port)
        await model.load()
        await model.install()?.value
        #expect(model.operation.failureMessage == "~/.zshrc is a symbolic link. Add the PATH block yourself.")
        #expect(model.report.isEmpty)
        #expect(model.state == .notInstalled)
    }

    @Test("Nothing installs before the state is known")
    func waitsForState() {
        let model = CommandLineToolsModel(port: InMemoryCommandLineTools())
        #expect(!model.canInstall)
        #expect(model.install() == nil)
    }
}
