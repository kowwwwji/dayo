#if DEBUG
import Foundation
import Testing
@testable import DayoCore

@Suite struct DemoSourceTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    /// 2027/1/20（水）10:00
    private var now: Date { calendar.date(from: DateComponents(year: 2027, month: 1, day: 20, hour: 10))! }

    private func source() -> DemoSource { DemoSource(calendar: calendar, now: { now }) }

    private func day(_ offset: Int) -> DateInterval {
        let start = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
        return calendar.dateInterval(of: .day, for: start)!
    }

    private func week() -> DateInterval { calendar.dateInterval(of: .weekOfYear, for: now)! }

    @Test func everyDayOfTheWeekHasEventsOrRemindersInsideTheRange() async throws {
        let demo = source()
        let snapshot = try await demo.snapshot(for: week(), includingOverdue: false)
        #expect(snapshot.items.count >= 20)
        #expect(snapshot.items.filter { !$0.falls(in: week()) }.isEmpty)
        let days = Set(snapshot.items.compactMap(\.start).map { calendar.startOfDay(for: $0) })
        #expect(days.count == 7)
        #expect(Set(snapshot.items.map(\.kind)) == [.event, .reminder])
    }

    @Test func todayHasTimedEventsAndAnOpenReminder() async throws {
        let snapshot = try await source().snapshot(for: day(0), includingOverdue: false)
        #expect(snapshot.items.contains { $0.kind == .event && !$0.isAllDay })
        #expect(snapshot.items.contains { $0.kind == .reminder && !$0.isCompleted })
    }

    @Test func theSameDayReadsTheSameItems() async throws {
        let demo = source()
        let first = try await demo.snapshot(for: day(1), includingOverdue: false)
        let second = try await demo.snapshot(for: day(1), includingOverdue: false)
        #expect(first.items.map(\.id) == second.items.map(\.id))
    }

    @Test func pastRemindersAreCompletedExceptTheOverdueOne() async throws {
        let demo = source()
        let past = try await demo.snapshot(for: day(-3), includingOverdue: false)
        #expect(past.items.filter { $0.kind == .reminder && !$0.isCompleted }.isEmpty)

        let today = try await demo.snapshot(for: day(0), includingOverdue: true)
        #expect(today.overdue.count == 1)
        #expect(today.overdue.map(\.isCompleted) == [false])
        #expect(try await demo.snapshot(for: day(0), includingOverdue: false).overdue.isEmpty)
    }

    @Test func overdueForALaterRangeIncludesOpenRemindersOfDaysNotViewedYet() async throws {
        let snapshot = try await source().snapshot(for: day(14), includingOverdue: true)
        #expect(snapshot.overdue.map(\.title).contains("資料を送る"))
        #expect(snapshot.overdue.map(\.title).contains("市役所に書類を出す"))
    }

    @Test func anEventWithoutAnEndEndsAtItsStartLikeEventKit() async throws {
        let demo = source()
        let start = calendar.date(byAdding: .hour, value: 3, to: now)!
        try await demo.create(ItemDraft(kind: .event, title: "終わり無し", start: start))
        let created = try #require(
            try await demo.snapshot(for: day(0), includingOverdue: false).items.first { $0.title == "終わり無し" }
        )
        #expect(created.end == start)
    }

    @Test func readsAndWritesFromManyTasksAtOnceKeepEveryItem() async throws {
        let demo = source()
        await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<200 {
                group.addTask {
                    if index.isMultiple(of: 2) {
                        try await demo.create(ItemDraft(kind: .reminder, title: "並行 \(index)"))
                    } else {
                        _ = try await demo.snapshot(for: day(index % 30), includingOverdue: true)
                    }
                }
            }
        }
        let undated = try await demo.snapshot(for: day(0), includingOverdue: false).undated
        #expect(undated.filter { $0.title.hasPrefix("並行") }.count == 100)
    }

    @Test func undatedRemindersAreAlwaysIncluded() async throws {
        let snapshot = try await source().snapshot(for: day(5), includingOverdue: false)
        #expect(!snapshot.undated.isEmpty)
        #expect(snapshot.undated.map(\.start) == snapshot.undated.map { _ in nil })
    }

    @Test func calendarsCoverEveryItemAndDestinationsAreTheWritableOnes() async throws {
        let demo = source()
        let snapshot = try await demo.snapshot(for: week(), includingOverdue: true)
        let calendars = try await demo.calendars()
        let ids = Set(calendars.map(\.id))
        #expect((snapshot.items + snapshot.undated).filter { !ids.contains($0.calendarIdentifier) }.isEmpty)
        let destinations = try await demo.destinations()
        #expect(Set(destinations.map(\.kind)) == [.event, .reminder])
    }

    @Test func createdItemsAppearInLaterReads() async throws {
        let demo = source()
        let start = calendar.date(byAdding: .hour, value: 5, to: now)!
        try await demo.create(ItemDraft(kind: .event, title: "打ち合わせ", start: start, end: start.addingTimeInterval(3600)))
        let snapshot = try await demo.snapshot(for: day(0), includingOverdue: false)
        let created = try #require(snapshot.items.first { $0.title == "打ち合わせ" })
        #expect(created.start == start)
        #expect(created.isEditable)
    }

    @Test func aListNameThatDoesNotExistIsAnError() async throws {
        await #expect(throws: CalendarSourceError.listNotFound("無い")) {
            try await source().create(ItemDraft(kind: .reminder, title: "x", listName: "無い"))
        }
    }

    @Test func anEventWithoutAStartIsAnError() async throws {
        await #expect(throws: CalendarSourceError.eventNeedsStart) {
            try await source().create(ItemDraft(kind: .event, title: "x"))
        }
    }

    @Test func completingUpdatingAndDeletingChangeLaterReads() async throws {
        let demo = source()
        let reminder = try #require(
            try await demo.snapshot(for: day(0), includingOverdue: false).items.first { $0.kind == .reminder }
        )
        try await demo.setCompleted(true, for: reminder)
        #expect(try await find(reminder, in: demo)?.isCompleted == true)

        var draft = ItemDraft(kind: .reminder, title: "名前を変えた", start: reminder.start)
        draft.calendarID = reminder.calendarIdentifier
        try await demo.update(reminder, with: draft, span: .thisOccurrence)
        #expect(try await find(reminder, in: demo)?.title == "名前を変えた")

        try await demo.delete(reminder, span: .thisOccurrence)
        #expect(try await find(reminder, in: demo) == nil)
        await #expect(throws: CalendarSourceError.itemNotFound) {
            try await demo.delete(reminder, span: .thisOccurrence)
        }
    }

    @Test func changesAreAnnouncedAfterAWrite() async throws {
        let demo = source()
        var iterator = demo.changes.makeAsyncIterator()
        try await demo.create(ItemDraft(kind: .reminder, title: "x"))
        #expect(await iterator.next() != nil)
    }

    private func find(_ item: TimelineItem, in demo: DemoSource) async throws -> TimelineItem? {
        try await demo.snapshot(for: day(0), includingOverdue: false).items
            .first { $0.calendarItemIdentifier == item.calendarItemIdentifier }
    }
}
#endif
