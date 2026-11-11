import Foundation

/// 日付ジャンプの入力欄の読み方。1 行の文字から行き先の日を決める。
public enum DateJump {
    /// 行き先の日（0:00）。日付として読めなければ nil。
    /// 「2026/11/1」のような年付きを先に見て、残りはクイック入力と同じ読み方（「11/20」「来週水曜」「20日」「3日後」）。
    /// クイック入力は年なしの過ぎた日付を次の年・月に読むので、過去へは年付きで行く。
    /// 日付のほかに何か書いてあれば読まない（行き先を取り違えないため）。
    public static func day(
        from text: String, reference: Date, calendar: Calendar, parser: InputParser = JapaneseInputParser()
    ) -> Date? {
        let text = JapaneseInputParser.normalize(text).trimmingCharacters(in: .whitespaces)
        if let match = text.wholeMatch(of: #/(\d{4})[/\-.年](\d{1,2})[/\-.月](\d{1,2})日?/#) {
            let components = DateComponents(year: Int(match.1), month: Int(match.2), day: Int(match.3))
            return existingDay(components, calendar: calendar)
        }
        let parsed = parser.parse(text, reference: reference, calendar: calendar)
        guard let date = parsed.date, parsed.title.isEmpty, parsed.time == nil, parsed.recurrence == nil,
              parsed.listName == nil
        else { return nil }
        return existingDay(date, calendar: calendar)
    }

    /// 暦にある日だけを返す（2/30 を 3/2 に読み替えない）。
    private static func existingDay(_ components: DateComponents, calendar: Calendar) -> Date? {
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(
                  year: components.year, month: components.month, day: components.day
              )
        else { return nil }
        return date
    }
}
