import EventKit

extension EKRecurrenceRule {
    /// `RecurrenceSpec` を EventKit の規則に変換する。終了は設けない。
    convenience init(_ spec: RecurrenceSpec) {
        let frequency: EKRecurrenceFrequency
        switch spec.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        }
        let daysOfTheWeek = spec.weekdays
            .compactMap(EKWeekday.init(rawValue:))
            .map { EKRecurrenceDayOfWeek($0, weekNumber: spec.weekOfMonth ?? 0) }
        self.init(
            recurrenceWith: frequency,
            interval: spec.interval,
            daysOfTheWeek: daysOfTheWeek.isEmpty ? nil : daysOfTheWeek,
            daysOfTheMonth: spec.daysOfMonth.isEmpty ? nil : spec.daysOfMonth.map { NSNumber(value: $0) },
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil
        )
    }
}

extension RecurrenceSpec {
    /// EventKit の規則のうち、このアプリで編集できる単純なもの（日・週・月、終了なし）だけを取り込む。
    /// 年次や終了付き、複合条件は nil（=カスタム。表示だけして保存時に触らない）。
    init?(rule: EKRecurrenceRule) {
        guard rule.recurrenceEnd == nil,
              rule.monthsOfTheYear?.isEmpty ?? true,
              rule.weeksOfTheYear?.isEmpty ?? true,
              rule.daysOfTheYear?.isEmpty ?? true
        else { return nil }

        let weekdays = rule.daysOfTheWeek ?? []
        let daysOfMonth = (rule.daysOfTheMonth ?? []).map(\.intValue)
        let setPositions = (rule.setPositions ?? []).map(\.intValue)

        switch rule.frequency {
        case .daily:
            guard weekdays.isEmpty, daysOfMonth.isEmpty, setPositions.isEmpty else { return nil }
            self.init(frequency: .daily, interval: rule.interval)
        case .weekly:
            guard daysOfMonth.isEmpty, setPositions.isEmpty, weekdays.allSatisfy({ $0.weekNumber == 0 }) else { return nil }
            self.init(frequency: .weekly, interval: rule.interval, weekdays: weekdays.map(\.dayOfTheWeek.rawValue))
        case .monthly:
            if weekdays.isEmpty {
                // 月末（-1）のような負の日は表せない
                guard setPositions.isEmpty, daysOfMonth.allSatisfy({ $0 > 0 }) else { return nil }
                self.init(frequency: .monthly, interval: rule.interval, daysOfMonth: daysOfMonth)
            } else {
                // 「第2火曜」「最終金曜」は曜日 1 つだけ扱う。複数曜日に位置指定が付くと意味が変わるため
                guard daysOfMonth.isEmpty, weekdays.count == 1 else { return nil }
                // 「最終金曜」は daysOfTheWeek の weekNumber か setPositions のどちらかで表される
                let weekNumbers = Set(weekdays.map(\.weekNumber))
                let weekOfMonth: Int
                if weekNumbers == [0], setPositions.count == 1 {
                    weekOfMonth = setPositions[0]
                } else if weekNumbers.count == 1, let only = weekNumbers.first, only != 0, setPositions.isEmpty {
                    weekOfMonth = only
                } else {
                    return nil
                }
                self.init(
                    frequency: .monthly,
                    interval: rule.interval,
                    weekdays: weekdays.map(\.dayOfTheWeek.rawValue),
                    weekOfMonth: weekOfMonth
                )
            }
        default:
            return nil
        }
    }
}
