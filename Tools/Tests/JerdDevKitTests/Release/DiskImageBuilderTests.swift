import Foundation
import Testing

@testable import JerdDevKit

@Suite("Disk image build")
struct DiskImageBuilderTests {
    @Test("The disk image uses LZMA compression, which macOS 14 opens")
    func usesLZMA() {
        let arguments = DiskImageBuilder.createArguments(
            folder: URL(filePath: "/c/disk-image"), image: URL(filePath: "/c/Jerd-0.2.0.dmg"))
        #expect(
            arguments == [
                "create", "-volname", "Jerd", "-srcfolder", "/c/disk-image", "-format", "ULMO", "/c/Jerd-0.2.0.dmg",
            ])
    }
}
