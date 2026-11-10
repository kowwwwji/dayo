import EventKit
import Foundation

/// EventKit への依存をここに閉じ込める。
public final class EventKitRepository: CalendarSource {
    /// 完了済みリマインダーを遡って取る日数。EventKit は完了日でしか絞れないため、
    /// 期日が期間内で完了がそれより前のものを拾うのに使う。全件取得は履歴が長いと重い。
    static let completedLookback: TimeInterval = 30 * 86_400

    private let store: EKEventStore
    private let timeZone: TimeZone

    public init(store: EKEventStore = EKEventStore(), timeZone: TimeZone = .autoupdatingCurrent) {
        self.store = store
        self.timeZone = timeZone
    }

    public func requestAccess() async throws -> AccessStatus {
        _ = try await store.requestFullAccessToEvents()
        _ = try await store.requestFullAccessToReminders()
        return AccessStatus(
            events: EKEventStore.authorizationStatus(for: .event),
            reminders: EKEventStore.authorizationStatus(for: .reminder)
        )
    }

    public func snapshot(for range: DateInterval, includingOverdue: Bool) async throws -> TimelineSnapshot {
        let eventPredicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: nil)
        let events = store.events(matching: eventPredicate).map(TimelineItem.init(event:))

        let incomplete = await fetchReminderItems(
            matching: store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        )
        let completed = await fetchReminderItems(
            matching: store.predicateForCompletedReminders(
                withCompletionDateStarting: range.start.addingTimeInterval(-Self.completedLookback),
                ending: nil,
                calendars: nil
            )
        )
        let reminders = Self.merge(incomplete: incomplete, completed: completed)

        let overdue = includingOverdue
            ? reminders.filter { !$0.isCompleted && $0.start.map { $0 < range.start } == true }
            : []
        return TimelineSnapshot(
            items: events + reminders.filter { $0.falls(in: range) },
            overdue: overdue
        )
    }

    public func setCompleted(_ completed: Bool, for item: TimelineItem) async throws {
        guard item.kind == .reminder else { throw CalendarSourceError.notAReminder }
        guard let reminder = store.calendarItem(withIdentifier: item.calendarItemIdentifier) as? EKReminder else {
            throw CalendarSourceError.itemNotFound
        }
        reminder.isCompleted = completed
        try store.save(reminder, commit: true)
    }

    public func create(_ draft: ItemDraft) async throws {
        switch draft.kind {
        case .reminder:
            guard let calendar = try calendar(named: draft.listName, for: .reminder)
                ?? store.defaultCalendarForNewReminders()
            else { throw CalendarSourceError.noCalendar }
            let reminder = EKReminder(eventStore: store)
            reminder.title = draft.title
            reminder.calendar = calendar
            if let start = draft.start {
                reminder.dueDateComponents = Self.dueComponents(for: start, allDay: draft.isAllDay, timeZone: timeZone)
                // 期日時刻の通知は純正リマインダーが出す。アラームが無いと時刻付きでも通知されない
                if !draft.isAllDay {
                    reminder.addAlarm(EKAlarm(absoluteDate: start))
                }
            }
            if let recurrence = draft.recurrence {
                reminder.addRecurrenceRule(EKRecurrenceRule(recurrence))
            }
            try store.save(reminder, commit: true)
        case .event:
            guard let start = draft.start else { throw CalendarSourceError.eventNeedsStart }
            guard let calendar = try calendar(named: draft.listName, for: .event)
                ?? store.defaultCalendarForNewEvents
            else { throw CalendarSourceError.noCalendar }
            let event = EKEvent(eventStore: store)
            event.title = draft.title
            event.calendar = calendar
            event.startDate = start
            event.endDate = draft.end ?? start
            event.isAllDay = draft.isAllDay
            if let recurrence = draft.recurrence {
                event.addRecurrenceRule(EKRecurrenceRule(recurrence))
            }
            try store.save(event, span: .thisEvent, commit: true)
        }
    }

    public func destinations() async throws -> [Destination] {
        func writable(_ entity: EKEntityType, as kind: ItemKind) -> [Destination] {
            store.calendars(for: entity)
                .filter(\.allowsContentModifications)
                .map {
                    Destination(
                        id: $0.calendarIdentifier,
                        name: $0.title,
                        kind: kind,
                        color: $0.cgColor ?? TimelineItem.fallbackColor
                    )
                }
        }
        return writable(.reminder, as: .reminder) + writable(.event, as: .event)
    }

    /// 名前でカレンダー／リストを探す。名前が無ければ nil（呼び出し側で既定にする）。
    /// 名前があるのに見つからなければエラー。黙って既定に入れると、意図しない場所に登録されたことに気づけない。
    private func calendar(named name: String?, for entity: EKEntityType) throws -> EKCalendar? {
        guard let name, !name.isEmpty else { return nil }
        let candidates = store.calendars(for: entity).filter { $0.allowsContentModifications }
        guard let found = Self.match(name, in: candidates, title: \.title) else {
            throw CalendarSourceError.listNotFound(name)
        }
        return found
    }

    /// 完全一致 → 前方一致の順に探す。大文字小文字は区別しない。
    static func match<C>(_ name: String, in candidates: [C], title: (C) -> String) -> C? {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        return candidates.first { title($0).compare(name, options: options) == .orderedSame }
            ?? candidates.first { title($0).range(of: name, options: options.union(.anchored)) != nil }
    }

    /// 期日。終日は年月日だけ、時刻ありは時分まで（純正リマインダーと同じ持ち方）。
    static func dueComponents(for date: Date, allDay: Bool, timeZone: TimeZone) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let units: Set<Calendar.Component> = allDay
            ? [.year, .month, .day]
            : [.year, .month, .day, .hour, .minute]
        return calendar.dateComponents(units, from: date)
    }

    /// 同期中は通知がまとめて届くため、未処理分は 1 件に畳む。
    public var changes: AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let token = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: store, queue: nil
            ) { _ in
                continuation.yield()
            }
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(token)
            }
        }
    }

    /// 2 回の取得の間に完了した項目は両方に現れるため、完了済み側を採用して重複を除く。
    static func merge(incomplete: [TimelineItem], completed: [TimelineItem]) -> [TimelineItem] {
        var byID: [String: TimelineItem] = [:]
        for item in incomplete { byID[item.id] = item }
        for item in completed { byID[item.id] = item }
        return Array(byID.values)
    }

    /// EKReminder は Sendable でないため、コールバックのスレッド上で TimelineItem に変換してから返す。
    private func fetchReminderItems(matching predicate: NSPredicate) async -> [TimelineItem] {
        let timeZone = self.timeZone
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let items = (reminders ?? []).map { TimelineItem(reminder: $0, timeZone: timeZone) }
                continuation.resume(returning: items)
            }
        }
    }
}
