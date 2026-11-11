import Foundation

/// 日本語 1 行のルールベースパーサー。
/// 要素ごとの正規表現を「リスト・種別 → 繰り返し → 時間帯 → 日付 → 時刻」の順に当て、
/// マッチした部分を取り除いた残りをタイトルにする。順序は曖昧さを減らすため
/// （`#月曜会議` のリスト名を日付に取られないよう先にリストを、「毎月15日」を日付の「15日」より先に、
/// 「10時-11時」を単独の時刻より先に取る）。
public struct JapaneseInputParser: InputParser {
    /// 時刻を表す語の既定値。
    public struct Options: Equatable, Sendable {
        public var morning = DateComponents(hour: 8, minute: 0)
        public var noon = DateComponents(hour: 12, minute: 0)
        public var evening = DateComponents(hour: 20, minute: 0)

        public init() {}
    }

    public var options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    public func parse(_ text: String, reference: Date, calendar: Calendar) -> ParsedInput {
        var cursor = Cursor(text: Self.normalize(text))
        let dates = DateResolver(reference: reference, calendar: calendar)
        var result = ParsedInput(title: "")

        if let list = cursor.take(Pattern.list) {
            result.listName = list.group(1)
        }
        if let marker = cursor.take(Pattern.eventMarker) {
            result.kind = .event
            // 「@予定」は既定カレンダーへ。それ以外の「@個人的」はカレンダー名の指定
            if let name = marker.group(1), name != "予定" {
                result.listName = name
            }
        }
        result.recurrence = Self.takeRecurrence(&cursor)
        if let range = Self.takeTimeRange(&cursor) {
            result.time = range.start
            result.endTime = range.end
            result.kind = .event
        }
        result.date = Self.takeDate(&cursor, dates)
        if result.time == nil {
            result.time = takeTime(&cursor)
        }
        result.title = cursor.title
        return result
    }

    // MARK: - 繰り返し

    private static func takeRecurrence(_ cursor: inout Cursor) -> RecurrenceSpec? {
        if cursor.take(Pattern.daily) != nil {
            return RecurrenceSpec(frequency: .daily)
        }
        if cursor.take(Pattern.weekdaysOnly) != nil {
            return RecurrenceSpec(frequency: .weekly, weekdays: [2, 3, 4, 5, 6])
        }
        if let m = cursor.take(Pattern.weekly) {
            let interval = m.group(1) == "隔週" ? 2 : 1
            let letters = m.group(2) ?? m.group(3) ?? ""
            return RecurrenceSpec(frequency: .weekly, interval: interval, weekdays: weekdays(letters))
        }
        if let m = cursor.take(Pattern.monthlyWeekday) {
            let week = m.group(2) != nil ? -1 : Int(m.group(1) ?? "") ?? 1
            return RecurrenceSpec(frequency: .monthly, weekdays: weekdays(m.group(3) ?? ""), weekOfMonth: week)
        }
        if let m = cursor.take(Pattern.monthlyDay, where: { (1...31).contains(Int($0.group(1) ?? "") ?? 0) }) {
            return RecurrenceSpec(frequency: .monthly, daysOfMonth: [Int(m.group(1)!)!])
        }
        if let m = cursor.take(Pattern.everyNDays, where: { (Int($0.group(1) ?? "") ?? 0) >= 1 }) {
            return RecurrenceSpec(frequency: .daily, interval: Int(m.group(1)!)!)
        }
        return nil
    }

    private static let weekdayTable: [Character: Int] = [
        "日": 1, "月": 2, "火": 3, "水": 4, "木": 5, "金": 6, "土": 7,
    ]

    private static func weekdays(_ letters: String) -> [Int] {
        letters.compactMap { weekdayTable[$0] }
    }

    // MARK: - 時刻

    private static func takeTimeRange(_ cursor: inout Cursor) -> (start: DateComponents, end: DateComponents)? {
        guard let m = cursor.take(Pattern.timeRange, where: { m in
            time(from: m, offset: 0) != nil && time(from: m, offset: 5) != nil
        }) else { return nil }
        let start = time(from: m, offset: 0)!
        var end = time(from: m, offset: 5)!
        // 「午後1時-3時」のように終了側だけ午前/午後が無く開始より前なら午後に寄せる
        if m.group(6) == nil, let s = start.hour, let e = end.hour, e < s, e + 12 > s, e + 12 < 24 {
            end.hour = e + 12
        }
        return (start, end)
    }

    private func takeTime(_ cursor: inout Cursor) -> DateComponents? {
        if let m = cursor.take(Pattern.time, where: { Self.time(from: $0, offset: 0) != nil }) {
            return Self.time(from: m, offset: 0)
        }
        if let m = cursor.take(Pattern.timeWord) {
            switch m.group(1) {
            case "朝": return options.morning
            case "昼": return options.noon
            default: return options.evening
            }
        }
        return nil
    }

    /// `Pattern.timeBody` のキャプチャ（午前午後, 時, :分, 分, 半）から時分を作る。範囲外なら nil。
    private static func time(from m: Cursor.Match, offset: Int) -> DateComponents? {
        guard var hour = Int(m.group(offset + 2) ?? "") else { return nil }
        let minute: Int
        if let colon = m.group(offset + 3) {
            minute = Int(colon) ?? 0
        } else if let written = m.group(offset + 4) {
            minute = Int(written) ?? 0
        } else if m.group(offset + 5) != nil {
            minute = 30
        } else {
            minute = 0
        }
        switch m.group(offset + 1) {
        case "午後": if hour < 12 { hour += 12 }
        case "午前": if hour == 12 { hour = 0 }
        default: break
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return DateComponents(hour: hour, minute: minute)
    }

    // MARK: - 日付

    private static func takeDate(_ cursor: inout Cursor, _ dates: DateResolver) -> DateComponents? {
        if let m = cursor.take(Pattern.relativeDay) {
            switch m.group(1) {
            case "今日": return dates.daysFromToday(0)
            case "明日", "あした": return dates.daysFromToday(1)
            default: return dates.daysFromToday(2)
            }
        }
        if let m = cursor.take(Pattern.nextWeekWeekday) {
            let weeks = m.group(1) == "再来週" ? 2 : 1
            return dates.weekday(weekdays(m.group(2) ?? "").first ?? 1, weeksAhead: weeks)
        }
        if let m = cursor.take(Pattern.weekday) {
            return dates.upcoming(weekday: weekdays(m.group(1) ?? "").first ?? 1)
        }
        if let m = cursor.take(Pattern.monthSlashDay, where: { dates.monthDay(Int($0.group(1)!)!, Int($0.group(2)!)!) != nil }) {
            return dates.monthDay(Int(m.group(1)!)!, Int(m.group(2)!)!)
        }
        if let m = cursor.take(Pattern.monthDay, where: { dates.monthDay(Int($0.group(1)!)!, Int($0.group(2)!)!) != nil }) {
            return dates.monthDay(Int(m.group(1)!)!, Int(m.group(2)!)!)
        }
        if let m = cursor.take(Pattern.daysLater) {
            return dates.daysFromToday(Int(m.group(1)!)!)
        }
        if let m = cursor.take(Pattern.dayOfMonth, where: { dates.dayOfMonth(Int($0.group(1)!)!) != nil }) {
            return dates.dayOfMonth(Int(m.group(1)!)!)
        }
        return nil
    }

    /// 相対表現を参照日基準の年月日に解決する。
    private struct DateResolver {
        let reference: Date
        let calendar: Calendar

        private var today: Date { calendar.startOfDay(for: reference) }

        func daysFromToday(_ days: Int) -> DateComponents? {
            calendar.date(byAdding: .day, value: days, to: today).map(ymd)
        }

        /// 今日以降で最初のその曜日（今日を含む）。
        func upcoming(weekday: Int) -> DateComponents? {
            first(weekday: weekday, onOrAfter: today).map(ymd)
        }

        /// 来週（1）・再来週（2）のその曜日。週の始まりは Calendar の設定に従う。
        func weekday(_ weekday: Int, weeksAhead: Int) -> DateComponents? {
            guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: reference),
                  let weekStart = calendar.date(byAdding: .weekOfYear, value: weeksAhead, to: thisWeek.start)
            else { return nil }
            return first(weekday: weekday, onOrAfter: weekStart).map(ymd)
        }

        /// 月日。過去なら翌年以降。2/29 のように存在しない年は飛ばす。
        func monthDay(_ month: Int, _ day: Int) -> DateComponents? {
            let year = calendar.component(.year, from: today)
            for candidateYear in year...(year + 4) {
                guard let date = exactDate(year: candidateYear, month: month, day: day) else { continue }
                if date >= today { return ymd(date) }
            }
            return nil
        }

        /// 日のみ。今月のその日が過ぎていれば、その日が存在する次の月。
        func dayOfMonth(_ day: Int) -> DateComponents? {
            for offset in 0..<12 {
                guard let monthStart = calendar.date(byAdding: .month, value: offset, to: startOfMonth),
                      let date = exactDate(
                        year: calendar.component(.year, from: monthStart),
                        month: calendar.component(.month, from: monthStart),
                        day: day
                      )
                else { continue }
                if date >= today { return ymd(date) }
            }
            return nil
        }

        private var startOfMonth: Date {
            calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        }

        private func first(weekday: Int, onOrAfter start: Date) -> Date? {
            for offset in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
                if calendar.component(.weekday, from: date) == weekday { return date }
            }
            return nil
        }

        /// 桁あふれで繰り上がった日付（11/31 → 12/1）を弾く。
        private func exactDate(year: Int, month: Int, day: Int) -> Date? {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  calendar.component(.day, from: date) == day,
                  calendar.component(.month, from: date) == month
            else { return nil }
            return date
        }

        private func ymd(_ date: Date) -> DateComponents {
            calendar.dateComponents([.year, .month, .day], from: date)
        }
    }

    // MARK: - 正規表現

    private enum Pattern {
        static let weekdayLetters = "[日月火水木金土]"
        static let weekdaySuffix = "(?:曜日|曜)"
        /// 語の区切り（空白か末尾）。「毎週日報」の「日」を曜日に取らないために使う。
        static let boundary = "(?=\\s|$)"
        /// キャプチャ: 1 午前午後, 2 時, 3 コロン分, 4 「分」の分, 5 半
        static let clock = "(?::(\\d{2})|時(?:(\\d{1,2})分|(半))?)"
        static let timeBody = "(午前|午後)?\\s*(\\d{1,2})\(clock)"
        /// 時間帯の開始側は「10-11時」のように時を省ける
        static let rangeStartBody = "(午前|午後)?\\s*(\\d{1,2})\(clock)?"
        /// 「3時間」「15時間後」を時刻に取らない
        static let notDuration = "(?![\\d:間])"

        static let daily = regex("毎日")
        static let weekdaysOnly = regex("平日")
        static let weekly = regex(
            "(毎週|隔週)(?:(\(weekdayLetters)+)\(weekdaySuffix)|(\(weekdayLetters)+)\(boundary)|\(boundary))"
        )
        static let monthlyWeekday = regex("毎月(?:第([1-5])|(最終))(\(weekdayLetters))\(weekdaySuffix)?")
        static let monthlyDay = regex("毎月(\\d{1,2})日(?![\\d間])")
        static let everyNDays = regex("(\\d{1,2})日ごと")

        static let rangeSeparator = "\\s*(?:[-〜～~]|から)\\s*"
        static let timeRange = regex("(?<![\\d:/])\(rangeStartBody)\(rangeSeparator)\(timeBody)\(notDuration)に?")
        static let time = regex("(?<![\\d:/])\(timeBody)\(notDuration)に?")
        static let timeWord = regex("(?:^|(?<=\\s))(朝|昼|夜)(?:に)?\(boundary)")

        static let relativeDay = regex("(明後日|あさって|明日|あした|今日)(?:の|に)?")
        static let nextWeekWeekday = regex("(再来週|来週)の?(\(weekdayLetters))\(weekdaySuffix)?(?:に)?")
        static let weekday = regex("(?:今週の?)?(\(weekdayLetters))\(weekdaySuffix)(?:に)?")
        static let monthSlashDay = regex("(?<![\\d/])(\\d{1,2})/(\\d{1,2})(?![\\d/])(?:に)?")
        static let monthDay = regex("(?<!\\d)(\\d{1,2})月(\\d{1,2})日(?![\\d間])(?:に)?")
        static let daysLater = regex("(?<!\\d)(\\d{1,3})日後(?:の|に)?")
        static let dayOfMonth = regex("(?<![\\d月])(\\d{1,2})日(?![\\d後ご間目中])(?:に)?")

        static let list = regex("#(\\S+)")
        static let eventMarker = regex("@(\\S+)")

        private static func regex(_ pattern: String) -> NSRegularExpression {
            // パターンは定数なので失敗は実装ミス
            try! NSRegularExpression(pattern: pattern)
        }
    }

    /// 入力文字列からマッチ部分を順に取り除いていく。
    private struct Cursor {
        struct Match {
            let groups: [String?]
            func group(_ index: Int) -> String? { index < groups.count ? groups[index] : nil }
        }

        private var text: String

        init(text: String) {
            self.text = text
        }

        /// 最初のマッチを取り除いて返す。`where` を満たさないマッチは残す。
        mutating func take(_ pattern: NSRegularExpression, where accept: (Match) -> Bool = { _ in true }) -> Match? {
            let ns = text as NSString
            let matches = pattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
            for result in matches {
                let groups = (0..<result.numberOfRanges).map { index -> String? in
                    let range = result.range(at: index)
                    return range.location == NSNotFound ? nil : ns.substring(with: range)
                }
                let match = Match(groups: groups)
                guard accept(match) else { continue }
                text = ns.replacingCharacters(in: result.range, with: " ")
                return match
            }
            return nil
        }

        /// 残りを空白 1 つ区切りに正規化したタイトル。
        var title: String {
            text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
    }

    /// 全角の数字・記号を半角に寄せる。カナは触らない。
    static func normalize(_ text: String) -> String {
        String(text.map { character -> Character in
            switch character {
            case "０"..."９":
                let offset = character.unicodeScalars.first!.value - ("０" as Unicode.Scalar).value
                return Character(Unicode.Scalar(("0" as Unicode.Scalar).value + offset)!)
            case "：": return ":"
            case "／": return "/"
            case "＃": return "#"
            case "＠": return "@"
            case "　": return " "
            case "－", "−", "–", "—", "‐": return "-"
            default: return character
            }
        })
    }
}
