import Foundation

/// 繰り返しリマインダーの将来回を画面用に展開する。
/// EventKit のリマインダーは「次の 1 回」しか実体を持たないため、先の回は規則から計算して見せる。
public enum VirtualOccurrences {
    /// 展開の元になるリマインダー。`end` より前に期日がある、未完了で繰り返し付きのもの。
    /// 期日が表示期間より前でも、そこを起点に期間内の回を数えるので含める。
    public static func sources(in reminders: [TimelineItem], before end: Date) -> [TimelineItem] {
        reminders.filter { item in
            guard isExpandable(item), let start = item.start else { return false }
            return start < end
        }
    }

    /// `range` に入る将来回。編集できない形（カスタム規則）の繰り返しは展開しない。
    public static func expand(_ recurring: [TimelineItem], in range: DateInterval, calendar: Calendar) -> [TimelineItem] {
        recurring.flatMap { item -> [TimelineItem] in
            guard isExpandable(item), let anchor = item.start, let recurrence = item.recurrence else { return [] }
            return recurrence.occurrences(after: anchor, in: range, calendar: calendar).map { date in
                item.virtualOccurrence(at: date)
            }
        }
    }

    private static func isExpandable(_ item: TimelineItem) -> Bool {
        item.kind == .reminder && !item.isCompleted && !item.isVirtual && item.recurrence != nil && item.start != nil
    }
}

extension TimelineItem {
    fileprivate func virtualOccurrence(at date: Date) -> TimelineItem {
        TimelineItem(
            id: "\(id)@\(date.timeIntervalSince1970)",
            calendarItemIdentifier: calendarItemIdentifier,
            kind: kind,
            title: title,
            start: date,
            end: nil,
            isAllDay: isAllDay,
            isCompleted: false,
            sourceName: sourceName,
            accountName: accountName,
            color: color,
            recurrence: recurrence,
            hasRecurrence: hasRecurrence,
            notes: notes,
            calendarIdentifier: calendarIdentifier,
            isEditable: false,
            priority: priority,
            earlyReminderMinutes: earlyReminderMinutes,
            isVirtual: true
        )
    }
}
