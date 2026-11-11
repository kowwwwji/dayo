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
            overdue: overdue,
            recurring: VirtualOccurrences.sources(in: reminders, before: range.end)
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
            guard let calendar = try resolveCalendar(draft, for: .reminder) ?? store.defaultCalendarForNewReminders()
            else { throw CalendarSourceError.noCalendar }
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = calendar
            try apply(draft, to: reminder, previous: nil)
            try commit { try store.save(reminder, commit: true) }
        case .event:
            guard let calendar = try resolveCalendar(draft, for: .event) ?? store.defaultCalendarForNewEvents
            else { throw CalendarSourceError.noCalendar }
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            try apply(draft, to: event, previous: nil, changesRecurrence: true)
            try commit { try store.save(event, span: .thisEvent, commit: true) }
        }
    }

    public func update(_ item: TimelineItem, with draft: ItemDraft, span: EditSpan) async throws {
        switch item.kind {
        case .reminder:
            let reminder = try fetchReminder(item)
            try commit {
                if let calendar = try resolveCalendar(draft, for: .reminder) { reminder.calendar = calendar }
                try apply(draft, to: reminder, previous: item)
                try store.save(reminder, commit: true)
            }
        case .event:
            guard draft.start != nil else { throw CalendarSourceError.eventNeedsStart }
            let event = try fetchEvent(item)
            // 繰り返しの 1 回だけを変えるときは規則とカレンダーには触れない。回ごとに持てるものではないため
            let wholeSeries = !item.hasRecurrence || span == .futureOccurrences
            try commit {
                if wholeSeries, let calendar = try resolveCalendar(draft, for: .event) { event.calendar = calendar }
                try apply(draft, to: event, previous: item, changesRecurrence: wholeSeries)
                try store.save(event, span: Self.ekSpan(span), commit: true)
            }
        }
    }

    public func delete(_ item: TimelineItem, span: EditSpan) async throws {
        switch item.kind {
        case .reminder:
            try store.remove(try fetchReminder(item), commit: true)
        case .event:
            try store.remove(try fetchEvent(item), span: Self.ekSpan(span), commit: true)
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

    // MARK: - 書き込みの共通部分

    /// 途中で失敗したら、変更しかけたオブジェクトをストアのキャッシュから戻す。
    /// 戻さないと次の取得で未保存の値が見えてしまう。
    private func commit(_ body: () throws -> Void) throws {
        do {
            try body()
        } catch {
            store.reset()
            throw error
        }
    }

    private func fetchReminder(_ item: TimelineItem) throws -> EKReminder {
        guard let reminder = store.calendarItem(withIdentifier: item.calendarItemIdentifier) as? EKReminder else {
            throw CalendarSourceError.itemNotFound
        }
        return reminder
    }

    /// 繰り返し予定の特定の回は `calendarItem(withIdentifier:)` では取れない（先頭の回が返る）ため、
    /// その回の時間帯で検索して開始時刻が一致するものを選ぶ。
    private func fetchEvent(_ item: TimelineItem) throws -> EKEvent {
        guard let start = item.start else { throw CalendarSourceError.itemNotFound }
        let end = item.end.map { max($0, start.addingTimeInterval(1)) } ?? start.addingTimeInterval(1)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let match = store.events(matching: predicate).first {
            $0.calendarItemIdentifier == item.calendarItemIdentifier && $0.startDate == start
        }
        guard let match else { throw CalendarSourceError.itemNotFound }
        return match
    }

    /// `previous` は更新前の項目。nil なら新規。
    private func apply(_ draft: ItemDraft, to reminder: EKReminder, previous: TimelineItem?) throws {
        reminder.title = draft.title
        reminder.notes = Self.normalizedNotes(draft.notes)
        reminder.priority = draft.priority.rawValue
        if let start = draft.start {
            reminder.dueDateComponents = Self.dueComponents(for: start, allDay: draft.isAllDay, timeZone: timeZone)
        } else {
            reminder.dueDateComponents = nil
        }
        // 期日時刻の通知は純正リマインダーが出す。アラームが無いと時刻付きでも通知されない。
        // 期日が変わったときだけ付け替え、「10分前」など相対のアラームには触らない
        let dueChanged = previous.map { $0.start != draft.start || $0.isAllDay != draft.isAllDay } ?? true
        if dueChanged {
            reminder.alarms?.filter { $0.absoluteDate != nil }.forEach(reminder.removeAlarm)
            if let start = draft.start, !draft.isAllDay {
                reminder.addAlarm(EKAlarm(absoluteDate: start))
            }
        }
        // 早期リマインダー（期日より前の相対アラーム）は値が変わったときだけ付け替える。
        // 期日が無いときは基準が無いので外す
        if Self.shouldReplaceEarlyReminder(previous: previous, draft: draft) {
            reminder.alarms?.filter(\.isEarlyReminder).forEach(reminder.removeAlarm)
            if draft.start != nil, !draft.isAllDay, let minutes = draft.earlyReminderMinutes, minutes > 0 {
                reminder.addAlarm(EKAlarm(relativeOffset: TimeInterval(-minutes * 60)))
            }
        }
        if !(previous?.hasCustomRecurrence ?? false) {
            replaceRecurrence(of: reminder, with: draft.recurrence)
        }
    }

    /// 新規なら常に、更新なら早期リマインダーの値が変わったときだけ相対アラームを付け替える。
    /// 期日を外す・時刻なしにする場合は draft 側が nil になるので、ここで変化として拾える。
    static func shouldReplaceEarlyReminder(previous: TimelineItem?, draft: ItemDraft) -> Bool {
        guard let previous else { return true }
        return previous.earlyReminderMinutes != draft.earlyReminderMinutes
    }

    func apply(_ draft: ItemDraft, to event: EKEvent, previous: TimelineItem?, changesRecurrence: Bool) throws {
        guard let start = draft.start else { throw CalendarSourceError.eventNeedsStart }
        event.title = draft.title
        event.notes = Self.normalizedNotes(draft.notes)
        // 終日かどうかを先に決める。終日のまま日時を入れると EventKit が日の端（0:00〜23:59）へ丸めるので、
        // 終日の予定に時刻を付けたとき、その時刻が消えてしまう
        event.isAllDay = draft.isAllDay
        event.startDate = start
        event.endDate = draft.end ?? start
        if changesRecurrence, !(previous?.hasCustomRecurrence ?? false) {
            replaceRecurrence(of: event, with: draft.recurrence)
        }
    }

    /// 規則が実質同じなら触らない。作り直すと EventKit 側だけが持つ情報（週の始まりなど）が落ちる。
    private func replaceRecurrence(of calendarItem: EKCalendarItem, with spec: RecurrenceSpec?) {
        let current = calendarItem.recurrenceRules ?? []
        if current.isEmpty, spec == nil { return }
        if current.count == 1, let spec, RecurrenceSpec(rule: current[0]) == spec { return }
        current.forEach(calendarItem.removeRecurrenceRule)
        if let spec {
            calendarItem.addRecurrenceRule(EKRecurrenceRule(spec))
        }
    }

    /// 識別子があればそれ、なければ名前の一致で保存先を決める。どちらも無ければ nil（呼び出し側で既定か現状維持）。
    private func resolveCalendar(_ draft: ItemDraft, for entity: EKEntityType) throws -> EKCalendar? {
        if let id = draft.calendarID {
            guard let calendar = store.calendar(withIdentifier: id),
                  calendar.allowedEntityTypes.contains(entity == .event ? .event : .reminder),
                  calendar.allowsContentModifications
            else { throw CalendarSourceError.noCalendar }
            return calendar
        }
        return try calendar(named: draft.listName, for: entity)
    }

    private static func ekSpan(_ span: EditSpan) -> EKSpan {
        switch span {
        case .thisOccurrence: .thisEvent
        case .futureOccurrences: .futureEvents
        }
    }

    /// 空白だけのメモは nil にする。
    private static func normalizedNotes(_ notes: String?) -> String? {
        guard let notes else { return nil }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : notes
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

    public func refresh() async {
        store.refreshSourcesIfNecessary()
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
