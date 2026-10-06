import Foundation

/// The folder name of one shell backup: `YYYYmmdd-HHMMSS-ffffff` in local time, with microseconds.
///
/// The form is the compatibility contract of `shell-backups/` with older setups.
enum ShellBackupName {
    static func folderName(for date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let microseconds = Int64((date.timeIntervalSince1970 * 1_000_000).rounded(.down)) % 1_000_000
        let day = pad(parts.year, 4) + pad(parts.month, 2) + pad(parts.day, 2)
        let time = pad(parts.hour, 2) + pad(parts.minute, 2) + pad(parts.second, 2)
        return "\(day)-\(time)-\(pad(Int(microseconds), 6))"
    }

    private static func pad(_ value: Int?, _ width: Int) -> String {
        let text = String(value ?? 0)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}
