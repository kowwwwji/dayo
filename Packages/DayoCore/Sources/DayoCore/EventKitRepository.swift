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
