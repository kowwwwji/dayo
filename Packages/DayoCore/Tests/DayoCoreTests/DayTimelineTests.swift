import CoreGraphics
import Foundation
import Testing
@testable import DayoCore

private func iso(_ string: String) -> Date {
    ISO8601DateFormatter().date(from: string)!
}

private func make(
    _ id: String,
    kind: ItemKind = .reminder,
    start: Date? = nil,
    isAllDay: Bool = false,
    title: String = ""
) -> TimelineItem {
    TimelineItem(
        id: id, calendarItemIdentifier: id, kind: kind, title: title.isEmpty ? id : title,
        start: start, end: nil, isAllDay: isAllDay, isCompleted: false,
        sourceName: "", accountName: "", color: CGColor(gray: 0, alpha: 1),
        recurrence: nil, isShared: false
    )
}

@Suite struct DayTimelineTests {
    let t9 = iso("2026-11-10T09:00:00Z")
    let t10 = iso("2026-11-10T10:00:00Z")
    let t15 = iso("2026-11-10T15:00:00Z")

    @Test func splitsIntoSections() {
        let allDay = make("allday", kind: .event, start: iso("2026-11-10T00:00:00Z"), isAllDay: true)
        let dated = make("dated", start: t9)
        let undated = make("undated")
        let overdue = make("overdue", start: iso("2026-11-08T09:00:00Z"))

        let timeline = DayTimeline(items: [undated, dated, allDay], overdue: [overdue])

        #expect(timeline.allDay == [allDay])
        #expect(timeline.overdue == [overdue])
        #expect(timeline.timed == [dated])
        #expect(timeline.undated == [undated])
    }

    @Test func timedSortedByStartThenEventBeforeReminderThenID() {
        let r10 = make("r10", kind: .reminder, start: t10)
        let e10 = make("e10", kind: .event, start: t10)
        let e9b = make("e9b", kind: .event, start: t9)
        let e9a = make("e9a", kind: .event, start: t9)
        let r15 = make("r15", start: t15)

        let timeline = DayTimeline(items: [r15, r10, e9b, e10, e9a], overdue: [])

        #expect(timeline.timed.map(\.id) == ["e9a", "e9b", "e10", "r10", "r15"])
    }

    @Test func allDayEventsBeforeDateOnlyReminders() {
        let reminder = make("date-only", kind: .reminder, start: iso("2026-11-10T00:00:00Z"), isAllDay: true, title: "A")
        let event = make("holiday", kind: .event, start: iso("2026-11-10T00:00:00Z"), isAllDay: true, title: "Z")

        let timeline = DayTimeline(items: [reminder, event], overdue: [])

        #expect(timeline.allDay.map(\.id) == ["holiday", "date-only"])
    }

    @Test func overdueSortedOldestFirst() {
        let yesterday = make("y", start: iso("2026-11-09T09:00:00Z"))
        let lastWeek = make("w", start: iso("2026-11-03T09:00:00Z"))

        let timeline = DayTimeline(items: [], overdue: [yesterday, lastWeek])

        #expect(timeline.overdue.map(\.id) == ["w", "y"])
    }

    @Test func undatedSortedByTitleThenID() {
        let b = make("1", title: "b")
        let a2 = make("3", title: "a")
        let a1 = make("2", title: "a")

        let timeline = DayTimeline(items: [b, a2, a1], overdue: [])

        #expect(timeline.undated.map(\.id) == ["2", "3", "1"])
    }

    @Test func emptyInputGivesEmptySections() {
        let timeline = DayTimeline(items: [], overdue: [])
        #expect(timeline.isEmpty)
    }
}
