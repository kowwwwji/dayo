import EventKit
import Foundation
import Testing
@testable import DayoCore

private final class RecordingSource: CalendarSource {
    private(set) var drafts: [ItemDraft] = []
    var createError: Error?
    var destinationList: [Destination] = []

    func requestAccess() async throws -> AccessStatus { .granted }
    func snapshot(for range: DateInterval, includingOverdue: Bool) async throws -> TimelineSnapshot { .empty }
    func setCompleted(_ completed: Bool, for item: TimelineItem) async throws {}
    func create(_ draft: ItemDraft) async throws {
        if let createError { throw createError }
        drafts.append(draft)
    }
    func update(_ item: TimelineItem, with draft: ItemDraft, span: EditSpan) async throws {}
    func delete(_ item: TimelineItem, span: EditSpan) async throws {}
    func destinations() async throws -> [Destination] { destinationList }
    var changes: AsyncStream<Void> { AsyncStream { _ in } }
}

private func destination(_ name: String, _ kind: ItemKind) -> Destination {
    Destination(id: "\(kind)-\(name)", name: name, kind: kind, color: CGColor(gray: 0, alpha: 1))
}

private struct TestError: LocalizedError {
    var errorDescription: String? { "boom" }
}

private let tokyo: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
}()

private let reference = tokyo.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 10))!

@MainActor
@Suite struct QuickInputModelTests {
    private func makeModel(_ source: RecordingSource) -> QuickInputModel {
        QuickInputModel(source: source, calendar: tokyo, now: { reference })
    }

    @Test func emptyTextHasNoPreview() {
        let model = makeModel(RecordingSource())
        model.text = "   "
        #expect(model.parsed == nil)
    }

    @Test func previewReflectsText() {
        let model = makeModel(RecordingSource())
        model.text = "明日 15時 歯医者 #家族"
        #expect(model.parsed?.title == "歯医者")
        #expect(model.parsed?.listName == "家族")
    }

    @Test func submitCreatesDraftClearsTextAndNotifies() async {
        let source = RecordingSource()
        let model = makeModel(source)
        var created = 0
        model.onCreated = { created += 1 }
        model.text = "明日 15時 歯医者"

        await model.submit()

        #expect(source.drafts.count == 1)
        #expect(source.drafts.first?.title == "歯医者")
        #expect(source.drafts.first?.start == tokyo.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 15)))
        #expect(model.text.isEmpty)
        #expect(model.errorMessage == nil)
        #expect(created == 1)
    }

    @Test func submitFailureKeepsTextAndShowsErrorUntilEdited() async {
        let source = RecordingSource()
        source.createError = TestError()
        let model = makeModel(source)
        var created = 0
        model.onCreated = { created += 1 }
        model.text = "牛乳買う"

        await model.submit()

        #expect(model.text == "牛乳買う")
        #expect(model.errorMessage == "boom")
        #expect(created == 0)

        model.text = "牛乳買う 2本"
        #expect(model.errorMessage == nil)
    }

    @Test func suggestionsFollowTrailingMarkerToken() async {
        let source = RecordingSource()
        source.destinationList = [
            destination("家族", .reminder), destination("買い物", .reminder), destination("仕事", .reminder),
            destination("個人的", .event), destination("Work", .event),
        ]
        let model = makeModel(source)
        await model.loadDestinations()

        model.text = "歯医者"
        #expect(model.suggestions.isEmpty)

        model.text = "歯医者 #"
        #expect(model.suggestions.map(\.name) == ["家族", "仕事", "買い物"])

        model.text = "歯医者 #家"
        #expect(model.suggestions.map(\.name) == ["家族"])

        model.text = "面談 @"
        #expect(model.suggestions.map(\.name) == ["Work", "個人的"])

        model.text = "面談 @w"
        #expect(model.suggestions.map(\.name) == ["Work"])

        // 日本語入力の全角記号でも出る
        model.text = "歯医者　＃家"
        #expect(model.suggestions.map(\.name) == ["家族"])
        model.text = "面談 ＠"
        #expect(model.suggestions.map(\.name) == ["Work", "個人的"])

        // 打ち終えた名前は候補に出さない。空白を打ったら候補は閉じる
        model.text = "面談 @Work"
        #expect(model.suggestions.isEmpty)
        model.text = "面談 @Wo "
        #expect(model.suggestions.isEmpty)
    }

    @Test func applyingSuggestionReplacesTokenAndAddsSpace() async {
        let source = RecordingSource()
        source.destinationList = [destination("家族", .reminder)]
        let model = makeModel(source)
        await model.loadDestinations()
        model.text = "明日 歯医者 #家"

        model.apply(model.suggestions[0])

        #expect(model.text == "明日 歯医者 #家族 ")
        #expect(model.suggestions.isEmpty)

        // 全角で打った印は半角に直して補完する
        model.text = "明日 歯医者 ＃"
        model.apply(model.suggestions[0])
        #expect(model.text == "明日 歯医者 #家族 ")
    }

    @Test func tabCyclesSuggestionsAndReturnAppliesTheSelectedOne() async {
        let source = RecordingSource()
        source.destinationList = [destination("家族", .reminder), destination("仕事", .reminder)]
        let model = makeModel(source)
        await model.loadDestinations()
        model.text = "歯医者 #"

        // 選んでいなければ Return は登録へ
        #expect(model.applySelectedSuggestion() == false)

        model.selectNextSuggestion()
        #expect(model.selectedSuggestionID == destination("家族", .reminder).id)
        model.selectNextSuggestion()
        #expect(model.selectedSuggestionID == destination("仕事", .reminder).id)
        model.selectNextSuggestion()
        #expect(model.selectedSuggestionID == destination("家族", .reminder).id)
        // Shift+Tab で戻る。先頭から戻ると末尾
        model.selectPreviousSuggestion()
        #expect(model.selectedSuggestionID == destination("仕事", .reminder).id)
        model.selectPreviousSuggestion()
        #expect(model.selectedSuggestionID == destination("家族", .reminder).id)

        #expect(model.applySelectedSuggestion())
        #expect(model.text == "歯医者 #家族 ")
        #expect(model.selectedSuggestionID == nil)
    }

    @Test func editingTextDropsSelection() async {
        let source = RecordingSource()
        source.destinationList = [destination("家族", .reminder)]
        let model = makeModel(source)
        await model.loadDestinations()
        model.text = "歯医者 #"
        model.selectNextSuggestion()

        model.text = "歯医者 #家"

        #expect(model.selectedSuggestionID == nil)
    }

    @Test func defaultEarlyReminderAppliesOnlyToTimedReminders() async {
        let source = RecordingSource()
        let model = makeModel(source)
        model.defaultEarlyReminderMinutes = 15

        model.text = "明日 15時 歯医者"
        await model.submit()
        #expect(source.drafts.last?.earlyReminderMinutes == 15)

        model.text = "明日 歯医者"
        await model.submit()
        #expect(source.drafts.last?.earlyReminderMinutes == nil)

        model.text = "明日 15時 面談 @予定"
        await model.submit()
        #expect(source.drafts.last?.earlyReminderMinutes == nil)

        model.defaultEarlyReminderMinutes = 0
        model.text = "明日 15時 歯医者"
        await model.submit()
        #expect(source.drafts.last?.earlyReminderMinutes == nil)
    }

    @Test func submitWithoutTitleIsRejected() async {
        let source = RecordingSource()
        let model = makeModel(source)
        model.text = "明日 15時"

        await model.submit()

        #expect(source.drafts.isEmpty)
        #expect(model.errorMessage != nil)
        #expect(model.text == "明日 15時")
    }
}

@Suite struct EventKitRepositoryCreateHelpersTests {
    @Test func dueComponentsRoundTripThroughReminderMapping() {
        let start = tokyo.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 15, minute: 30))!
        let timed = EventKitRepository.dueComponents(for: start, allDay: false, timeZone: tokyo.timeZone)
        #expect(timed.hour == 15 && timed.minute == 30 && timed.timeZone == nil)
        #expect(TimelineItem.date(from: timed, defaultTimeZone: tokyo.timeZone) == start)

        let allDay = EventKitRepository.dueComponents(for: start, allDay: true, timeZone: tokyo.timeZone)
        #expect(allDay.hour == nil)
        #expect(allDay.day == 11)
    }

    @Test func earlyReminderAlarmsAreReplacedOnlyWhenTheValueChanges() {
        func item(_ minutes: Int?, dated: Bool = true) -> TimelineItem {
            TimelineItem(
                id: "x", calendarItemIdentifier: "x", kind: .reminder, title: "", start: dated ? Date() : nil, end: nil,
                isAllDay: false, isCompleted: false, sourceName: "", accountName: "",
                color: CGColor(gray: 0, alpha: 1), recurrence: nil, earlyReminderMinutes: minutes
            )
        }
        func draft(_ minutes: Int?, dated: Bool = true) -> ItemDraft {
            ItemDraft(kind: .reminder, title: "", start: dated ? Date() : nil, earlyReminderMinutes: minutes)
        }
        // 新規は常に付ける。更新は値が変わったときだけ。期日が消えたら外す
        #expect(EventKitRepository.shouldReplaceEarlyReminder(previous: nil, draft: draft(15)))
        #expect(EventKitRepository.shouldReplaceEarlyReminder(previous: item(15), draft: draft(15)) == false)
        #expect(EventKitRepository.shouldReplaceEarlyReminder(previous: item(15), draft: draft(60)))
        #expect(EventKitRepository.shouldReplaceEarlyReminder(previous: item(nil), draft: draft(nil)) == false)
        // 期日を外した・時刻なしにした場合はエディタが draft を nil にするので変化として拾う
        #expect(EventKitRepository.shouldReplaceEarlyReminder(previous: item(15), draft: draft(nil, dated: false)))
    }

    @Test func earlyReminderLabels() {
        #expect(EarlyReminder(minutes: nil) == .none)
        #expect(EarlyReminder(minutes: 0) == .none)
        #expect(EarlyReminder(minutes: 15).label == "15分前")
        #expect(EarlyReminder(minutes: 120).label == "2時間前")
        #expect(EarlyReminder(minutes: 1440).label == "1日前")
        #expect(EarlyReminder.none.label == "なし")
        #expect(EarlyReminder(minutes: 45).minutes == 45)
    }

    @Test func calendarMatchPrefersExactThenPrefixIgnoringCase() {
        let titles = ["Work", "家族", "家計簿", "work-side"]
        #expect(EventKitRepository.match("work", in: titles, title: { $0 }) == "Work")
        #expect(EventKitRepository.match("家", in: titles, title: { $0 }) == "家族")
        #expect(EventKitRepository.match("家計", in: titles, title: { $0 }) == "家計簿")
        #expect(EventKitRepository.match("仕事", in: titles, title: { $0 }) == nil)
    }
}

@Suite struct RecurrenceRuleConversionTests {
    @Test func weeklyWithWeekdays() {
        let rule = EKRecurrenceRule(RecurrenceSpec(frequency: .weekly, interval: 2, weekdays: [2, 4, 6]))
        #expect(rule.frequency == .weekly)
        #expect(rule.interval == 2)
        #expect(rule.daysOfTheWeek?.map { $0.dayOfTheWeek.rawValue } == [2, 4, 6])
        #expect(rule.daysOfTheWeek?.map(\.weekNumber) == [0, 0, 0])
        #expect(rule.daysOfTheMonth == nil)
    }

    @Test func monthlyLastFriday() {
        let rule = EKRecurrenceRule(RecurrenceSpec(frequency: .monthly, weekdays: [6], weekOfMonth: -1))
        #expect(rule.frequency == .monthly)
        #expect(rule.daysOfTheWeek?.map { ($0.dayOfTheWeek.rawValue, $0.weekNumber) }.first ?? (0, 0) == (6, -1))
    }

    @Test func monthlyByDayAndEveryNDays() {
        let monthly = EKRecurrenceRule(RecurrenceSpec(frequency: .monthly, daysOfMonth: [15]))
        #expect(monthly.daysOfTheMonth == [15])
        #expect(monthly.daysOfTheWeek == nil)

        let daily = EKRecurrenceRule(RecurrenceSpec(frequency: .daily, interval: 3))
        #expect(daily.frequency == .daily)
        #expect(daily.interval == 3)
    }
}
