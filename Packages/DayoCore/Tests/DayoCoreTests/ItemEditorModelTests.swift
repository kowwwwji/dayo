import CoreGraphics
import EventKit
import Foundation
import Testing
@testable import DayoCore

private final class EditingSource: CalendarSource {
    private(set) var updates: [(item: TimelineItem, draft: ItemDraft, span: EditSpan)] = []
    private(set) var deletes: [(item: TimelineItem, span: EditSpan)] = []
    var error: Error?
    var destinationList: [Destination] = []

    func requestAccess() async throws -> AccessStatus { .granted }
    func snapshot(for range: DateInterval, includingOverdue: Bool) async throws -> TimelineSnapshot { .empty }
    func setCompleted(_ completed: Bool, for item: TimelineItem) async throws {}
    func create(_ draft: ItemDraft) async throws {}
    func update(_ item: TimelineItem, with draft: ItemDraft, span: EditSpan) async throws {
        if let error { throw error }
        updates.append((item, draft, span))
    }
    func delete(_ item: TimelineItem, span: EditSpan) async throws {
        if let error { throw error }
        deletes.append((item, span))
    }
    func destinations() async throws -> [Destination] { destinationList }
    var changes: AsyncStream<Void> { AsyncStream { _ in } }
}

private struct TestError: LocalizedError {
    var errorDescription: String? { "boom" }
}

private let tokyo: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
}()

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    tokyo.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

private func item(
    kind: ItemKind,
    start: Date?,
    end: Date? = nil,
    isAllDay: Bool = false,
    recurrence: RecurrenceSpec? = nil,
    hasRecurrence: Bool? = nil
) -> TimelineItem {
    TimelineItem(
        id: "x", calendarItemIdentifier: "x", kind: kind, title: "面談", start: start, end: end,
        isAllDay: isAllDay, isCompleted: false, sourceName: "仕事", accountName: "",
        color: CGColor(gray: 0, alpha: 1), recurrence: recurrence, isShared: false,
        hasRecurrence: hasRecurrence, notes: "メモ", calendarIdentifier: "cal-1"
    )
}

@MainActor
@Suite struct ItemEditorModelTests {
    // 2026-11-10 は火曜
    let tuesday10 = date(2026, 11, 10, 10)

    private func makeModel(_ item: TimelineItem, source: EditingSource = EditingSource()) -> ItemEditorModel {
        ItemEditorModel(item: item, source: source, calendar: tokyo, now: tuesday10)
    }

    @Test func initialValuesComeFromItem() {
        let model = makeModel(item(kind: .event, start: tuesday10, end: date(2026, 11, 10, 11)))
        #expect(model.title == "面談")
        #expect(model.notes == "メモ")
        #expect(model.start == tuesday10)
        #expect(model.end == date(2026, 11, 10, 11))
        #expect(model.isAllDay == false)
        #expect(model.destinationID == "cal-1")
        #expect(model.recurrence == .none)
        #expect(model.needsSpanChoice == false)
    }

    @Test func recognisesPresetRecurrenceFromStartDate() {
        let weekly = makeModel(item(kind: .event, start: tuesday10, recurrence: .init(frequency: .weekly, weekdays: [3])))
        #expect(weekly.recurrence == .weekly)
        #expect(weekly.label(for: .weekly) == "毎週火曜")
        #expect(weekly.needsSpanChoice)

        let monthly = makeModel(item(kind: .reminder, start: tuesday10, recurrence: .init(frequency: .monthly, daysOfMonth: [10])))
        #expect(monthly.recurrence == .monthly)
        #expect(monthly.needsSpanChoice == false)

        let custom = makeModel(item(kind: .reminder, start: tuesday10, recurrence: .init(frequency: .weekly, weekdays: [2, 4, 6])))
        #expect(custom.recurrence == .custom)
        #expect(custom.recurrenceOptions.contains(.custom))
        #expect(custom.label(for: .custom) == "毎週月水金曜")
        #expect(custom.draft.recurrence == RecurrenceSpec(frequency: .weekly, weekdays: [2, 4, 6]))
    }

    @Test func bareWeeklyAndMonthlyRulesMatchPresetsAndAreSentBackUnchanged() {
        // 純正アプリは「毎週」を曜日なしで保存することがある。開始日の曜日で補ってプリセット扱いにする
        let bareWeekly = RecurrenceSpec(frequency: .weekly)
        let weekly = makeModel(item(kind: .reminder, start: tuesday10, recurrence: bareWeekly))
        #expect(weekly.recurrence == .weekly)
        #expect(weekly.recurrenceOptions.contains(.custom) == false)
        // 変えていなければ元の規則をそのまま渡し、Repository が作り直さずに済むようにする
        #expect(weekly.draft.recurrence == bareWeekly)

        let bareMonthly = makeModel(item(kind: .reminder, start: tuesday10, recurrence: .init(frequency: .monthly)))
        #expect(bareMonthly.recurrence == .monthly)

        let shuffled = makeModel(item(kind: .reminder, start: tuesday10, recurrence: .init(frequency: .weekly, weekdays: [6, 2, 4, 3, 5])))
        #expect(shuffled.recurrence == .weekdays)

        // 選択肢を変えたらプリセットから作る
        weekly.recurrence = .daily
        #expect(weekly.draft.recurrence == RecurrenceSpec(frequency: .daily))
    }

    @Test func zeroLengthEventIsValid() {
        let model = makeModel(item(kind: .event, start: tuesday10, end: tuesday10))
        #expect(model.validationMessage == nil)
        model.end = date(2026, 11, 10, 9)
        #expect(model.validationMessage == "終了は開始より前にはできません")
    }

    @Test func undatedReminderDraftHasNoAllDayOrEnd() {
        let model = makeModel(item(kind: .reminder, start: nil))
        #expect(model.draft.isAllDay == false)
        #expect(model.draft.end == nil)
    }

    @Test func unsupportedRecurrenceStillRequiresDueDate() async {
        let model = makeModel(item(kind: .reminder, start: tuesday10, recurrence: nil, hasRecurrence: true))
        model.hasDate = false
        #expect(await model.save() == false)
        #expect(model.errorMessage == "繰り返しのあるリマインダーには期日が必要です")
    }

    @Test func priorityIsSentForRemindersOnly() async {
        let source = EditingSource()
        let reminder = makeModel(item(kind: .reminder, start: tuesday10), source: source)
        reminder.priority = .high
        #expect(await reminder.save())
        #expect(source.updates.last?.draft.priority == .high)

        let event = makeModel(item(kind: .event, start: tuesday10, end: date(2026, 11, 10, 11)), source: source)
        event.priority = .high
        #expect(await event.save())
        #expect(source.updates.last?.draft.priority == ReminderPriority.none)
    }

    @Test func unsupportedRecurrenceIsShownButNotSent() {
        let model = makeModel(item(kind: .event, start: tuesday10, recurrence: nil, hasRecurrence: true))
        #expect(model.recurrence == .unsupported)
        #expect(model.recurrenceOptions.contains(.unsupported))
        #expect(model.draft.recurrence == nil)
    }

    @Test func undatedReminderDefaultsToNineAndStaysUndatedUntilToggled() {
        let model = makeModel(item(kind: .reminder, start: nil))
        #expect(model.hasDate == false)
        #expect(model.start == date(2026, 11, 10, 9))
        #expect(model.draft.start == nil)

        model.hasDate = true
        model.isAllDay = true
        #expect(model.draft.start == date(2026, 11, 10))
        #expect(model.draft.isAllDay)
    }

    @Test func allDayEventDraftUsesDayBoundaries() {
        let model = makeModel(item(kind: .event, start: tuesday10, end: date(2026, 11, 10, 11)))
        model.isAllDay = true
        #expect(model.draft.start == date(2026, 11, 10))
        #expect(model.draft.end == date(2026, 11, 10))
        #expect(model.validationMessage == nil)
    }

    @Test func saveSendsDraftAndSpanThenNotifies() async {
        let source = EditingSource()
        let original = item(kind: .event, start: tuesday10, end: date(2026, 11, 10, 11), recurrence: .init(frequency: .weekly, weekdays: [3]))
        let model = makeModel(original, source: source)
        var changed = 0
        model.onChanged = { changed += 1 }
        model.title = "  面談（延期） "
        model.recurrence = .biweekly
        model.destinationID = "cal-2"

        let ok = await model.save(span: .futureOccurrences)

        #expect(ok)
        #expect(source.updates.count == 1)
        #expect(source.updates[0].item == original)
        #expect(source.updates[0].span == .futureOccurrences)
        #expect(source.updates[0].draft.title == "面談（延期）")
        #expect(source.updates[0].draft.recurrence == RecurrenceSpec(frequency: .weekly, interval: 2, weekdays: [3]))
        #expect(source.updates[0].draft.calendarID == "cal-2")
        #expect(changed == 1)
    }

    @Test func validationBlocksSave() async {
        let source = EditingSource()
        let model = makeModel(item(kind: .event, start: tuesday10, end: date(2026, 11, 10, 11)), source: source)

        model.title = " "
        #expect(await model.save() == false)
        #expect(model.errorMessage == "タイトルを入力してください")

        model.title = "面談"
        model.end = date(2026, 11, 10, 9)
        #expect(await model.save() == false)
        #expect(model.errorMessage == "終了は開始より前にはできません")

        let reminder = makeModel(item(kind: .reminder, start: nil), source: source)
        reminder.recurrence = .daily
        #expect(await reminder.save() == false)
        #expect(reminder.errorMessage == "繰り返しのあるリマインダーには期日が必要です")

        #expect(source.updates.isEmpty)
    }

    @Test func failureShowsMessageAndDoesNotNotify() async {
        let source = EditingSource()
        source.error = TestError()
        let model = makeModel(item(kind: .reminder, start: tuesday10), source: source)
        var changed = 0
        model.onChanged = { changed += 1 }

        #expect(await model.save() == false)
        #expect(model.errorMessage == "boom")
        #expect(await model.delete() == false)
        #expect(changed == 0)
    }

    @Test func deleteSendsSpan() async {
        let source = EditingSource()
        let model = makeModel(item(kind: .event, start: tuesday10, end: date(2026, 11, 10, 11)), source: source)

        #expect(await model.delete(span: .thisOccurrence))
        #expect(source.deletes.count == 1)
        #expect(source.deletes[0].span == .thisOccurrence)
    }

    @Test func destinationsAreFilteredByKind() async {
        let source = EditingSource()
        source.destinationList = [
            Destination(id: "l", name: "家族", kind: .reminder, color: CGColor(gray: 0, alpha: 1)),
            Destination(id: "c", name: "仕事", kind: .event, color: CGColor(gray: 0, alpha: 1)),
        ]
        let model = makeModel(item(kind: .event, start: tuesday10), source: source)

        await model.loadDestinations()

        #expect(model.destinations.map(\.id) == ["c"])
    }
}

@Suite struct RecurrenceRuleImportTests {
    @Test func simpleRulesRoundTrip() {
        let specs: [RecurrenceSpec] = [
            .init(frequency: .daily, interval: 3),
            .init(frequency: .weekly, weekdays: [2, 4, 6]),
            .init(frequency: .weekly, interval: 2, weekdays: [3]),
            .init(frequency: .monthly, daysOfMonth: [15]),
            .init(frequency: .monthly, weekdays: [6], weekOfMonth: -1),
            .init(frequency: .monthly, weekdays: [3], weekOfMonth: 2),
        ]
        for spec in specs {
            #expect(RecurrenceSpec(rule: EKRecurrenceRule(spec)) == spec)
        }
    }

    @Test func lastWeekdayViaSetPositionsIsImported() {
        let rule = EKRecurrenceRule(
            recurrenceWith: .monthly, interval: 1,
            daysOfTheWeek: [EKRecurrenceDayOfWeek(.friday)], daysOfTheMonth: nil,
            monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil,
            setPositions: [-1], end: nil
        )
        #expect(RecurrenceSpec(rule: rule) == RecurrenceSpec(frequency: .monthly, weekdays: [6], weekOfMonth: -1))
    }

    @Test func positionalRulesWithSeveralWeekdaysAndNegativeDaysAreUnsupported() {
        let severalWeekdays = EKRecurrenceRule(
            recurrenceWith: .monthly, interval: 1,
            daysOfTheWeek: [EKRecurrenceDayOfWeek(.monday), EKRecurrenceDayOfWeek(.friday)], daysOfTheMonth: nil,
            monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil,
            setPositions: [-1], end: nil
        )
        #expect(RecurrenceSpec(rule: severalWeekdays) == nil)

        let lastDay = EKRecurrenceRule(
            recurrenceWith: .monthly, interval: 1,
            daysOfTheWeek: nil, daysOfTheMonth: [-1],
            monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil,
            setPositions: nil, end: nil
        )
        #expect(RecurrenceSpec(rule: lastDay) == nil)
    }

    @Test func describesSpecsInJapanese() {
        #expect(RecurrenceSpec(frequency: .daily).localizedDescription == "毎日")
        #expect(RecurrenceSpec(frequency: .daily, interval: 3).localizedDescription == "3日ごと")
        #expect(RecurrenceSpec(frequency: .weekly).localizedDescription == "毎週")
        #expect(RecurrenceSpec(frequency: .weekly, weekdays: [2, 3, 4, 5, 6]).localizedDescription == "平日")
        #expect(RecurrenceSpec(frequency: .weekly, interval: 2, weekdays: [3]).localizedDescription == "隔週火曜")
        #expect(RecurrenceSpec(frequency: .monthly, daysOfMonth: [15]).localizedDescription == "毎月15日")
        #expect(RecurrenceSpec(frequency: .monthly, weekdays: [6], weekOfMonth: -1).localizedDescription == "毎月最終金曜")
        #expect(RecurrenceSpec(frequency: .monthly, interval: 2).localizedDescription == "2か月ごと")
    }

    @Test func yearlyAndEndedRulesAreUnsupported() {
        #expect(RecurrenceSpec(rule: EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)) == nil)
        let ended = EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 5))
        #expect(RecurrenceSpec(rule: ended) == nil)
    }
}
