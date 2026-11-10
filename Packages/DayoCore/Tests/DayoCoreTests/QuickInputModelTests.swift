import EventKit
import Foundation
import Testing
@testable import DayoCore

private final class RecordingSource: CalendarSource {
    private(set) var drafts: [ItemDraft] = []
    var createError: Error?

    func requestAccess() async throws -> AccessStatus { .granted }
    func snapshot(for range: DateInterval, includingOverdue: Bool) async throws -> TimelineSnapshot { .empty }
    func setCompleted(_ completed: Bool, for item: TimelineItem) async throws {}
    func create(_ draft: ItemDraft) async throws {
        if let createError { throw createError }
        drafts.append(draft)
    }
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
