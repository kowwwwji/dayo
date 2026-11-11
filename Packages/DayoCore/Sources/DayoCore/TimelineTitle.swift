import Foundation

/// ウィンドウや画面のタイトルに出す日付。日表示は「2026 / 11 / 10 (火) W46」、
/// 3 日表示は「2026 / 11 / 11 (水) – 13 (金) W46」、週表示は「2026 / 11  W46」の形。
/// 年は西暦（システムが和暦でも）。週番号は ISO 8601（月曜始まり）で、`showsWeekNumber` で消せる。
public enum TimelineTitle {
    public static func text(
        for day: Date, showsWeekNumber: Bool, timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        text(forDays: [day], showsWeekNumber: showsWeekNumber, timeZone: timeZone)
    }

    /// 連続した日の並びのタイトル（最初の日 – 最後の日）。最後の日の年と月は、最初の日と違うときだけ書く。
    /// 週番号は、並びが 2 つの週にまたがるときだけ両方書く。
    public static func text(
        forDays days: [Date], showsWeekNumber: Bool, timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        let calendar = gregorian(in: timeZone)
        let from = calendar.dateComponents([.year, .month, .day, .weekday], from: first)
        let to = calendar.dateComponents([.year, .month, .day, .weekday], from: last)
        var text = "\(from.year ?? 0) / \(from.month ?? 0) / \(from.day ?? 0) (\(weekday(from)))"
        if first != last {
            var end = "\(to.day ?? 0) (\(weekday(to)))"
            if from.year != to.year {
                end = "\(to.year ?? 0) / \(to.month ?? 0) / " + end
            } else if from.month != to.month {
                end = "\(to.month ?? 0) / " + end
            }
            text += " – " + end
        }
        if showsWeekNumber {
            let firstWeek = week(of: first, in: timeZone), lastWeek = week(of: last, in: timeZone)
            text += firstWeek == lastWeek ? " W\(firstWeek)" : " W\(firstWeek)–\(lastWeek)"
        }
        return text
    }

    /// 週表示のタイトル。年月は週の最初の日のもの。
    /// 週番号は週の中の木曜で決める（ISO の週は木曜が属する週。日曜始まりの週でも月〜土と同じ番号になる）。
    public static func text(
        forWeek days: [Date], showsWeekNumber: Bool, timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        guard let first = days.first else { return "" }
        let calendar = gregorian(in: timeZone)
        let parts = calendar.dateComponents([.year, .month], from: first)
        var text = "\(parts.year ?? 0) / \(parts.month ?? 0)"
        if showsWeekNumber {
            let thursday = days.first { calendar.component(.weekday, from: $0) == 5 } ?? first
            text += "  W\(week(of: thursday, in: timeZone))"
        }
        return text
    }

    private static let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    private static func weekday(_ parts: DateComponents) -> String {
        parts.weekday.flatMap { weekdays.indices.contains($0 - 1) ? weekdays[$0 - 1] : nil } ?? ""
    }

    private static func gregorian(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static func week(of day: Date, in timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        return calendar.component(.weekOfYear, from: day)
    }
}
