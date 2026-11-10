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
