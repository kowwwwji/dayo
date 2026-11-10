import EventKit
import Foundation
import Testing
@testable import DayoCore

private let utc = TimeZone(identifier: "UTC")!
private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

private func iso(_ string: String) -> Date {
    ISO8601DateFormatter().date(from: string)!
}

/// EKEvent / EKReminder → TimelineItem の変換を in-memory のオブジェクトで確認する。
/// EKEventStore はアクセスしない限り権限ダイアログを出さない。
@Suite struct TimelineItemMappingTests {
    let store = EKEventStore()

    private func makeCalendar(_ type: EKEntityType, title: String) -> EKCalendar {
        let cal = EKCalendar(for: type, eventStore: store)
        cal.title = title
        cal.cgColor = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        return cal
    }

    @Test func eventMapsDatesAndSource() {
        let event = EKEvent(eventStore: store)
        event.title = "面談"
        event.startDate = Date(timeIntervalSince1970: 1_000)
        event.endDate = Date(timeIntervalSince1970: 4_600)
        event.calendar = makeCalendar(.event, title: "仕事")

        let item = TimelineItem(event: event)

        #expect(item.kind == .event)
        #expect(item.title == "面談")
        #expect(item.start == event.startDate)
        #expect(item.end == event.endDate)
        #expect(item.isAllDay == false)
        #expect(item.isCompleted == false)
        #expect(item.sourceName == "仕事")
        #expect(item.color == event.calendar.cgColor)
        #expect(item.recurrence == nil)
        #expect(item.calendarItemIdentifier == event.calendarItemIdentifier)
        #expect(item.id.hasPrefix(event.calendarItemIdentifier))
    }

    @Test func eventOccurrencesGetDistinctIDs() {
        let rule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        let event = EKEvent(eventStore: store)
        event.title = "定例"
        event.startDate = Date(timeIntervalSince1970: 0)
        event.endDate = Date(timeIntervalSince1970: 3_600)
        event.addRecurrenceRule(rule)
        event.calendar = makeCalendar(.event, title: "仕事")

        let a = TimelineItem(event: event)
        event.startDate = Date(timeIntervalSince1970: 7 * 86_400)
        event.endDate = Date(timeIntervalSince1970: 7 * 86_400 + 3_600)
        let b = TimelineItem(event: event)

        #expect(a.recurrence == RecurrenceSpec(frequency: .weekly))
        #expect(a.hasRecurrence)
        #expect(a.calendarItemIdentifier == b.calendarItemIdentifier)
        #expect(a.id != b.id)
    }

    @Test func reminderPriorityIsRoundedToFourLevels() {
        let reminder = EKReminder(eventStore: store)
        reminder.title = "重要"
        reminder.calendar = makeCalendar(.reminder, title: "仕事")
        reminder.priority = 1
        #expect(TimelineItem(reminder: reminder).priority == .high)
        reminder.priority = 5
        #expect(TimelineItem(reminder: reminder).priority == .medium)
        reminder.priority = 7
        #expect(TimelineItem(reminder: reminder).priority == .low)
        reminder.priority = 0
        #expect(TimelineItem(reminder: reminder).priority == ReminderPriority.none)
    }

    @Test func earlyReminderComesFromTheEarliestNegativeRelativeAlarm() {
        let reminder = EKReminder(eventStore: store)
        reminder.title = "会議"
        reminder.calendar = makeCalendar(.reminder, title: "仕事")
        reminder.dueDateComponents = DateComponents(year: 2026, month: 11, day: 10, hour: 9)
        #expect(TimelineItem(reminder: reminder).earlyReminderMinutes == nil)

        // 期日ちょうどの絶対アラームは数えない
        reminder.addAlarm(EKAlarm(absoluteDate: Date()))
        #expect(TimelineItem(reminder: reminder).earlyReminderMinutes == nil)

        reminder.addAlarm(EKAlarm(relativeOffset: -15 * 60))
        #expect(TimelineItem(reminder: reminder).earlyReminderMinutes == 15)

        // 複数あれば最も早いもの。期日後（正）のものは無視
        reminder.addAlarm(EKAlarm(relativeOffset: -60 * 60))
        reminder.addAlarm(EKAlarm(relativeOffset: 10 * 60))
        #expect(TimelineItem(reminder: reminder).earlyReminderMinutes == 60)
    }

    @Test func locationAndTinyOffsetAlarmsAreNotEarlyReminders() {
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = makeCalendar(.reminder, title: "家")
        reminder.dueDateComponents = DateComponents(year: 2026, month: 11, day: 10, hour: 9)

        // 場所ベースの通知（到着時）。relativeOffset は 0 だが絶対時刻でもない
        let home = EKAlarm(relativeOffset: 0)
        home.structuredLocation = EKStructuredLocation(title: "自宅")
        home.proximity = .enter
        reminder.addAlarm(home)
        #expect(home.isEarlyReminder == false)
        #expect(TimelineItem(reminder: reminder).earlyReminderMinutes == nil)

        // 1 分未満は無し扱い（0 を返さない）
        reminder.addAlarm(EKAlarm(relativeOffset: -20))
        #expect(TimelineItem(reminder: reminder).earlyReminderMinutes == nil)
    }

    @Test func unsupportedRecurrenceIsKeptAsCustom() {
        let event = EKEvent(eventStore: store)
        event.title = "誕生日"
        event.startDate = Date(timeIntervalSince1970: 0)
        event.endDate = Date(timeIntervalSince1970: 3_600)
        event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil))
        event.notes = "ケーキ"
        event.calendar = makeCalendar(.event, title: "家族")

        let item = TimelineItem(event: event)

        #expect(item.recurrence == nil)
        #expect(item.hasRecurrence)
        #expect(item.notes == "ケーキ")
        #expect(item.calendarIdentifier == event.calendar.calendarIdentifier)
    }

    @Test func reminderWithTimeMapsDueDateInDefaultTimeZone() {
        let reminder = EKReminder(eventStore: store)
        reminder.title = "ゴミ出し"
        reminder.calendar = makeCalendar(.reminder, title: "家族")
        reminder.dueDateComponents = DateComponents(year: 2026, month: 11, day: 10, hour: 9, minute: 0)
        reminder.isCompleted = true

        let item = TimelineItem(reminder: reminder, timeZone: utc)

        #expect(item.kind == .reminder)
        #expect(item.start == iso("2026-11-10T09:00:00Z"))
        #expect(item.end == nil)
        #expect(item.isAllDay == false)
        #expect(item.isCompleted == true)
        #expect(item.sourceName == "家族")
        #expect(item.id == reminder.calendarItemIdentifier)
    }

    @Test func reminderHonoursTimeZoneInDueDate() {
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = makeCalendar(.reminder, title: "家族")
        var due = DateComponents(year: 2026, month: 11, day: 10, hour: 9, minute: 0)
        due.timeZone = tokyo
        reminder.dueDateComponents = due

        let item = TimelineItem(reminder: reminder, timeZone: utc)

        #expect(item.start == iso("2026-11-10T00:00:00Z"))
    }

    @Test func reminderDueDateIsGregorianRegardlessOfComponentsCalendar() {
        // EventKit の期日はグレゴリオ暦の年。和暦などの Calendar が付いていても年号として解釈しない。
        var due = DateComponents(year: 2026, month: 11, day: 10)
        due.calendar = Calendar(identifier: .japanese)

        let date = TimelineItem.date(from: due, defaultTimeZone: utc)

        #expect(date == iso("2026-11-10T00:00:00Z"))
    }

    @Test func reminderWithDateOnlyIsAllDay() {
        let reminder = EKReminder(eventStore: store)
        reminder.title = "経費精算"
        reminder.calendar = makeCalendar(.reminder, title: "仕事")
        reminder.dueDateComponents = DateComponents(year: 2026, month: 11, day: 28)

        let item = TimelineItem(reminder: reminder, timeZone: utc)

        #expect(item.start == iso("2026-11-28T00:00:00Z"))
        #expect(item.isAllDay == true)
    }

    @Test func reminderWithoutDueDateHasNoStart() {
        let reminder = EKReminder(eventStore: store)
        reminder.title = "牛乳買う"
        reminder.calendar = makeCalendar(.reminder, title: "買い物")

        let item = TimelineItem(reminder: reminder)

        #expect(item.start == nil)
        #expect(item.isAllDay == false)
        #expect(item.isCompleted == false)
    }
}

@Suite struct RangeFilterTests {
    private func item(start: Date?) -> TimelineItem {
        TimelineItem(
            id: "x", calendarItemIdentifier: "x", kind: .reminder, title: "", start: start, end: nil,
            isAllDay: false, isCompleted: false, sourceName: "", accountName: "",
            color: CGColor(gray: 0, alpha: 1), recurrence: nil, isShared: false
        )
    }

    let today = DateInterval(start: iso("2026-11-10T00:00:00Z"), end: iso("2026-11-11T00:00:00Z"))

    @Test func includesStartAndExcludesEnd() {
        #expect(item(start: today.start).falls(in: today) == true)
        #expect(item(start: iso("2026-11-10T23:59:59Z")).falls(in: today) == true)
        #expect(item(start: today.end).falls(in: today) == false)
    }

    @Test func excludesOverdueAndUndated() {
        #expect(item(start: iso("2026-11-09T12:00:00Z")).falls(in: today) == false)
        #expect(item(start: nil).falls(in: today) == false)
    }
}

@Suite struct AccessStatusTests {
    @Test func grantedOnlyWhenBothFullAccess() {
        #expect(AccessStatus(events: .fullAccess, reminders: .fullAccess) == .granted)
        #expect(AccessStatus(events: .writeOnly, reminders: .fullAccess) == .denied)
        #expect(AccessStatus(events: .fullAccess, reminders: .denied) == .denied)
    }

    @Test func restrictedWinsOverDenied() {
        #expect(AccessStatus(events: .restricted, reminders: .denied) == .restricted)
    }

    @Test func notDeterminedWhenEitherUnasked() {
        #expect(AccessStatus(events: .notDetermined, reminders: .fullAccess) == .notDetermined)
        #expect(AccessStatus(events: .notDetermined, reminders: .notDetermined) == .notDetermined)
    }
}

@Suite struct EventKitApplyTests {
    private func tokyoDate(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func givingAnAllDayEventATimeKeepsThatTime() throws {
        let store = EKEventStore()
        let repository = EventKitRepository(store: store, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        let event = EKEvent(eventStore: store)
        event.title = "出張"
        event.isAllDay = true
        event.startDate = tokyoDate(10)
        event.endDate = tokyoDate(10)

        // 終日のまま日時を入れると EventKit が日の端（0:00〜23:59）へ丸めてしまう
        let draft = ItemDraft(kind: .event, title: "出張", start: tokyoDate(12, 10), end: tokyoDate(12, 11))
        try repository.apply(draft, to: event, previous: nil, changesRecurrence: false)

        #expect(event.isAllDay == false)
        #expect(event.startDate == tokyoDate(12, 10))
        #expect(event.endDate == tokyoDate(12, 11))
    }
}
