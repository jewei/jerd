import Foundation
import Testing

@testable import JerdDevKit

@Suite("Project comparison")
struct ProjectComparisonTests {
    private let generated: [String: Data] = [
        "project.pbxproj": Data("objects".utf8),
        "xcshareddata/xcschemes/Jerd.xcscheme": Data("scheme".utf8),
    ]

    @Test("finds no difference in identical projects")
    func identicalProjects() {
        #expect(ProjectComparison.differences(generated: generated, committed: generated).isEmpty)
    }

    @Test("reports a changed file, a file that is not committed, and an extra committed file")
    func reportsEveryKind() {
        let committed: [String: Data] = [
            "project.pbxproj": Data("edited".utf8),
            "xcshareddata/xcschemes/Old.xcscheme": Data("old".utf8),
        ]
        #expect(
            ProjectComparison.differences(generated: generated, committed: committed) == [
                .changed("project.pbxproj"),
                .notCommitted("xcshareddata/xcschemes/Jerd.xcscheme"),
                .notGenerated("xcshareddata/xcschemes/Old.xcscheme"),
            ])
    }

    @Test("accepts the committed Package.resolved and personal Xcode files")
    func ignoresExpectedExtraFiles() {
        var committed = generated
        committed["project.xcworkspace/xcshareddata/swiftpm/Package.resolved"] = Data("{}".utf8)
        committed["xcuserdata/jewei.xcuserdatad/xcschemes/xcschememanagement.plist"] = Data()
        committed["project.xcworkspace/xcuserdata/jewei.xcuserdatad/UserInterfaceState.xcuserstate"] = Data()
        committed[".DS_Store"] = Data()
        #expect(ProjectComparison.differences(generated: generated, committed: committed).isEmpty)
    }

    @Test("describes each difference with its path")
    func describesDifferences() {
        #expect(ProjectComparison.Difference.changed("a").description == "a differs from the generated file.")
        #expect(ProjectComparison.Difference.notCommitted("b").description == "b is generated but not committed.")
        #expect(
            ProjectComparison.Difference.notGenerated("c").description
                == "c is committed but XcodeGen does not make it."
        )
    }
}
