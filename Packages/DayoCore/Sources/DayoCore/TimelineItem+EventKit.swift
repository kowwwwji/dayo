import CoreGraphics
import EventKit
import Foundation

extension TimelineItem {
    /// カレンダーが色を持たないときの表示色。
    static let fallbackColor = CGColor(gray: 0.5, alpha: 1)

    public init(event: EKEvent) {
        let baseID = event.calendarItemIdentifier
        let rules = event.recurrenceRules ?? []
        self.init(
            // 繰り返し予定は展開された各回（例外として切り離された回も）が同じ
            // calendarItemIdentifier を持つため、常に開始時刻を付けて区別する。
            id: "\(baseID)#\(event.startDate.timeIntervalSince1970)",
            calendarItemIdentifier: baseID,
            kind: .event,
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            isCompleted: false,
            sourceName: event.calendar?.title ?? "",
            accountName: event.calendar?.source?.title ?? "",
            color: event.calendar?.cgColor ?? Self.fallbackColor,
            recurrence: Self.editableRecurrence(rules),
            // TODO: 共有判定の手段はフェーズ2で調べる（EventKit に直接の API がない）
            isShared: false,
            hasRecurrence: !rules.isEmpty,
            notes: event.notes,
            calendarIdentifier: event.calendar?.calendarIdentifier ?? "",
            isEditable: event.calendar?.allowsContentModifications ?? false
        )
    }

    /// - Parameter timeZone: 期日にタイムゾーンが無い（floating）ときに使うゾーン。
    public init(reminder: EKReminder, timeZone: TimeZone = .autoupdatingCurrent) {
        let due = reminder.dueDateComponents
        let rules = reminder.recurrenceRules ?? []
        self.init(
            id: reminder.calendarItemIdentifier,
            calendarItemIdentifier: reminder.calendarItemIdentifier,
            kind: .reminder,
            title: reminder.title ?? "",
            start: due.flatMap { Self.date(from: $0, defaultTimeZone: timeZone) },
            end: nil,
            // 時刻のない期日は終日扱い
            isAllDay: due != nil && due?.hour == nil,
            isCompleted: reminder.isCompleted,
            sourceName: reminder.calendar?.title ?? "",
            accountName: reminder.calendar?.source?.title ?? "",
            color: reminder.calendar?.cgColor ?? Self.fallbackColor,
            recurrence: Self.editableRecurrence(rules),
            // TODO: 共有判定の手段はフェーズ2で調べる
            isShared: false,
            hasRecurrence: !rules.isEmpty,
            notes: reminder.notes,
            calendarIdentifier: reminder.calendar?.calendarIdentifier ?? "",
            isEditable: reminder.calendar?.allowsContentModifications ?? false,
            priority: ReminderPriority(ekPriority: reminder.priority)
        )
    }

    /// 規則が 1 つで、このアプリで表せるときだけ編集可能な形にする。複数あればカスタム扱い。
    private static func editableRecurrence(_ rules: [EKRecurrenceRule]) -> RecurrenceSpec? {
        guard rules.count == 1 else { return nil }
        return RecurrenceSpec(rule: rules[0])
    }

    /// EventKit の期日はグレゴリオ暦の年月日で入っているため、ユーザーの暦設定（和暦など）に
    /// 依存する `Calendar.current` では解釈しない。
    static func date(from components: DateComponents, defaultTimeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = components.timeZone ?? defaultTimeZone
        return calendar.date(from: components)
    }
}
