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
    private(set) var creates: [ItemDraft] = []
    func create(_ draft: ItemDraft) async throws {
        if let error { throw error }
        creates.append(draft)
    }
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
        color: CGColor(gray: 0, alpha: 1), recurrence: recurrence,
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

    @Test func earlyReminderFollowsTheDueDate() async {
        var reminderItem = item(kind: .reminder, start: tuesday10)
        reminderItem.earlyReminderMinutes = 15
        let model = makeModel(reminderItem)
        #expect(model.earlyReminderMinutes == 15)
        #expect(model.draft.earlyReminderMinutes == 15)

        model.earlyReminderMinutes = 60
        #expect(model.draft.earlyReminderMinutes == 60)

        // 期日を外す・時刻なしにすると鳴る時刻が定まらないので付けない。なし（0）は nil
        model.hasDate = false
        #expect(model.draft.earlyReminderMinutes == nil)
        model.hasDate = true
        model.isAllDay = true
        #expect(model.draft.earlyReminderMinutes == nil)
        model.isAllDay = false
        model.earlyReminderMinutes = 0
        #expect(model.draft.earlyReminderMinutes == nil)

        let event = makeModel(item(kind: .event, start: tuesday10, end: date(2026, 11, 10, 11)))
        #expect(event.draft.earlyReminderMinutes == nil)
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

    /// 削除は自分では行わず、タイムラインへ任せる（取り消せるよう、実際の削除を遅らせるため）。
    @Test func deleteHandsTheItemAndSpanToTheHandler() async {
        let source = EditingSource()
        let event = item(kind: .event, start: tuesday10, end: date(2026, 11, 10, 11))
        let model = makeModel(event, source: source)
        var handed: [(item: TimelineItem, span: EditSpan)] = []
        model.onDelete = {
            handed.append(($0, $1))
            return true
        }

        #expect(await model.delete(span: .futureOccurrences))

        #expect(handed.map(\.item) == [event])
        #expect(handed.map(\.span) == [.futureOccurrences])
        #expect(source.deletes.isEmpty)
    }

    /// 任せた先が受けなかったら（別の保存の最中など）、閉じずに知らせる。黙って閉じると、消えたと思い込む。
    @Test func deleteReportsWhenTheHandlerDidNotTakeTheItem() async {
        let source = EditingSource()
        let model = makeModel(item(kind: .event, start: tuesday10, end: date(2026, 11, 10, 11)), source: source)
        model.onDelete = { _, _ in false }

        #expect(await model.delete() == false)
        #expect(model.errorMessage != nil)
    }

    @Test func deleteDoesNothingWithoutAHandler() async {
        let source = EditingSource()
        let model = makeModel(item(kind: .event, start: tuesday10, end: date(2026, 11, 10, 11)), source: source)

        #expect(await model.delete() == false)
        #expect(source.deletes.isEmpty)
    }

    @Test func theLocationIsKeptAsItIsOnSave() {
        var meeting = item(kind: .event, start: date(2026, 11, 12, 10), end: date(2026, 11, 12, 11))
        meeting.location = "会議室 A"
        let model = ItemEditorModel(item: meeting, source: EditingSource(), calendar: tokyo)

        #expect(model.location == "会議室 A")
        #expect(model.draft.location == "会議室 A")
    }

    @Test(arguments: [
        ("牧ノ戸峠, 日本、〒879-4911 大分県玖珠郡九重町田野 牧ノ戸峠", "牧ノ戸峠", "日本、〒879-4911 大分県玖珠郡九重町田野 牧ノ戸峠"),
        ("A, B, C", "A", "B, C"),
        ("会議室 A", "会議室 A", ""),
        ("会議室 A,", "会議室 A", ""),
        (", B", ", B", ""),
    ])
    func theLocationSplitsAtItsFirstComma(location: String, name: String, rest: String) {
        var meeting = item(kind: .event, start: date(2026, 11, 12, 10), end: date(2026, 11, 12, 11))
        meeting.location = location
        let model = ItemEditorModel(item: meeting, source: EditingSource(), calendar: tokyo)

        #expect(model.locationName == name)
        #expect(model.locationDetail == rest)
    }

    @Test func theLocationOpensAsAGoogleMapsSearch() {
        var meeting = item(kind: .event, start: date(2026, 11, 12, 10), end: date(2026, 11, 12, 11))
        meeting.location = "東京駅 丸の内口&q=x"
        let url = ItemEditorModel(item: meeting, source: EditingSource(), calendar: tokyo).locationMapURL

        #expect(url?.host() == "www.google.com")
        #expect(url?.path() == "/maps/search/")
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
        #expect(items == [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: "東京駅 丸の内口&q=x")])

        meeting.location = "  "
        #expect(ItemEditorModel(item: meeting, source: EditingSource(), calendar: tokyo).locationMapURL == nil)
    }

    @Test(arguments: [
        ("https://maps.google.com/?daddr=35.8,140.1", true),
        ("http://example.com/a", true),
        ("file:///etc/passwd", false),
        ("javascript:alert(1)", false),
    ])
    func onlyWebLinksAreOffered(link: String, offered: Bool) {
        var meeting = item(kind: .event, start: date(2026, 11, 12, 10), end: date(2026, 11, 12, 11))
        meeting.url = URL(string: link)
        let model = ItemEditorModel(item: meeting, source: EditingSource(), calendar: tokyo)

        #expect((model.linkURL != nil) == offered)
    }

    @Test func theURLOfAnEventIsEditedThroughTheDraft() {
        var meeting = item(kind: .event, start: date(2026, 11, 12, 10), end: date(2026, 11, 12, 11))
        meeting.url = URL(string: "https://example.com/a")
        let model = ItemEditorModel(item: meeting, source: EditingSource(), calendar: tokyo)

        #expect(model.urlText == "https://example.com/a")
        #expect(model.draft.url == URL(string: "https://example.com/a"))

        model.urlText = " https://example.com/b "
        #expect(model.draft.url == URL(string: "https://example.com/b"))
        #expect(model.validationMessage == nil)

        model.urlText = ""
        #expect(model.draft.url == nil)
        #expect(model.validationMessage == nil)

        model.urlText = "example.com"
        #expect(model.validationMessage != nil)
    }

    @Test func theConferenceBlockIsHiddenFromTheNotesAndKeptOnSave() {
        let line = "-::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-"
        let block = "\(line)\nGoogle Meet に参加: https://meet.google.com/abc-defg-hij\n\(line)"
        var meeting = item(kind: .event, start: date(2026, 11, 12, 10), end: date(2026, 11, 12, 11))
        meeting.notes = "議題\n\n\(block)"
        let model = ItemEditorModel(item: meeting, source: EditingSource(), calendar: tokyo)

        #expect(model.notes == "議題")
        #expect(model.conferenceURL == URL(string: "https://meet.google.com/abc-defg-hij"))
        #expect(model.draft.notes == "議題\n\n\(block)")

        model.notes = "議題を変更"
        #expect(model.draft.notes == "議題を変更\n\n\(block)")
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

@MainActor
@Suite struct NewItemEditorModelTests {
    let thursday10 = date(2026, 11, 12, 10)

    private func makeModel(
        kind: ItemKind = .event, isAllDay: Bool = false, earlyReminder: Int = 0, source: EditingSource = EditingSource()
    ) -> ItemEditorModel {
        ItemEditorModel(
            newItemOf: kind, start: thursday10, isAllDay: isAllDay,
            defaultEarlyReminderMinutes: earlyReminder, source: source, calendar: tokyo
        )
    }

    @Test func aNewEventStartsEmptyWithOneHour() {
        let model = makeModel()
        #expect(model.isNew)
        #expect(model.kind == .event)
        #expect(model.title == "")
        #expect(model.start == thursday10)
        #expect(model.end == date(2026, 11, 12, 11))
        #expect(model.recurrence == .none)
        #expect(model.needsSpanChoice == false)
    }

    @Test func savingANewEventCreatesItInTheDefaultCalendar() async {
        let source = EditingSource()
        let model = makeModel(source: source)
        model.title = "面談"
        var changed = 0
        model.onChanged = { changed += 1 }

        let done = await model.save()

        #expect(done)
        #expect(source.updates.isEmpty)
        #expect(source.creates == [ItemDraft(
            kind: .event, title: "面談", start: thursday10, end: date(2026, 11, 12, 11), notes: ""
        )])
        #expect(changed == 1)
    }

    @Test func anEmptyTitleCreatesNothing() async {
        let source = EditingSource()
        let model = makeModel(source: source)

        let done = await model.save()

        #expect(done == false)
        #expect(source.creates.isEmpty)
        #expect(model.errorMessage == "タイトルを入力してください")
    }

    @Test func switchingToReminderKeepsWhatWasTypedAndDropsTheEnd() async {
        let source = EditingSource()
        source.destinationList = [
            Destination(id: "cal", name: "仕事", kind: .event, color: CGColor(gray: 0, alpha: 1)),
            Destination(id: "list", name: "家族", kind: .reminder, color: CGColor(gray: 0, alpha: 1)),
        ]
        let model = makeModel(earlyReminder: 10, source: source)
        await model.loadDestinations()
        #expect(model.destinations.map(\.id) == ["cal"])
        model.title = "ゴミ出し"
        model.destinationID = "cal"

        await model.setKind(.reminder)

        #expect(model.kind == .reminder)
        #expect(model.title == "ゴミ出し")
        #expect(model.destinations.map(\.id) == ["list"])
        // 予定のカレンダーはリマインダーの保存先にできないので既定に戻す
        #expect(model.destinationID == "")
        _ = await model.save()
        #expect(source.creates == [ItemDraft(
            kind: .reminder, title: "ゴミ出し", start: thursday10, notes: "", earlyReminderMinutes: 10
        )])
    }

    @Test func aNewAllDayReminderHasNoTimeAndNoEarlyReminder() async {
        let source = EditingSource()
        let model = makeModel(kind: .reminder, isAllDay: true, earlyReminder: 10, source: source)
        model.title = "支払い"

        _ = await model.save()

        #expect(source.creates == [ItemDraft(
            kind: .reminder, title: "支払い", start: date(2026, 11, 12), isAllDay: true, notes: ""
        )])
    }

    @Test func aNewAllDayEventCoversThatDay() async {
        let source = EditingSource()
        let model = makeModel(isAllDay: true, source: source)
        model.title = "出張"

        _ = await model.save()

        #expect(source.creates.first?.start == date(2026, 11, 12))
        #expect(source.creates.first?.end == date(2026, 11, 12))
        #expect(source.creates.first?.isAllDay == true)
    }

    @Test func theKindOfAnExistingItemCannotBeChanged() async {
        let existing = item(kind: .event, start: thursday10, end: date(2026, 11, 12, 11))
        let model = ItemEditorModel(item: existing, source: EditingSource(), calendar: tokyo, now: thursday10)

        await model.setKind(.reminder)

        #expect(model.isNew == false)
        #expect(model.kind == .event)
    }
}
