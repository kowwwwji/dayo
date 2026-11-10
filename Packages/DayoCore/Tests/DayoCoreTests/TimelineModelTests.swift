import CoreGraphics
import Foundation
import Testing
@testable import DayoCore

/// テスト用の取得元。`gate` を立てると `snapshot` が `release` まで待つので、応答順を制御できる。
private final class FakeSource: CalendarSource {
    var accessResult: AccessStatus = .granted
    var snapshots: [Date: TimelineSnapshot] = [:]
    var setCompletedError: Error?
    var updateError: Error?
    private(set) var requests: [(range: DateInterval, includingOverdue: Bool)] = []
    private(set) var completions: [(id: String, completed: Bool)] = []
    private(set) var updates: [(item: TimelineItem, draft: ItemDraft, span: EditSpan)] = []
    var gate = false
    private var pending: [CheckedContinuation<Void, Never>] = []
    var pendingCount: Int { pending.count }

    func requestAccess() async throws -> AccessStatus { accessResult }

    func snapshot(for range: DateInterval, includingOverdue: Bool) async throws -> TimelineSnapshot {
        requests.append((range, includingOverdue))
        if gate {
            await withCheckedContinuation { pending.append($0) }
        }
        return snapshots[range.start] ?? .empty
    }

    func setCompleted(_ completed: Bool, for item: TimelineItem) async throws {
        if let setCompletedError { throw setCompletedError }
        completions.append((item.id, completed))
    }

    func create(_ draft: ItemDraft) async throws {}

    func update(_ item: TimelineItem, with draft: ItemDraft, span: EditSpan) async throws {
        if let updateError { throw updateError }
        updates.append((item, draft, span))
    }
    func delete(_ item: TimelineItem, span: EditSpan) async throws {}
    func destinations() async throws -> [Destination] { [] }

    var changes: AsyncStream<Void> { AsyncStream { _ in } }

    func release(at index: Int) {
        pending.remove(at: index).resume()
    }

    func waitForPending(_ count: Int) async {
        while pending.count < count { await Task.yield() }
    }
}

private struct TestError: Error {}

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func iso(_ string: String) -> Date {
    ISO8601DateFormatter().date(from: string)!
}

private func item(_ id: String, start: Date? = nil) -> TimelineItem {
    TimelineItem(
        id: id, calendarItemIdentifier: id, kind: .reminder, title: id, start: start, end: nil,
        isAllDay: false, isCompleted: false, sourceName: "", accountName: "",
        color: CGColor(gray: 0, alpha: 1), recurrence: nil, isShared: false
    )
}

@MainActor
@Suite struct TimelineModelTests {
    let d0 = iso("2026-11-10T00:00:00Z")
    let d1 = iso("2026-11-11T00:00:00Z")
    let d2 = iso("2026-11-12T00:00:00Z")

    private func makeModel(
        _ source: FakeSource, mode: TimelineMode = .day, now: @escaping () -> Date
    ) -> TimelineModel {
        TimelineModel(source: source, calendar: utc, mode: mode, now: now)
    }

    @Test func activateLoadsTodayWithOverdue() async {
        let source = FakeSource()
        let today = item("today", start: iso("2026-11-10T09:00:00Z"))
        let overdue = item("old", start: iso("2026-11-01T09:00:00Z"))
        source.snapshots[d0] = TimelineSnapshot(items: [today], overdue: [overdue])
        let model = makeModel(source) { self.d0 }

        await model.activate()

        #expect(model.access == .granted)
        #expect(model.hasLoaded)
        #expect(model.timeline.timed == [today])
        #expect(model.timeline.overdue == [overdue])
        #expect(source.requests.map(\.includingOverdue) == [true])
    }

    @Test func deniedAccessDoesNotLoad() async {
        let source = FakeSource()
        source.accessResult = .denied
        let model = makeModel(source) { self.d0 }

        await model.activate()

        #expect(model.access == .denied)
        #expect(model.hasLoaded == false)
        #expect(source.requests.isEmpty)
    }

    @Test func overdueIsRequestedOnlyForToday() async {
        let source = FakeSource()
        let model = makeModel(source) { self.d0 }

        await model.showNext()
        await model.showToday()

        #expect(model.day == d0)
        #expect(source.requests.map(\.includingOverdue) == [false, true])
        #expect(source.requests.map(\.range.start) == [d1, d0])
    }

    @Test func staleLoadDoesNotOverwriteNewerDay() async {
        let source = FakeSource()
        source.snapshots[d1] = TimelineSnapshot(items: [item("d1", start: iso("2026-11-11T09:00:00Z"))], overdue: [])
        source.snapshots[d2] = TimelineSnapshot(items: [item("d2", start: iso("2026-11-12T09:00:00Z"))], overdue: [])
        source.gate = true
        let model = makeModel(source) { self.d0 }

        let first = Task { await model.showNext() }
        await source.waitForPending(1)
        let second = Task { await model.showNext() }
        await source.waitForPending(2)

        source.release(at: 1)
        await second.value
        source.release(at: 0)
        await first.value

        #expect(model.day == d2)
        #expect(model.timeline.timed.map(\.id) == ["d2"])
    }

    @Test func toggleErrorIsKeptAndNoReloadHappens() async {
        let source = FakeSource()
        source.setCompletedError = TestError()
        let model = makeModel(source) { self.d0 }

        await model.toggleCompleted(item("x"))

        #expect(model.errorMessage != nil)
        #expect(source.requests.isEmpty)
    }

    @Test func toggleCompletedFlipsStateAndReloads() async {
        let source = FakeSource()
        let model = makeModel(source) { self.d0 }

        await model.toggleCompleted(item("x"))

        #expect(source.completions.map(\.completed) == [true])
        #expect(source.requests.count == 1)
    }

    @Test func dayChangeFollowsTodayWhenViewingToday() async {
        let source = FakeSource()
        var now = d0
        let model = makeModel(source) { now }

        now = d1
        await model.handleDayChanged()

        #expect(model.day == d1)
    }

    @Test func dayChangeKeepsPastDayButResumesFollowingWhenTomorrowBecomesToday() async {
        let source = FakeSource()
        var now = d0
        let model = makeModel(source) { now }

        await model.showPrevious()
        now = d1
        await model.handleDayChanged()
        #expect(model.day == iso("2026-11-09T00:00:00Z"))

        await model.showToday()
        await model.showNext()
        #expect(model.day == d2)
        now = d2
        await model.handleDayChanged()
        #expect(model.day == d2)
        now = iso("2026-11-13T00:00:00Z")
        await model.handleDayChanged()
        #expect(model.day == iso("2026-11-13T00:00:00Z"))
    }

    @Test func activateCatchesUpToTodayAfterMissedDayChange() async {
        let source = FakeSource()
        var now = d0
        let model = makeModel(source) { now }
        await model.activate()

        now = d1
        await model.activate()

        #expect(model.day == d1)
        #expect(source.requests.map(\.range.start) == [d0, d1])
    }

    @Test func moveShowsNewPositionBeforeSaveFinishesAndSendsDraft() async {
        let source = FakeSource()
        let original = item("x", start: iso("2026-11-10T09:00:00Z"))
        source.snapshots[d0] = TimelineSnapshot(items: [original], overdue: [])
        let model = makeModel(source) { self.d0 }
        await model.activate()
        #expect(model.placements.first?.startMinute == 9 * 60)

        // 保存後の読み直しを止めて、楽観更新の状態を見る
        source.gate = true
        let task = Task { await model.move(original, from: self.d0, toDay: self.d0, startMinute: 11 * 60, span: .futureOccurrences) }
        await source.waitForPending(1)

        #expect(model.placements.first?.startMinute == 11 * 60)
        #expect(source.updates.count == 1)
        #expect(source.updates[0].item == original)
        #expect(source.updates[0].draft.start == iso("2026-11-10T11:00:00Z"))
        #expect(source.updates[0].draft.end == nil)
        #expect(source.updates[0].span == .futureOccurrences)

        source.release(at: 0)
        await task.value
    }

    @Test func moveShiftsByTheVisibleDeltaForEventsClippedAtMidnight() async {
        let source = FakeSource()
        // 前日 22:00〜当日 2:00 の予定。表示は 0:00〜2:00 に切られる
        let start = iso("2026-11-09T22:00:00Z")
        let event = TimelineItem(
            id: "e", calendarItemIdentifier: "e", kind: .event, title: "夜勤", start: start,
            end: iso("2026-11-10T02:00:00Z"), isAllDay: false, isCompleted: false,
            sourceName: "", accountName: "", color: CGColor(gray: 0, alpha: 1), recurrence: nil, isShared: false
        )
        source.snapshots[d0] = TimelineSnapshot(items: [event], overdue: [])
        let model = makeModel(source) { self.d0 }
        await model.activate()
        #expect(model.placements.first?.startMinute == 0)

        // 3 時間下へ → 開始も 3 時間だけ後ろへ（当日 3:00 に飛ばない）
        await model.move(event, from: d0, toDay: d0, startMinute: 180, span: .thisOccurrence)

        #expect(source.updates.first?.draft.start == iso("2026-11-10T01:00:00Z"))
        #expect(source.updates.first?.draft.end == iso("2026-11-10T05:00:00Z"))
    }

    @Test func moveFailureShowsErrorAndRevertsOnReload() async {
        let source = FakeSource()
        source.updateError = TestError()
        let original = item("x", start: iso("2026-11-10T09:00:00Z"))
        source.snapshots[d0] = TimelineSnapshot(items: [original], overdue: [])
        let model = makeModel(source) { self.d0 }
        await model.activate()

        await model.move(original, from: d0, toDay: d0, startMinute: 11 * 60, span: .thisOccurrence)

        #expect(model.errorMessage != nil)
        #expect(model.placements.first?.startMinute == 9 * 60)
    }
}

@MainActor
@Suite struct TimelineModelWeekTests {
    /// 2026-11-10 は火曜。週（日曜始まり）は 11-08 〜 11-14。
    let today = iso("2026-11-10T00:00:00Z")
    let weekStart = iso("2026-11-08T00:00:00Z")
    let nextWeekStart = iso("2026-11-15T00:00:00Z")

    private func day(_ dayOfMonth: Int) -> Date {
        iso("2026-11-\(String(format: "%02d", dayOfMonth))T00:00:00Z")
    }

    private func makeModel(
        _ source: FakeSource, mode: TimelineMode = .week, now: @escaping () -> Date
    ) -> TimelineModel {
        TimelineModel(source: source, calendar: utc, mode: mode, now: now)
    }

    private func recurring(_ id: String, start: Date, allDay: Bool = false) -> TimelineItem {
        TimelineItem(
            id: id, calendarItemIdentifier: id, kind: .reminder, title: id, start: start, end: nil,
            isAllDay: allDay, isCompleted: false, sourceName: "", accountName: "",
            color: CGColor(gray: 0, alpha: 1), recurrence: RecurrenceSpec(frequency: .daily), isShared: false
        )
    }

    @Test func dayModeHasASingleColumn() async {
        let source = FakeSource()
        let model = makeModel(source, mode: .day) { self.today }
        await model.activate()

        #expect(model.mode == .day)
        #expect(model.columns.map(\.day) == [today])
        #expect(model.range == DateInterval(start: today, end: day(11)))
    }

    @Test func weekModeLoadsTheWeekContainingToday() async {
        let source = FakeSource()
        let tue = item("tue", start: iso("2026-11-10T09:00:00Z"))
        let fri = item("fri", start: iso("2026-11-13T15:00:00Z"))
        let old = item("old", start: iso("2026-11-01T09:00:00Z"))
        source.snapshots[weekStart] = TimelineSnapshot(items: [fri, tue], overdue: [old])
        let model = makeModel(source) { self.today }

        await model.activate()

        #expect(source.requests.map(\.range) == [DateInterval(start: weekStart, end: nextWeekStart)])
        #expect(source.requests.map(\.includingOverdue) == [true])
        #expect(model.containsToday)
        #expect(model.columns.map(\.day) == (8...14).map(day))
        #expect(model.columns[2].placements.map(\.id) == ["tue"])
        #expect(model.columns[5].placements.map(\.id) == ["fri"])
        #expect(model.timeline.overdue == [old])
        #expect(model.isLoadedForRange)
    }

    @Test func weekModeMovesByWeeksAndRequestsOverdueOnlyForThisWeek() async {
        let source = FakeSource()
        let model = makeModel(source) { self.today }

        await model.showNext()
        #expect(model.range.start == nextWeekStart)
        #expect(model.containsToday == false)
        await model.showPrevious()
        await model.showPrevious()
        #expect(model.range.start == iso("2026-11-01T00:00:00Z"))
        await model.showToday()

        #expect(model.range.start == weekStart)
        #expect(source.requests.map(\.includingOverdue) == [false, true, false, true])
    }

    @Test func allDayItemsBecomeSpansInWeekMode() async {
        let source = FakeSource()
        let trip = TimelineItem(
            id: "trip", calendarItemIdentifier: "trip", kind: .event, title: "出張",
            start: day(9), end: iso("2026-11-10T23:59:59Z"), isAllDay: true, isCompleted: false,
            sourceName: "", accountName: "", color: CGColor(gray: 0, alpha: 1), recurrence: nil, isShared: false
        )
        source.snapshots[weekStart] = TimelineSnapshot(items: [trip], overdue: [])
        let model = makeModel(source) { self.today }

        await model.activate()

        #expect(model.allDaySpans.map(\.id) == ["trip"])
        #expect(model.allDaySpans.map(\.firstColumn) == [1])
        #expect(model.allDaySpans.map(\.columnSpan) == [2])
    }

    @Test func switchingModeReloadsTheNewRange() async {
        let source = FakeSource()
        let model = makeModel(source, mode: .day) { self.today }
        await model.activate()

        await model.setMode(.week)
        #expect(model.mode == .week)
        #expect(model.columns.count == 7)

        await model.setMode(.day)
        #expect(model.columns.map(\.day) == [today])
        #expect(source.requests.map(\.range.start) == [today, weekStart, today])
    }

    @Test func settingTheSameModeDoesNotReload() async {
        let source = FakeSource()
        let model = makeModel(source) { self.today }
        await model.setMode(.week)
        #expect(source.requests.isEmpty)
    }

    @Test func switchingToDayShowsTodayWhenTheWeekContainsIt() async {
        let source = FakeSource()
        let model = makeModel(source, mode: .day) { self.today }
        // 木曜を見てから週へ → 日へ戻すと今日
        await model.showNext()
        await model.showNext()
        await model.setMode(.week)
        await model.setMode(.day)
        #expect(model.day == today)
    }

    @Test func switchingToDayKeepsTheDayWhenTheWeekIsNotThisWeek() async {
        let source = FakeSource()
        let model = makeModel(source) { self.today }
        await model.showNext()
        await model.setMode(.day)
        #expect(model.day == day(17))
        #expect(model.containsToday == false)
    }

    @Test func dayChangeInsideTheWeekKeepsFollowingToday() async {
        let source = FakeSource()
        var now = today
        let model = makeModel(source) { now }
        await model.activate()

        now = day(11)
        await model.handleDayChanged()
        await model.setMode(.day)

        #expect(model.day == day(11))
    }

    @Test func futureOccurrencesAppearAsVirtualItemsInTheWeek() async {
        let source = FakeSource()
        let pill = recurring("薬", start: iso("2026-11-10T21:00:00Z"))
        source.snapshots[weekStart] = TimelineSnapshot(items: [pill], overdue: [], recurring: [pill])
        let model = makeModel(source) { self.today }

        await model.activate()

        #expect(model.columns.map(\.placements.count) == [0, 0, 1, 1, 1, 1, 1])
        #expect(model.columns[2].placements.map(\.item.isVirtual) == [false])
        #expect(model.columns[3].placements.map(\.item.isVirtual) == [true])
        #expect(model.columns[3].placements.map(\.startMinute) == [21 * 60])
    }

    @Test func futureOccurrencesAppearInDayModeOnALaterDay() async {
        let source = FakeSource()
        let pill = recurring("薬", start: iso("2026-11-10T21:00:00Z"))
        source.snapshots[day(12)] = TimelineSnapshot(items: [], overdue: [], recurring: [pill])
        let model = makeModel(source, mode: .day) { self.today }

        await model.showNext()
        await model.showNext()

        #expect(model.timeline.timed.map(\.isVirtual) == [true])
        #expect(model.timeline.timed.map(\.start) == [iso("2026-11-12T21:00:00Z")])
    }

    @Test func allDayFutureOccurrencesBecomeSpans() async {
        let source = FakeSource()
        let trash = recurring("ゴミ", start: day(12), allDay: true)
        source.snapshots[weekStart] = TimelineSnapshot(items: [trash], overdue: [], recurring: [trash])
        let model = makeModel(source) { self.today }

        await model.activate()

        #expect(model.allDaySpans.map(\.firstColumn) == [4, 5, 6])
        #expect(model.allDaySpans.map(\.item.isVirtual) == [false, true, true])
    }

    @Test func occurrencesBeforeNowAreNotShown() async {
        let source = FakeSource()
        // 月曜 9:00 の回が未完了のまま火曜 10:00 になった。火曜 9:00 の回は「将来」ではないので出さない
        let late = recurring("朝", start: iso("2026-11-09T09:00:00Z"))
        source.snapshots[weekStart] = TimelineSnapshot(items: [late], overdue: [], recurring: [late])
        let model = makeModel(source) { iso("2026-11-10T10:00:00Z") }

        await model.activate()

        #expect(model.columns.map(\.placements.count) == [0, 1, 0, 1, 1, 1, 1])
    }

    @Test func virtualItemsCannotBeCompletedOrMoved() async {
        let source = FakeSource()
        let pill = recurring("薬", start: iso("2026-11-10T21:00:00Z"))
        source.snapshots[weekStart] = TimelineSnapshot(items: [pill], overdue: [], recurring: [pill])
        let model = makeModel(source) { self.today }
        await model.activate()
        let virtual = model.columns[3].placements[0].item
        let requests = source.requests.count

        await model.toggleCompleted(virtual)
        await model.move(virtual, from: day(11), toDay: day(12), startMinute: 600, span: .thisOccurrence)

        #expect(source.completions.isEmpty)
        #expect(source.updates.isEmpty)
        #expect(source.requests.count == requests)
        #expect(model.columns[3].placements.map(\.startMinute) == [21 * 60])
    }

    @Test func moveToAnotherDayKeepsTheDurationAndShowsItThereBeforeSaving() async {
        let source = FakeSource()
        let event = TimelineItem(
            id: "e", calendarItemIdentifier: "e", kind: .event, title: "面談",
            start: iso("2026-11-10T09:00:00Z"), end: iso("2026-11-10T10:30:00Z"), isAllDay: false,
            isCompleted: false, sourceName: "", accountName: "", color: CGColor(gray: 0, alpha: 1),
            recurrence: nil, isShared: false
        )
        source.snapshots[weekStart] = TimelineSnapshot(items: [event], overdue: [])
        let model = makeModel(source) { self.today }
        await model.activate()

        source.gate = true
        let task = Task {
            await model.move(event, from: self.today, toDay: self.day(13), startMinute: 14 * 60, span: .thisOccurrence)
        }
        await source.waitForPending(1)

        #expect(model.columns[2].placements.isEmpty)
        #expect(model.columns[5].placements.map(\.startMinute) == [14 * 60])
        #expect(source.updates.first?.draft.start == iso("2026-11-13T14:00:00Z"))
        #expect(source.updates.first?.draft.end == iso("2026-11-13T15:30:00Z"))

        source.release(at: 0)
        await task.value
    }

    @Test func movingTheSecondDayOfAnOvernightEventShiftsByTheVisibleDelta() async {
        let source = FakeSource()
        // 火 22:00 〜 水 2:00。水曜の列では 0:00〜2:00 に切って出ている
        let event = TimelineItem(
            id: "e", calendarItemIdentifier: "e", kind: .event, title: "夜勤",
            start: iso("2026-11-10T22:00:00Z"), end: iso("2026-11-11T02:00:00Z"), isAllDay: false,
            isCompleted: false, sourceName: "", accountName: "", color: CGColor(gray: 0, alpha: 1),
            recurrence: nil, isShared: false
        )
        source.snapshots[weekStart] = TimelineSnapshot(items: [event], overdue: [])
        let model = makeModel(source) { self.today }
        await model.activate()

        // 水曜の切れ端を木曜の 1:00 へ → 全体が 1 日と 1 時間後ろへ
        await model.move(event, from: day(11), toDay: day(12), startMinute: 60, span: .thisOccurrence)

        #expect(source.updates.first?.draft.start == iso("2026-11-11T23:00:00Z"))
        #expect(source.updates.first?.draft.end == iso("2026-11-12T03:00:00Z"))
    }
}

@Suite struct MoveDraftTests {
    @Test func keepsDurationAndAttributes() {
        let start = iso("2026-11-10T09:00:00Z")
        let event = TimelineItem(
            id: "e", calendarItemIdentifier: "e", kind: .event, title: "面談", start: start,
            end: start.addingTimeInterval(90 * 60), isAllDay: false, isCompleted: false,
            sourceName: "", accountName: "", color: CGColor(gray: 0, alpha: 1),
            recurrence: RecurrenceSpec(frequency: .weekly, weekdays: [3]), isShared: false,
            notes: "資料", calendarIdentifier: "cal"
        )
        let moved = ItemDraft(moving: event, to: iso("2026-11-10T11:00:00Z"))
        #expect(moved.start == iso("2026-11-10T11:00:00Z"))
        #expect(moved.end == iso("2026-11-10T12:30:00Z"))
        #expect(moved.isAllDay == false)
        #expect(moved.title == "面談")
        #expect(moved.notes == "資料")
        #expect(moved.recurrence == RecurrenceSpec(frequency: .weekly, weekdays: [3]))
        #expect(moved.calendarID == nil)

        let reminder = item("r", start: start)
        #expect(ItemDraft(moving: reminder, to: start).end == nil)
    }
}
