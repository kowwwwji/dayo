import CoreGraphics
import Foundation
import Testing
@testable import DayoCore

private let tokyo: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    calendar.locale = Locale(identifier: "ja_JP")
    calendar.firstWeekday = 1
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    tokyo.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func range(_ from: Date, _ to: Date) -> DateInterval {
    DateInterval(start: from, end: to)
}

/// 月日と時分だけ取り出して比較しやすくする。
private func mdhm(_ dates: [Date]) -> [[Int]] {
    dates.map {
        let c = tokyo.dateComponents([.month, .day, .hour, .minute], from: $0)
        return [c.month!, c.day!, c.hour!, c.minute!]
    }
}

@Suite struct RecurrenceOccurrencesTests {
    /// 起点は 2026-11-10（火）9:00 JST。
    let anchor = date(2026, 11, 10, 9)

    private func days(_ spec: RecurrenceSpec, from: Date, to: Date) -> [[Int]] {
        mdhm(spec.occurrences(after: anchor, in: range(from, to), calendar: tokyo)).map { [$0[0], $0[1]] }
    }

    @Test func dailyExcludesTheAnchorAndKeepsItsTime() {
        let dates = RecurrenceSpec(frequency: .daily)
            .occurrences(after: anchor, in: range(date(2026, 11, 8), date(2026, 11, 13)), calendar: tokyo)
        #expect(mdhm(dates) == [[11, 11, 9, 0], [11, 12, 9, 0]])
    }

    @Test func everyThreeDaysCountsFromTheAnchor() {
        let spec = RecurrenceSpec(frequency: .daily, interval: 3)
        #expect(days(spec, from: date(2026, 11, 8), to: date(2026, 11, 22)) == [[11, 13], [11, 16], [11, 19]])
        // 月をまたいでも起点から数える（11/10 + 21 日 = 12/1）
        #expect(days(spec, from: date(2026, 11, 29), to: date(2026, 12, 6)) == [[12, 1], [12, 4]])
    }

    @Test func weeklyWithoutWeekdaysUsesTheAnchorWeekday() {
        let spec = RecurrenceSpec(frequency: .weekly)
        #expect(days(spec, from: date(2026, 11, 8), to: date(2026, 11, 29)) == [[11, 17], [11, 24]])
    }

    @Test func weeklyOnSeveralWeekdays() {
        // 月・水・金。起点（火）より後だけ
        let spec = RecurrenceSpec(frequency: .weekly, weekdays: [2, 4, 6])
        #expect(days(spec, from: date(2026, 11, 8), to: date(2026, 11, 22))
            == [[11, 11], [11, 13], [11, 16], [11, 18], [11, 20]])
    }

    @Test func biweeklySkipsTheOffWeek() {
        let spec = RecurrenceSpec(frequency: .weekly, interval: 2, weekdays: [3])
        #expect(days(spec, from: date(2026, 11, 15), to: date(2026, 11, 22)).isEmpty)
        #expect(days(spec, from: date(2026, 11, 22), to: date(2026, 11, 29)) == [[11, 24]])
        #expect(days(spec, from: date(2026, 11, 8), to: date(2026, 12, 27)) == [[11, 24], [12, 8], [12, 22]])
    }

    @Test func biweeklyOnSeveralWeekdaysKeepsTheRestOfTheAnchorWeek() {
        // 隔週の火・木。起点の週の木曜は出て、翌週は出ない
        let spec = RecurrenceSpec(frequency: .weekly, interval: 2, weekdays: [3, 5])
        #expect(days(spec, from: date(2026, 11, 8), to: date(2026, 11, 29)) == [[11, 12], [11, 24], [11, 26]])
    }

    @Test func monthlyWithoutDaysUsesTheAnchorDay() {
        let spec = RecurrenceSpec(frequency: .monthly)
        #expect(days(spec, from: date(2026, 11, 1), to: date(2027, 2, 1)) == [[12, 10], [1, 10]])
    }

    @Test func monthlyOnADayOfMonthSkipsShortMonths() {
        let spec = RecurrenceSpec(frequency: .monthly, daysOfMonth: [31])
        #expect(days(spec, from: date(2026, 11, 1), to: date(2027, 4, 1)) == [[12, 31], [1, 31], [3, 31]])
    }

    @Test func everyOtherMonthCountsFromTheAnchorMonth() {
        let spec = RecurrenceSpec(frequency: .monthly, interval: 2, daysOfMonth: [10])
        #expect(days(spec, from: date(2026, 11, 1), to: date(2027, 4, 1)) == [[1, 10], [3, 10]])
    }

    @Test func monthlyOnTheSecondTuesday() {
        let spec = RecurrenceSpec(frequency: .monthly, weekdays: [3], weekOfMonth: 2)
        #expect(days(spec, from: date(2026, 11, 1), to: date(2027, 2, 1)) == [[12, 8], [1, 12]])
    }

    @Test func monthlyOnTheLastFriday() {
        let spec = RecurrenceSpec(frequency: .monthly, weekdays: [6], weekOfMonth: -1)
        #expect(days(spec, from: date(2026, 11, 1), to: date(2027, 2, 1)) == [[11, 27], [12, 25], [1, 29]])
    }

    @Test func rangeEndIsExclusiveAndRangeBeforeTheAnchorIsEmpty() {
        let spec = RecurrenceSpec(frequency: .daily)
        // 11/12 0:00 で終わる範囲に 11/12 9:00 は入らない
        #expect(days(spec, from: date(2026, 11, 11), to: date(2026, 11, 12)) == [[11, 11]])
        #expect(days(spec, from: date(2026, 11, 1), to: date(2026, 11, 10)).isEmpty)
    }
}

private func reminder(
    _ id: String,
    start: Date?,
    recurrence: RecurrenceSpec?,
    isAllDay: Bool = false,
    isCompleted: Bool = false,
    hasRecurrence: Bool? = nil
) -> TimelineItem {
    TimelineItem(
        id: id, calendarItemIdentifier: id, kind: .reminder, title: id, start: start, end: nil,
        isAllDay: isAllDay, isCompleted: isCompleted, sourceName: "家族", accountName: "iCloud",
        color: CGColor(gray: 0, alpha: 1), recurrence: recurrence, isShared: false, hasRecurrence: hasRecurrence
    )
}

@Suite struct VirtualOccurrencesTests {
    let week = range(date(2026, 11, 8), date(2026, 11, 15))

    @Test func expandsFutureOccurrencesAsReadOnlyCopies() {
        let source = reminder("薬", start: date(2026, 11, 12, 21), recurrence: .init(frequency: .daily))
        let virtual = VirtualOccurrences.expand([source], in: week, calendar: tokyo)

        #expect(mdhm(virtual.compactMap(\.start)) == [[11, 13, 21, 0], [11, 14, 21, 0]])
        #expect(virtual.map(\.isVirtual) == [true, true])
        #expect(virtual.map(\.isEditable) == [false, false])
        #expect(virtual.map(\.calendarItemIdentifier) == ["薬", "薬"])
        #expect(virtual.map(\.title) == ["薬", "薬"])
        #expect(virtual.map(\.sourceName) == ["家族", "家族"])
        let expectedIDs = [date(2026, 11, 13, 21), date(2026, 11, 14, 21)].map { "薬@\($0.timeIntervalSince1970)" }
        #expect(virtual.map(\.id) == expectedIDs)
    }

    @Test func realItemsAreNotVirtualByDefault() {
        #expect(reminder("a", start: nil, recurrence: nil).isVirtual == false)
    }

    @Test func keepsAllDayOccurrencesAllDay() {
        let source = reminder("ゴミ", start: date(2026, 11, 9), recurrence: .init(frequency: .weekly, weekdays: [2, 5]), isAllDay: true)
        let virtual = VirtualOccurrences.expand([source], in: week, calendar: tokyo)
        #expect(mdhm(virtual.compactMap(\.start)) == [[11, 12, 0, 0]])
        #expect(virtual.map(\.isAllDay) == [true])
    }

    @Test func skipsItemsThatCannotBeExpanded() {
        let daily = RecurrenceSpec(frequency: .daily)
        let sources = [
            reminder("完了済み", start: date(2026, 11, 9, 9), recurrence: daily, isCompleted: true),
            reminder("期日なし", start: nil, recurrence: daily),
            reminder("単発", start: date(2026, 11, 9, 9), recurrence: nil),
            // 年次などこのアプリで表せない規則
            reminder("カスタム", start: date(2026, 11, 9, 9), recurrence: nil, hasRecurrence: true),
        ]
        #expect(VirtualOccurrences.expand(sources, in: week, calendar: tokyo).isEmpty)
    }

    @Test func expandsFromAnAnchorBeforeTheRange() {
        // 起点が先週でも、今週の回が interval を守って出る
        let source = reminder("隔日", start: date(2026, 11, 5, 8), recurrence: .init(frequency: .daily, interval: 2))
        let virtual = VirtualOccurrences.expand([source], in: week, calendar: tokyo)
        #expect(mdhm(virtual.compactMap(\.start)).map { $0[1] } == [9, 11, 13])
    }

    @Test func recurringSourcesAreIncompleteRecurringRemindersDueBeforeTheRangeEnds() {
        let daily = RecurrenceSpec(frequency: .daily)
        let reminders = [
            reminder("先週から", start: date(2026, 11, 5, 8), recurrence: daily),
            reminder("今週", start: date(2026, 11, 10, 8), recurrence: daily),
            reminder("来週から", start: date(2026, 11, 15), recurrence: daily),
            reminder("完了済み", start: date(2026, 11, 10, 8), recurrence: daily, isCompleted: true),
            reminder("単発", start: date(2026, 11, 10, 8), recurrence: nil),
            reminder("期日なし", start: nil, recurrence: daily),
        ]
        #expect(VirtualOccurrences.sources(in: reminders, before: week.end).map(\.id) == ["先週から", "今週"])
    }

    @Test func snapshotCarriesRecurringSources() {
        let source = reminder("薬", start: date(2026, 11, 12, 21), recurrence: .init(frequency: .daily))
        #expect(TimelineSnapshot(items: [], overdue: [], recurring: [source]).recurring == [source])
        #expect(TimelineSnapshot(items: [], overdue: []).recurring.isEmpty)
    }
}
