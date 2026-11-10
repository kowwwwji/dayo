import Foundation

/// 繰り返しの規則。EventKit に依存しない表現にし、`EKRecurrenceRule` への変換は Repository で行う。
/// `EKRecurrenceRule` は値として比較できず、パーサーのテーブルテストに使えないため。
public struct RecurrenceSpec: Equatable, Sendable {
    public enum Frequency: Equatable, Sendable {
        case daily
        case weekly
        case monthly
    }

    public var frequency: Frequency
    /// 隔週=2、3日ごと=3。
    public var interval: Int
    /// 1=日 … 7=土（`Calendar.component(.weekday)` と同じ）。weekly なら曜日指定、monthly なら `weekOfMonth` と組で使う。
    public var weekdays: [Int]
    /// 月内の第 n 週。-1 は最終。
    public var weekOfMonth: Int?
    /// 毎月 15 日 = [15]。
    public var daysOfMonth: [Int]

    public init(
        frequency: Frequency,
        interval: Int = 1,
        weekdays: [Int] = [],
        weekOfMonth: Int? = nil,
        daysOfMonth: [Int] = []
    ) {
        self.frequency = frequency
        self.interval = interval
        self.weekdays = weekdays
        self.weekOfMonth = weekOfMonth
        self.daysOfMonth = daysOfMonth
    }

    /// `reference` の日以降で最初に該当する日（0:00）。繰り返しリマインダーの初回期日に使う。
    public func firstOccurrence(onOrAfter reference: Date, calendar: Calendar) -> Date? {
        let start = calendar.startOfDay(for: reference)
        // 毎月 31 日のように該当しない月が続いても 2 年あれば必ず見つかる
        for offset in 0..<(366 * 2) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            if matches(day, calendar: calendar) { return day }
        }
        return nil
    }

    func matches(_ day: Date, calendar: Calendar) -> Bool {
        switch frequency {
        case .daily:
            return true
        case .weekly:
            return weekdays.isEmpty || weekdays.contains(calendar.component(.weekday, from: day))
        case .monthly:
            if !daysOfMonth.isEmpty {
                return daysOfMonth.contains(calendar.component(.day, from: day))
            }
            guard let weekOfMonth, !weekdays.isEmpty else { return true }
            guard weekdays.contains(calendar.component(.weekday, from: day)) else { return false }
            if weekOfMonth > 0 {
                return calendar.component(.weekdayOrdinal, from: day) == weekOfMonth
            }
            guard let nextWeek = calendar.date(byAdding: .day, value: 7, to: day) else { return false }
            return calendar.component(.month, from: nextWeek) != calendar.component(.month, from: day)
        }
    }
}

/// クイック入力 1 行を要素に分解した結果。解釈できなかった語は `title` に残す。
public struct ParsedInput: Equatable {
    public var title: String
    /// 既定は reminder。`@予定` か時間帯があれば event。
    public var kind: ItemKind
    /// year / month / day。参照日で解決済み。
    public var date: DateComponents?
    /// hour / minute。
    public var time: DateComponents?
    /// 「10時-11時」の終了側。event のときだけ意味を持つ。
    public var endTime: DateComponents?
    public var recurrence: RecurrenceSpec?
    /// `#家族` → "家族"。
    public var listName: String?

    public init(
        title: String,
        kind: ItemKind = .reminder,
        date: DateComponents? = nil,
        time: DateComponents? = nil,
        endTime: DateComponents? = nil,
        recurrence: RecurrenceSpec? = nil,
        listName: String? = nil
    ) {
        self.title = title
        self.kind = kind
        self.date = date
        self.time = time
        self.endTime = endTime
        self.recurrence = recurrence
        self.listName = listName
    }
}

/// クイック入力の解釈。後で LLM 実装に差し替えられるよう protocol にしている。
public protocol InputParser {
    /// `reference` は「今日」「金曜」などの相対表現を解決する基準時刻。
    func parse(_ text: String, reference: Date, calendar: Calendar) -> ParsedInput
}

/// 登録に渡す 1 件分。`CalendarSource.create` の入力。
public struct ItemDraft: Equatable {
    public var kind: ItemKind
    public var title: String
    /// event: 開始 / reminder: 期日。期日なしは nil。
    public var start: Date?
    /// event のみ。
    public var end: Date?
    public var isAllDay: Bool
    public var recurrence: RecurrenceSpec?
    /// リスト名（reminder）またはカレンダー名（event）の前方一致。nil なら既定。
    public var listName: String?

    public init(
        kind: ItemKind,
        title: String,
        start: Date? = nil,
        end: Date? = nil,
        isAllDay: Bool = false,
        recurrence: RecurrenceSpec? = nil,
        listName: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.recurrence = recurrence
        self.listName = listName
    }
}

extension ParsedInput {
    /// 登録用に日時を確定する。
    /// 日付が無くても、時刻があれば今日、繰り返しがあれば次の該当日を期日にする。
    /// ただし日付を明示していない場合、その時刻が既に過ぎていれば翌日（繰り返しなら次の該当日）へ送る。
    /// 時刻が無ければ終日。event で終了が無ければ開始の 1 時間後。
    public func draft(reference: Date, calendar: Calendar) -> ItemDraft {
        guard let (day, start) = resolveStart(reference: reference, calendar: calendar) else {
            return ItemDraft(kind: kind, title: title, recurrence: recurrence, listName: listName)
        }
        var end: Date?
        if kind == .event {
            if let endTime {
                let endOnDay = Self.combine(day, with: endTime, calendar: calendar)
                // 「23時-1時」のように翌日にまたぐ終了
                end = endOnDay > start ? endOnDay : calendar.date(byAdding: .day, value: 1, to: endOnDay)
            } else if time != nil {
                end = calendar.date(byAdding: .hour, value: 1, to: start)
            } else {
                end = start
            }
        }
        return ItemDraft(
            kind: kind,
            title: title,
            start: start,
            end: end,
            isAllDay: time == nil,
            recurrence: recurrence,
            listName: listName
        )
    }

    /// 期日の日（0:00）と開始日時。期日なしなら nil。
    private func resolveStart(reference: Date, calendar: Calendar) -> (day: Date, start: Date)? {
        if let date {
            guard let day = calendar.date(from: date).map({ calendar.startOfDay(for: $0) }) else { return nil }
            return (day, Self.combine(day, with: time, calendar: calendar))
        }
        let today = calendar.startOfDay(for: reference)
        if let recurrence {
            guard let first = recurrence.firstOccurrence(onOrAfter: today, calendar: calendar) else { return nil }
            let start = Self.combine(first, with: time, calendar: calendar)
            if start >= reference || time == nil { return (first, start) }
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
                  let next = recurrence.firstOccurrence(onOrAfter: tomorrow, calendar: calendar)
            else { return nil }
            return (next, Self.combine(next, with: time, calendar: calendar))
        }
        if time != nil {
            let start = Self.combine(today, with: time, calendar: calendar)
            if start >= reference { return (today, start) }
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
            return (tomorrow, Self.combine(tomorrow, with: time, calendar: calendar))
        }
        return nil
    }

    private static func combine(_ day: Date, with time: DateComponents?, calendar: Calendar) -> Date {
        guard let time else { return day }
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) ?? day
    }
}
