import CoreGraphics
import Foundation
import Testing
@testable import DayoCore

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func iso(_ string: String) -> Date {
    ISO8601DateFormatter().date(from: string)!
}

private func item(
    _ id: String, kind: ItemKind = .event, _ start: String, _ end: String? = nil, allDay: Bool = false
) -> TimelineItem {
    TimelineItem(
        id: id, calendarItemIdentifier: id, kind: kind, title: id,
        start: iso(start), end: end.map(iso), isAllDay: allDay, isCompleted: false,
        sourceName: "", accountName: "", color: CGColor(gray: 0, alpha: 1), recurrence: nil
    )
}

@Suite struct TimelineColumnsTests {
    /// 2026-11-08（日）〜 11-14（土）。
    let days = (8...14).map { iso("2026-11-\(String(format: "%02d", $0))T00:00:00Z") }

    private func columns(_ items: [TimelineItem]) -> [TimelineColumn] {
        TimelineColumns.columns(for: items, days: days, calendar: utc)
    }

    private func spans(_ items: [TimelineItem]) -> [AllDaySpan] {
        TimelineColumns.allDaySpans(for: items, days: days, calendar: utc)
    }

    @Test func makesOneColumnPerDayInOrder() {
        let result = columns([])
        #expect(result.map(\.day) == days)
        #expect(result.map(\.placements.count) == [0, 0, 0, 0, 0, 0, 0])
    }

    @Test func placesTimedItemsInTheirDayWithMinutesFromThatMidnight() {
        let result = columns([
            item("tue", "2026-11-10T10:00:00Z", "2026-11-10T11:00:00Z"),
            item("fri", kind: .reminder, "2026-11-13T09:30:00Z"),
        ])
        #expect(result[2].placements.map(\.id) == ["tue"])
        #expect(result[2].placements.map(\.startMinute) == [600])
        #expect(result[5].placements.map(\.id) == ["fri"])
        #expect(result[5].placements.map(\.startMinute) == [570])
        #expect(result.map(\.placements.count) == [0, 0, 1, 0, 0, 1, 0])
    }

    @Test func overlapsAreResolvedPerDay() {
        let result = columns([
            item("a", "2026-11-10T10:00:00Z", "2026-11-10T12:00:00Z"),
            item("b", "2026-11-10T11:00:00Z", "2026-11-10T13:00:00Z"),
            item("c", "2026-11-11T10:00:00Z", "2026-11-11T12:00:00Z"),
        ])
        #expect(result[2].placements.map(\.columnCount) == [2, 2])
        #expect(result[3].placements.map(\.columnCount) == [1])
    }

    @Test func splitsATimedItemCrossingMidnightIntoEachDay() {
        let result = columns([item("night", "2026-11-10T22:00:00Z", "2026-11-12T02:00:00Z")])
        #expect(result.map(\.placements.count) == [0, 0, 1, 1, 1, 0, 0])
        #expect(result[2].placements.map(\.startMinute) == [1320])
        #expect(result[2].placements.map(\.endMinute) == [1440])
        #expect(result[3].placements.map(\.startMinute) == [0])
        #expect(result[3].placements.map(\.endMinute) == [1440])
        #expect(result[4].placements.map(\.endMinute) == [120])
    }

    @Test func allDayItemsAreNotPlacedInColumns() {
        let result = columns([item("trip", "2026-11-09T00:00:00Z", "2026-11-10T23:59:59Z", allDay: true)])
        #expect(result.map(\.placements.count) == [0, 0, 0, 0, 0, 0, 0])
    }

    @Test func aSingleDayColumnBehavesLikeTheDayView() {
        let result = TimelineColumns.columns(
            for: [item("a", "2026-11-10T10:00:00Z", "2026-11-10T11:00:00Z")], days: [days[2]], calendar: utc
        )
        #expect(result.map(\.day) == [days[2]])
        #expect(result[0].placements.map(\.startMinute) == [600])
    }

    @Test func allDaySpanCoversItsDays() {
        let result = spans([
            item("trip", "2026-11-09T00:00:00Z", "2026-11-11T23:59:59Z", allDay: true),
            item("due", kind: .reminder, "2026-11-13T00:00:00Z", allDay: true),
        ])
        #expect(result.map(\.id) == ["trip", "due"])
        #expect(result.map(\.firstColumn) == [1, 5])
        #expect(result.map(\.columnSpan) == [3, 1])
        #expect(result.map(\.lane) == [0, 0])
    }

    @Test func allDaySpanEndingAtMidnightDoesNotSpillIntoTheNextDay() {
        // 終了を翌日 0:00 で持つ取得元もある
        let result = spans([item("day", "2026-11-10T00:00:00Z", "2026-11-11T00:00:00Z", allDay: true)])
        #expect(result.map(\.firstColumn) == [2])
        #expect(result.map(\.columnSpan) == [1])
    }

    @Test func allDaySpanIsClippedToTheVisibleDays() {
        let result = spans([
            item("before", "2026-11-05T00:00:00Z", "2026-11-09T23:59:59Z", allDay: true),
            item("after", "2026-11-13T00:00:00Z", "2026-11-20T23:59:59Z", allDay: true),
            item("outside", "2026-11-01T00:00:00Z", "2026-11-02T23:59:59Z", allDay: true),
        ])
        #expect(result.map(\.id) == ["before", "after"])
        #expect(result.map(\.firstColumn) == [0, 5])
        #expect(result.map(\.columnSpan) == [2, 2])
    }

    @Test func overlappingSpansTakeSeparateLanesAndFreeLanesAreReused() {
        let result = spans([
            item("short", "2026-11-10T00:00:00Z", "2026-11-10T23:59:59Z", allDay: true),
            item("long", "2026-11-09T00:00:00Z", "2026-11-11T23:59:59Z", allDay: true),
            item("later", "2026-11-12T00:00:00Z", "2026-11-12T23:59:59Z", allDay: true),
        ])
        #expect(result.map(\.id) == ["long", "short", "later"])
        #expect(result.map(\.lane) == [0, 1, 0])
    }

    @Test func sameDaySpansPutEventsBeforeReminders() {
        let result = spans([
            item("b-reminder", kind: .reminder, "2026-11-10T00:00:00Z", allDay: true),
            item("a-event", "2026-11-10T00:00:00Z", "2026-11-10T23:59:59Z", allDay: true),
        ])
        #expect(result.map(\.id) == ["a-event", "b-reminder"])
        #expect(result.map(\.lane) == [0, 1])
    }

    @Test func timedItemsDoNotBecomeSpans() {
        #expect(spans([item("a", "2026-11-10T10:00:00Z", "2026-11-10T11:00:00Z")]).isEmpty)
    }
}
