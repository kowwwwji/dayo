import CoreGraphics
import Foundation
import Testing
@testable import DayoCore

private func iso(_ string: String) -> Date {
    ISO8601DateFormatter().date(from: string)!
}

private func item(_ id: String, kind: ItemKind = .event, _ start: String, _ end: String? = nil) -> TimelineItem {
    TimelineItem(
        id: id, calendarItemIdentifier: id, kind: kind, title: id,
        start: iso(start), end: end.map(iso), isAllDay: false, isCompleted: false,
        sourceName: "", accountName: "", color: CGColor(gray: 0, alpha: 1), recurrence: nil, isShared: false
    )
}

@Suite struct DayGridLayoutTests {
    let day = DateInterval(start: iso("2026-11-10T00:00:00Z"), end: iso("2026-11-11T00:00:00Z"))

    private func placement(_ id: String, in placements: [GridPlacement]) -> GridPlacement {
        placements.first { $0.id == id }!
    }

    @Test func convertsToMinutesFromMidnight() {
        let placements = DayGridLayout.place(
            [item("a", "2026-11-10T10:00:00Z", "2026-11-10T11:30:00Z")], in: day
        )
        let a = placement("a", in: placements)
        #expect(a.startMinute == 600)
        #expect(a.endMinute == 690)
        #expect(a.column == 0)
        #expect(a.columnCount == 1)
    }

    @Test func reminderGetsMinimumHeight() {
        let placements = DayGridLayout.place([item("r", kind: .reminder, "2026-11-10T09:00:00Z")], in: day)
        #expect(placement("r", in: placements).durationMinutes == 30)
    }

    @Test func overlappingItemsShareColumns() {
        let placements = DayGridLayout.place([
            item("a", "2026-11-10T10:00:00Z", "2026-11-10T12:00:00Z"),
            item("b", "2026-11-10T11:00:00Z", "2026-11-10T13:00:00Z"),
            item("c", "2026-11-10T12:30:00Z", "2026-11-10T13:30:00Z"),
        ], in: day)

        #expect(placement("a", in: placements).column == 0)
        #expect(placement("b", in: placements).column == 1)
        // c は a が終わった後なので a の列を再利用する
        #expect(placement("c", in: placements).column == 0)
        #expect(placements.allSatisfy { $0.columnCount == 2 })
    }

    @Test func nonOverlappingItemsFormSeparateClusters() {
        let placements = DayGridLayout.place([
            item("a", "2026-11-10T09:00:00Z", "2026-11-10T10:00:00Z"),
            item("b", "2026-11-10T09:30:00Z", "2026-11-10T10:00:00Z"),
            item("c", "2026-11-10T14:00:00Z", "2026-11-10T15:00:00Z"),
        ], in: day)

        #expect(placement("a", in: placements).columnCount == 2)
        #expect(placement("b", in: placements).columnCount == 2)
        #expect(placement("c", in: placements).columnCount == 1)
        #expect(placement("c", in: placements).column == 0)
    }

    @Test func clampsItemsCrossingMidnight() {
        let placements = DayGridLayout.place([
            item("late", "2026-11-10T23:00:00Z", "2026-11-11T02:00:00Z"),
            item("early", "2026-11-09T22:00:00Z", "2026-11-10T01:00:00Z"),
        ], in: day)

        #expect(placement("late", in: placements).endMinute == 1440)
        #expect(placement("early", in: placements).startMinute == 0)
        #expect(placement("early", in: placements).endMinute == 60)
    }

    @Test func dropsItemsEntirelyOutsideTheDay() {
        let placements = DayGridLayout.place([
            item("tomorrow", "2026-11-11T00:00:00Z", "2026-11-11T01:00:00Z"),
        ], in: day)
        #expect(placements.isEmpty)
    }
}
