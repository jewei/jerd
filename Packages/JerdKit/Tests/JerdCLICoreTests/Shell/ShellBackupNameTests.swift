import Foundation
import Testing

@testable import JerdCLICore

@Suite struct ShellBackupNameTests {
    private let utc = TimeZone(identifier: "UTC") ?? .current

    @Test func nameHasDateTimeAndMicroseconds() {
        // 2026-03-04 05:06:07.089123 UTC
        let date = Date(timeIntervalSince1970: 1_772_600_767.089_123)
        #expect(ShellBackupName.folderName(for: date, timeZone: utc) == "20260304-050607-089123")
    }

    @Test func nameUsesTheGivenTimeZone() {
        let date = Date(timeIntervalSince1970: 1_772_600_767)
        let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? utc
        #expect(ShellBackupName.folderName(for: date, timeZone: tokyo) == "20260304-140607-000000")
    }
}
