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

private func day(_ dayOfMonth: Int) -> Date {
    iso("2026-11-\(String(format: "%02d", dayOfMonth))T00:00:00Z")
}

private func item(
    _ id: String, kind: ItemKind = .event, _ start: String, _ end: String? = nil,
    allDay: Bool = false, virtual: Bool = false
) -> TimelineItem {
    TimelineItem(
        id: id, calendarItemIdentifier: id, kind: kind, title: id,
        start: iso(start), end: end.map(iso), isAllDay: allDay, isCompleted: false,
        sourceName: "", accountName: "", color: CGColor(gray: 0, alpha: 1), recurrence: nil, isShared: false,
        isVirtual: virtual
    )
}

private typealias Place = TimelineSelection.Place

private func position(_ id: String, _ place: Place, _ dayOfMonth: Int) -> TimelineCursor.Position {
    TimelineCursor.Position(selection: TimelineSelection(itemID: id, place: place), day: day(dayOfMonth))
}

private func grid(_ dayOfMonth: Int) -> Place { .grid(day: day(dayOfMonth)) }

/// 2026-11-08（日）〜 11-14（土）。
///
/// | 日 8 | 月 9 | 火 10 | 水 11 | 木 12 | 金 13 | 土 14 |
/// | --- | --- | --- | --- | --- | --- | --- |
/// | | | trip（終日、火〜木） | trip / memo（終日） | trip | | |
/// | | | t9 9:00 / t14 14:00 | w10 10:00 / w10b 10:00 / v 12:00（仮想） | | f13 13:00 | |
@Suite struct TimelineCursorTests {
    let days = (8...14).map(day)

    private func cursor(overdue: Bool = true) -> TimelineCursor {
        let old = [
            item("o1", kind: .reminder, "2026-11-01T09:00:00Z"),
            item("o2", kind: .reminder, "2026-11-02T09:00:00Z"),
        ]
        let allDay = [
            item("trip", "2026-11-10T00:00:00Z", "2026-11-13T00:00:00Z", allDay: true),
            item("memo", kind: .reminder, "2026-11-11T00:00:00Z", allDay: true),
            item("va", kind: .reminder, "2026-11-12T00:00:00Z", allDay: true, virtual: true),
        ]
        let timed = [
            item("t9", "2026-11-10T09:00:00Z", "2026-11-10T10:00:00Z"),
            item("t14", kind: .reminder, "2026-11-10T14:00:00Z"),
            item("w10", "2026-11-11T10:00:00Z", "2026-11-11T11:00:00Z"),
            item("w10b", "2026-11-11T10:00:00Z", "2026-11-11T10:30:00Z"),
            item("v", kind: .reminder, "2026-11-11T12:00:00Z", virtual: true),
            item("f13", "2026-11-13T13:00:00Z", "2026-11-13T14:00:00Z"),
        ]
        return TimelineCursor(
            days: days,
            overdue: overdue ? old : [],
            allDaySpans: TimelineColumns.allDaySpans(for: allDay, days: days, calendar: utc),
            columns: TimelineColumns.columns(for: timed, days: days, calendar: utc)
        )
    }

    @Test func aColumnListsOverdueThenAllDayThenTimedWithoutVirtualItems() {
        let entries = cursor().entries(on: day(11))
        #expect(entries.map(\.itemID) == ["o1", "o2", "trip", "memo", "w10", "w10b"])
        #expect(entries.map(\.place) == [.overdue, .overdue, .allDay, .allDay, grid(11), grid(11)])
    }

    @Test func aDayWithoutItemsStillListsOverdue() {
        #expect(cursor().entries(on: day(8)).map(\.itemID) == ["o1", "o2"])
        #expect(cursor(overdue: false).entries(on: day(8)).isEmpty)
    }

    @Test func findsTheItemOfASelection() {
        let cursor = cursor()
        #expect(cursor.item(for: TimelineSelection(itemID: "w10", place: grid(11)))?.id == "w10")
        #expect(cursor.item(for: TimelineSelection(itemID: "trip", place: .allDay))?.id == "trip")
        #expect(cursor.item(for: TimelineSelection(itemID: "o1", place: .overdue))?.id == "o1")
        #expect(cursor.item(for: TimelineSelection(itemID: "w10", place: grid(10))) == nil)
        #expect(cursor.item(for: TimelineSelection(itemID: "v", place: grid(11))) == nil)
    }

    @Test(arguments: [
        // 起点の日, 端, 期限切れあり, 期待
        (11, TimelineCursor.Edge.first, true, position("o1", .overdue, 11)),
        (11, .last, true, position("w10b", grid(11), 11)),
        (11, .first, false, position("trip", .allDay, 11)),
        // 項目の無い日からは、項目のある最初の日へ
        (8, .first, false, position("trip", .allDay, 10)),
        (8, .last, false, position("t14", grid(10), 10)),
        // 期限切れだけがある日は期限切れを選び、列はその日のまま
        (8, .last, true, position("o2", .overdue, 8)),
    ] as [(Int, TimelineCursor.Edge, Bool, TimelineCursor.Position)])
    func startsAtTheEdgeOfTheGivenDay(
        dayOfMonth: Int, edge: TimelineCursor.Edge, overdue: Bool, expected: TimelineCursor.Position
    ) {
        #expect(cursor(overdue: overdue).start(on: day(dayOfMonth), at: edge) == expected)
    }

    @Test func startsOnTheFirstDayWhenNoDayIsGiven() {
        #expect(cursor().start(on: nil, at: .first) == position("o1", .overdue, 8))
        #expect(cursor(overdue: false).start(on: nil, at: .first) == position("trip", .allDay, 10))
        #expect(TimelineCursor(days: days, overdue: [], allDaySpans: [], columns: []).start(on: nil, at: .first) == nil)
    }

    @Test(arguments: [
        // 起点, 向き（+1 が下）, 期待（nil は端で動かない）
        (position("w10", grid(11), 11), 1, position("w10b", grid(11), 11)),
        (position("w10b", grid(11), 11), 1, nil),
        (position("w10", grid(11), 11), -1, position("memo", .allDay, 11)),
        (position("memo", .allDay, 11), -1, position("trip", .allDay, 11)),
        // 列の先頭から上は期限切れ。期限切れから下は元の列の先頭へ戻る
        (position("trip", .allDay, 11), -1, position("o2", .overdue, 11)),
        (position("o2", .overdue, 11), 1, position("trip", .allDay, 11)),
        (position("o2", .overdue, 10), 1, position("trip", .allDay, 10)),
        (position("o2", .overdue, 13), 1, position("f13", grid(13), 13)),
        (position("o2", .overdue, 8), 1, nil),
        (position("o1", .overdue, 11), -1, nil),
        // 火曜の列: 終日 → 時刻順
        (position("trip", .allDay, 10), 1, position("t9", grid(10), 10)),
        (position("t9", grid(10), 10), 1, position("t14", grid(10), 10)),
    ] as [(TimelineCursor.Position, Int, TimelineCursor.Position?)])
    func movesUpAndDownWithinAColumn(
        from: TimelineCursor.Position, step: Int, expected: TimelineCursor.Position?
    ) {
        #expect(cursor().vertical(from: from, by: step) == expected)
    }

    @Test(arguments: [
        // 起点, 向き（+1 が右）, 期待（nil はその方向に項目が無い）
        // 時刻付きからは、開始時刻が近い時刻付きへ。同じ時刻なら左に並ぶほう
        (position("t9", grid(10), 10), 1, position("w10", grid(11), 11)),
        (position("t14", grid(10), 10), 1, position("w10", grid(11), 11)),
        (position("w10b", grid(11), 11), -1, position("t9", grid(10), 10)),
        // 時刻付きの無い日は終日へ
        (position("w10", grid(11), 11), 1, position("trip", .allDay, 12)),
        (position("f13", grid(13), 13), -1, position("trip", .allDay, 12)),
        // 項目の無い日は飛ばす。その先にも無ければ nil
        (position("f13", grid(13), 13), 1, nil),
        (position("t9", grid(10), 10), -1, nil),
        // 終日からは、隣の日の別の終日へ。無ければ時刻付きへ
        (position("trip", .allDay, 10), 1, position("memo", .allDay, 11)),
        (position("memo", .allDay, 11), -1, position("trip", .allDay, 10)),
        (position("memo", .allDay, 11), 1, position("trip", .allDay, 12)),
        (position("trip", .allDay, 12), 1, position("f13", grid(13), 13)),
        (position("trip", .allDay, 11), -1, position("t9", grid(10), 10)),
        // 期限切れからは隣の日の先頭へ
        (position("o1", .overdue, 11), 1, position("trip", .allDay, 12)),
        (position("o1", .overdue, 8), 1, position("trip", .allDay, 10)),
    ] as [(TimelineCursor.Position, Int, TimelineCursor.Position?)])
    func movesSidewaysToTheNearestItemOfTheNextDayWithItems(
        from: TimelineCursor.Position, step: Int, expected: TimelineCursor.Position?
    ) {
        #expect(cursor().horizontal(from: from, by: step) == expected)
    }

    @Test(arguments: [
        // 向き（+1 は次の週へ入った = 左端から）, 近づけたい開始分, 期待
        (1, 13 * 60, position("t14", grid(10), 10)),
        (1, nil, position("trip", .allDay, 10)),
        (-1, 9 * 60, position("f13", grid(13), 13)),
        (-1, nil, position("f13", grid(13), 13)),
    ] as [(Int, Int?, TimelineCursor.Position)])
    func entersAWeekFromTheSideItWasReachedFrom(step: Int, minute: Int?, expected: TimelineCursor.Position) {
        #expect(cursor().enter(by: step, nearMinute: minute) == expected)
    }

    @Test func enteringAnEmptyWeekSelectsNothing() {
        let empty = TimelineCursor(days: days, overdue: [], allDaySpans: [], columns: [])
        #expect(empty.enter(by: 1, nearMinute: nil) == nil)
    }

    @Test func reportsTheStartMinuteOnlyForTimedSelections() {
        let cursor = cursor()
        #expect(cursor.startMinute(of: position("t14", grid(10), 10)) == 14 * 60)
        #expect(cursor.startMinute(of: position("trip", .allDay, 10)) == nil)
    }

    @Test(arguments: [
        // 残っている選択はそのまま
        (position("w10", grid(11), 11), position("w10", grid(11), 11)),
        (position("o1", .overdue, 9), position("o1", .overdue, 9)),
        (position("trip", .allDay, 11), position("trip", .allDay, 11)),
        // 終日の項目がその日に掛からなくなったら、列を項目の最初の日へ寄せる
        (position("trip", .allDay, 13), position("trip", .allDay, 10)),
        // 無くなった項目、別の場所、仮想項目、表示範囲の外の日は解除
        (position("gone", grid(11), 11), nil),
        (position("w10", grid(10), 10), nil),
        (position("w10", .allDay, 11), nil),
        (position("v", grid(11), 11), nil),
        (position("va", .allDay, 12), nil),
        (position("o1", .overdue, 20), nil),
    ] as [(TimelineCursor.Position, TimelineCursor.Position?)])
    func keepsOnlySelectionsThatAreStillOnScreen(
        from: TimelineCursor.Position, expected: TimelineCursor.Position?
    ) {
        #expect(cursor().resolve(from) == expected)
    }
}
