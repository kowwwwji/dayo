import Foundation

extension RecurrenceSpec {
    private static let weekdayNames = ["", "日", "月", "火", "水", "木", "金", "土"]

    /// 「毎週月水曜」「毎月最終金曜」のような日本語の説明。チップとエディタで使う。
    public var localizedDescription: String {
        switch frequency {
        case .daily:
            return interval == 1 ? "毎日" : "\(interval)日ごと"
        case .weekly:
            if weekdays == [2, 3, 4, 5, 6] { return "平日" }
            let prefix = interval == 2 ? "隔週" : interval == 1 ? "毎週" : "\(interval)週ごと"
            let days = weekdays.compactMap { Self.weekdayNames.indices.contains($0) ? Self.weekdayNames[$0] : nil }.joined()
            return days.isEmpty ? prefix : "\(prefix)\(days)曜"
        case .monthly:
            let prefix = interval == 1 ? "毎月" : "\(interval)か月ごと"
            if !daysOfMonth.isEmpty {
                return prefix + daysOfMonth.map { "\($0)日" }.joined(separator: "・")
            }
            guard let weekday = weekdays.first, Self.weekdayNames.indices.contains(weekday), let week = weekOfMonth else {
                return prefix
            }
            let ordinal = week == -1 ? "最終" : "第\(week)"
            return "\(prefix)\(ordinal)\(Self.weekdayNames[weekday])曜"
        }
    }
}
