import EventKit
import Foundation

/// EventKit への依存をここに閉じ込める。
///
/// `items(in:)` が返すのは期間内の予定・期日付きリマインダーと、期日なしリマインダーのみ。
/// 期限切れ（期間より前の未完了）や完了済みの扱いは画面側の要件なので、ここでは返さない。
public final class EventKitRepository: CalendarSource {
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

    public func items(in range: DateInterval) async throws -> [TimelineItem] {
        let eventPredicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: nil)
        let events = store.events(matching: eventPredicate).map(TimelineItem.init(event:))

        // 未完了リマインダーを全件取り、期間内の期日付きと期日なしを残す。
        let reminderPredicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        )
        let reminders = await fetchReminderItems(matching: reminderPredicate)
            .filter { $0.falls(in: range) }

        return events + reminders
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
