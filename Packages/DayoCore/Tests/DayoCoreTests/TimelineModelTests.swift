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
    var deleteError: Error?
    private(set) var requests: [(range: DateInterval, includingOverdue: Bool)] = []
    private(set) var completions: [(id: String, completed: Bool)] = []
    private(set) var updates: [(item: TimelineItem, draft: ItemDraft, span: EditSpan)] = []
    private(set) var deletions: [(item: TimelineItem, span: EditSpan)] = []
    private(set) var refreshCount = 0
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

    /// 削除した項目は、以後の取得結果からも消える。
    func delete(_ item: TimelineItem, span: EditSpan) async throws {
        if let deleteError { throw deleteError }
        deletions.append((item, span))
        snapshots = snapshots.mapValues { snapshot in
            TimelineSnapshot(
                items: snapshot.items.filter { $0.id != item.id },
                overdue: snapshot.overdue.filter { $0.id != item.id },
                recurring: snapshot.recurring.filter { $0.id != item.id }
            )
        }
    }

    func destinations() async throws -> [Destination] { [] }

    func refresh() async { refreshCount += 1 }

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
        color: CGColor(gray: 0, alpha: 1), recurrence: nil
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

    @Test func refreshAsksTheSourceToSyncAndReloads() async {
        let source = FakeSource()
        let model = makeModel(source) { self.d0 }
        await model.activate()
        let added = item("added", start: iso("2026-11-10T09:00:00Z"))
        source.snapshots[d0] = TimelineSnapshot(items: [added], overdue: [])

        await model.refresh()

        #expect(source.refreshCount == 1)
        #expect(model.timeline.timed == [added])
    }

    @Test func isRefreshingOnlyWhileARefreshRuns() async {
        let source = FakeSource()
        let model = makeModel(source) { self.d0 }
        await model.activate()
        #expect(!model.isRefreshing)

        source.gate = true
        let refresh = Task { await model.refresh() }
        await source.waitForPending(1)
        #expect(model.isRefreshing)

        source.release(at: 0)
        await refresh.value
        #expect(!model.isRefreshing)
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
            sourceName: "", accountName: "", color: CGColor(gray: 0, alpha: 1), recurrence: nil
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
            color: CGColor(gray: 0, alpha: 1), recurrence: RecurrenceSpec(frequency: .daily)
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

    @Test func overdueInTheWeekMatchesTheDayViewOfToday() async {
        let source = FakeSource()
        // 今日（火）より前に期日が過ぎた未完了は、週の中の日（月）でも期限切れ欄に出す。列にも残す
        let lastWeek = item("先週", start: iso("2026-11-01T09:00:00Z"))
        let monday = item("月曜", start: iso("2026-11-09T09:00:00Z"))
        var done = item("完了済み", start: iso("2026-11-09T10:00:00Z"))
        done.isCompleted = true
        let todayItem = item("今日", start: iso("2026-11-10T09:00:00Z"))
        let event = TimelineItem(
            id: "予定", calendarItemIdentifier: "予定", kind: .event, title: "予定",
            start: iso("2026-11-09T13:00:00Z"), end: iso("2026-11-09T14:00:00Z"), isAllDay: false,
            isCompleted: false, sourceName: "", accountName: "", color: CGColor(gray: 0, alpha: 1),
            recurrence: nil
        )
        source.snapshots[weekStart] = TimelineSnapshot(
            items: [monday, done, todayItem, event], overdue: [lastWeek]
        )
        let model = makeModel(source) { iso("2026-11-10T08:00:00Z") }

        await model.activate()

        #expect(model.timeline.overdue.map(\.id) == ["先週", "月曜"])
        #expect(model.columns[1].placements.map(\.id) == ["月曜", "完了済み", "予定"])
    }

    @Test func otherWeeksHaveNoOverdue() async {
        let source = FakeSource()
        source.snapshots[iso("2026-11-01T00:00:00Z")] = TimelineSnapshot(
            items: [item("過去", start: iso("2026-11-03T09:00:00Z"))], overdue: []
        )
        let model = makeModel(source) { self.today }

        await model.showPrevious()

        #expect(model.timeline.overdue.isEmpty)
        #expect(model.columns[2].placements.map(\.id) == ["過去"])
    }

    @Test func allDayItemsBecomeSpansInWeekMode() async {
        let source = FakeSource()
        let trip = TimelineItem(
            id: "trip", calendarItemIdentifier: "trip", kind: .event, title: "出張",
            start: day(9), end: iso("2026-11-10T23:59:59Z"), isAllDay: true, isCompleted: false,
            sourceName: "", accountName: "", color: CGColor(gray: 0, alpha: 1), recurrence: nil
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

    @Test func switchingModeLaysOutColumnsBeforeTheLoadFinishes() async {
        let source = FakeSource()
        let model = makeModel(source, mode: .day) { self.today }
        await model.activate()

        // 読み込みを待つ間も列の数は新しい表示に合っている（週の見出しと列がずれない）
        source.gate = true
        let task = Task { await model.setMode(.week) }
        await source.waitForPending(1)
        #expect(model.columns.map(\.day) == (8...14).map(day))

        source.release(at: 0)
        await task.value
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

    @Test func allDayOccurrenceForTodayIsShownEvenAfterMidnight() async {
        let source = FakeSource()
        // 月曜の回が未完了のまま火曜 10:00。終日の回には時刻が無いので、今日の分は「これから」に数える
        let trash = recurring("ゴミ", start: day(9), allDay: true)
        source.snapshots[weekStart] = TimelineSnapshot(items: [trash], overdue: [], recurring: [trash])
        let model = makeModel(source) { iso("2026-11-10T10:00:00Z") }

        await model.activate()

        #expect(model.allDaySpans.map(\.firstColumn) == [1, 2, 3, 4, 5, 6])
        #expect(model.allDaySpans.map(\.item.isVirtual) == [false, true, true, true, true, true])
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
            recurrence: nil
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
            recurrence: nil
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

@MainActor
@Suite struct TimelineModelAllDayTests {
    let today = iso("2026-11-10T00:00:00Z")
    let weekStart = iso("2026-11-08T00:00:00Z")

    private func day(_ dayOfMonth: Int) -> Date {
        iso("2026-11-\(String(format: "%02d", dayOfMonth))T00:00:00Z")
    }

    private func make(
        _ id: String, kind: ItemKind, start: Date, end: Date? = nil, allDay: Bool,
        recurrence: RecurrenceSpec? = nil, isVirtual: Bool = false
    ) -> TimelineItem {
        TimelineItem(
            id: id, calendarItemIdentifier: id, kind: kind, title: id, start: start, end: end,
            isAllDay: allDay, isCompleted: false, sourceName: "", accountName: "",
            color: CGColor(gray: 0, alpha: 1), recurrence: recurrence, isVirtual: isVirtual
        )
    }

    private func loaded(_ items: [TimelineItem], source: FakeSource = FakeSource()) async -> (TimelineModel, FakeSource) {
        source.snapshots[weekStart] = TimelineSnapshot(items: items, overdue: [])
        let model = TimelineModel(source: source, calendar: utc, mode: .week) { self.today }
        await model.activate()
        return (model, source)
    }

    @Test func movingAnAllDayEventShiftsItByDaysAndKeepsItsLength() async {
        let trip = make("出張", kind: .event, start: day(9), end: iso("2026-11-10T23:59:59Z"), allDay: true)
        let (model, source) = await loaded([trip])

        source.gate = true
        let task = Task { await model.moveAllDay(trip, byDays: 2, span: .thisOccurrence) }
        await source.waitForPending(1)

        #expect(model.allDaySpans.map(\.firstColumn) == [3])
        #expect(model.allDaySpans.map(\.columnSpan) == [2])
        #expect(source.updates.first?.draft.start == day(11))
        #expect(source.updates.first?.draft.end == iso("2026-11-12T23:59:59Z"))
        #expect(source.updates.first?.draft.isAllDay == true)

        source.release(at: 0)
        await task.value
    }

    @Test func movingADateOnlyReminderKeepsItDateOnly() async {
        let due = make("支払い", kind: .reminder, start: day(10), allDay: true)
        let (model, source) = await loaded([due])

        await model.moveAllDay(due, byDays: -1, span: .thisOccurrence)

        #expect(source.updates.first?.draft.start == day(9))
        #expect(source.updates.first?.draft.end == nil)
        #expect(source.updates.first?.draft.isAllDay == true)
    }

    @Test func droppingAnAllDayEventOnTheGridMakesItOneHourAtThatTime() async {
        let trip = make("出張", kind: .event, start: day(9), end: iso("2026-11-10T23:59:59Z"), allDay: true)
        let (model, source) = await loaded([trip])

        source.gate = true
        let task = Task { await model.makeTimed(trip, onDay: self.day(12), startMinute: 600, span: .thisOccurrence) }
        await source.waitForPending(1)

        #expect(model.allDaySpans.isEmpty)
        #expect(model.columns[4].placements.map(\.startMinute) == [600])
        #expect(model.columns[4].placements.map(\.endMinute) == [660])
        #expect(source.updates.first?.draft.start == iso("2026-11-12T10:00:00Z"))
        #expect(source.updates.first?.draft.end == iso("2026-11-12T11:00:00Z"))
        #expect(source.updates.first?.draft.isAllDay == false)

        source.release(at: 0)
        await task.value
    }

    @Test func droppingADateOnlyReminderOnTheGridGivesItADueTime() async {
        let due = make("支払い", kind: .reminder, start: day(10), allDay: true)
        let (model, source) = await loaded([due])

        await model.makeTimed(due, onDay: day(10), startMinute: 15 * 60 + 30, span: .thisOccurrence)

        #expect(source.updates.first?.draft.start == iso("2026-11-10T15:30:00Z"))
        #expect(source.updates.first?.draft.end == nil)
        #expect(source.updates.first?.draft.isAllDay == false)
    }

    @Test func droppingATimedEventOnTheAllDayRowMakesItAllDayThatDay() async {
        let meeting = make(
            "面談", kind: .event, start: iso("2026-11-10T09:00:00Z"), end: iso("2026-11-10T10:30:00Z"), allDay: false
        )
        let (model, source) = await loaded([meeting])

        source.gate = true
        let task = Task { await model.makeAllDay(meeting, onDay: self.day(13), span: .futureOccurrences) }
        await source.waitForPending(1)

        #expect(model.columns[2].placements.isEmpty)
        #expect(model.allDaySpans.map(\.firstColumn) == [5])
        #expect(model.allDaySpans.map(\.columnSpan) == [1])
        #expect(source.updates.first?.draft.start == day(13))
        #expect(source.updates.first?.draft.end == day(13))
        #expect(source.updates.first?.draft.isAllDay == true)
        #expect(source.updates.first?.span == .futureOccurrences)

        source.release(at: 0)
        await task.value
    }

    @Test func droppingATimedReminderOnTheAllDayRowDropsItsTime() async {
        let call = make("電話", kind: .reminder, start: iso("2026-11-10T09:00:00Z"), allDay: false)
        let (model, source) = await loaded([call])

        await model.makeAllDay(call, onDay: day(10), span: .thisOccurrence)

        #expect(source.updates.first?.draft.start == day(10))
        #expect(source.updates.first?.draft.end == nil)
        #expect(source.updates.first?.draft.isAllDay == true)
    }

    @Test func nothingHappensForVirtualItemsOrAZeroDayMove() async {
        let virtual = make("薬", kind: .reminder, start: day(12), allDay: true, isVirtual: true)
        let due = make("支払い", kind: .reminder, start: day(10), allDay: true)
        let (model, source) = await loaded([due])

        await model.moveAllDay(virtual, byDays: 1, span: .thisOccurrence)
        await model.makeTimed(virtual, onDay: day(12), startMinute: 600, span: .thisOccurrence)
        await model.makeAllDay(virtual, onDay: day(12), span: .thisOccurrence)
        await model.moveAllDay(due, byDays: 0, span: .thisOccurrence)

        #expect(source.updates.isEmpty)
    }

    @Test func aFailedAllDayMoveShowsTheErrorAndPutsTheItemBack() async {
        let source = FakeSource()
        source.updateError = TestError()
        let due = make("支払い", kind: .reminder, start: day(10), allDay: true)
        let (model, _) = await loaded([due], source: source)

        await model.moveAllDay(due, byDays: 3, span: .thisOccurrence)

        #expect(model.errorMessage != nil)
        #expect(model.allDaySpans.map(\.firstColumn) == [2])
    }
}

@Suite struct AllDayDraftTests {
    private func timedReminder() -> TimelineItem {
        TimelineItem(
            id: "r", calendarItemIdentifier: "r", kind: .reminder, title: "電話",
            start: iso("2026-11-10T09:00:00Z"), end: nil, isAllDay: false, isCompleted: false,
            sourceName: "", accountName: "", color: CGColor(gray: 0, alpha: 1), recurrence: nil,
            earlyReminderMinutes: 10
        )
    }

    @Test func makingAReminderAllDayDropsItsEarlyReminder() {
        // 時刻なしの期日は鳴る時刻が定まらないので、早期リマインダーは残さない
        let draft = ItemDraft(makingAllDay: timedReminder(), on: iso("2026-11-10T00:00:00Z"))
        #expect(draft.isAllDay)
        #expect(draft.earlyReminderMinutes == nil)
    }

    @Test func movingKeepsTheEarlyReminderOnlyForTimedItems() {
        #expect(ItemDraft(moving: timedReminder(), to: iso("2026-11-11T09:00:00Z")).earlyReminderMinutes == 10)
        #expect(ItemDraft(moving: timedReminder(), to: iso("2026-11-11T00:00:00Z"), isAllDay: true).earlyReminderMinutes == nil)
    }
}

@Suite struct MoveDraftTests {
    @Test func keepsDurationAndAttributes() {
        let start = iso("2026-11-10T09:00:00Z")
        let event = TimelineItem(
            id: "e", calendarItemIdentifier: "e", kind: .event, title: "面談", start: start,
            end: start.addingTimeInterval(90 * 60), isAllDay: false, isCompleted: false,
            sourceName: "", accountName: "", color: CGColor(gray: 0, alpha: 1),
            recurrence: RecurrenceSpec(frequency: .weekly, weekdays: [3]),
            notes: "資料", location: "会議室 A", calendarIdentifier: "cal"
        )
        let moved = ItemDraft(moving: event, to: iso("2026-11-10T11:00:00Z"))
        #expect(moved.start == iso("2026-11-10T11:00:00Z"))
        #expect(moved.end == iso("2026-11-10T12:30:00Z"))
        #expect(moved.isAllDay == false)
        #expect(moved.title == "面談")
        #expect(moved.notes == "資料")
        #expect(moved.location == "会議室 A")
        #expect(moved.recurrence == RecurrenceSpec(frequency: .weekly, weekdays: [3]))
        #expect(moved.calendarID == nil)

        let reminder = item("r", start: start)
        #expect(ItemDraft(moving: reminder, to: start).end == nil)
    }
}

@MainActor
@Suite struct TimelineModelSelectionTests {
    /// 2026-11-10 は火曜。週（日曜始まり）は 11-08 〜 11-14。
    let today = iso("2026-11-10T00:00:00Z")
    let weekStart = iso("2026-11-08T00:00:00Z")
    let nextWeekStart = iso("2026-11-15T00:00:00Z")
    let previousWeekStart = iso("2026-11-01T00:00:00Z")

    private func day(_ dayOfMonth: Int) -> Date {
        iso("2026-11-\(String(format: "%02d", dayOfMonth))T00:00:00Z")
    }

    private func event(_ id: String, _ start: String) -> TimelineItem {
        let start = iso(start)
        return TimelineItem(
            id: id, calendarItemIdentifier: id, kind: .event, title: id, start: start,
            end: start.addingTimeInterval(3600), isAllDay: false, isCompleted: false, sourceName: "",
            accountName: "", color: CGColor(gray: 0, alpha: 1), recurrence: nil
        )
    }

    private func grid(_ id: String, _ dayOfMonth: Int) -> TimelineSelection {
        TimelineSelection(itemID: id, place: .grid(day: day(dayOfMonth)))
    }

    private func loaded(
        _ items: [TimelineItem], overdue: [TimelineItem] = [], mode: TimelineMode = .week,
        source: FakeSource = FakeSource()
    ) async -> (TimelineModel, FakeSource) {
        source.snapshots[mode == .week ? weekStart : today] = TimelineSnapshot(items: items, overdue: overdue)
        let model = TimelineModel(source: source, calendar: utc, mode: mode) { self.today }
        await model.activate()
        return (model, source)
    }

    @Test func nothingIsSelectedAtFirst() async {
        let (model, _) = await loaded([item("a", start: iso("2026-11-10T09:00:00Z"))])
        #expect(model.selection == nil)
        #expect(model.selectedItem == nil)
    }

    @Test func nextWithoutASelectionPicksTheFirstItemOfToday() async {
        let (model, _) = await loaded([
            event("mon", "2026-11-09T09:00:00Z"),
            event("a", "2026-11-10T09:00:00Z"),
            event("b", "2026-11-10T12:00:00Z"),
        ])

        model.selectNext()

        #expect(model.selection == grid("a", 10))
        #expect(model.selectedItem?.id == "a")
    }

    @Test func previousWithoutASelectionPicksTheLastItemOfToday() async {
        let (model, _) = await loaded([
            item("a", start: iso("2026-11-10T09:00:00Z")),
            item("b", start: iso("2026-11-10T12:00:00Z")),
            item("wed", start: iso("2026-11-11T09:00:00Z")),
        ])

        model.selectPrevious()

        #expect(model.selection == grid("b", 10))
    }

    @Test func withoutTodayOnScreenTheFirstDayIsUsed() async {
        let source = FakeSource()
        source.snapshots[nextWeekStart] = TimelineSnapshot(
            items: [item("next", start: iso("2026-11-17T09:00:00Z"))], overdue: []
        )
        let (model, _) = await loaded([], source: source)
        await model.showNext()

        model.selectNext()

        #expect(model.selection == grid("next", 17))
    }

    @Test func nextAndPreviousWalkTheColumnAndStopAtItsEnds() async {
        let old = item("old", start: iso("2026-11-01T09:00:00Z"))
        let (model, _) = await loaded([
            item("a", start: iso("2026-11-10T09:00:00Z")),
            item("b", start: iso("2026-11-10T12:00:00Z")),
        ], overdue: [old])

        model.selectNext()
        #expect(model.selection == TimelineSelection(itemID: "old", place: .overdue))
        model.selectNext()
        model.selectNext()
        #expect(model.selection == grid("b", 10))
        model.selectNext()
        #expect(model.selection == grid("b", 10))
        model.selectPrevious()
        model.selectPrevious()
        model.selectPrevious()
        #expect(model.selection == TimelineSelection(itemID: "old", place: .overdue))
    }

    @Test func virtualOccurrencesAreSkipped() async {
        let source = FakeSource()
        let pill = TimelineItem(
            id: "薬", calendarItemIdentifier: "薬", kind: .reminder, title: "薬",
            start: iso("2026-11-10T21:00:00Z"), end: nil, isAllDay: false, isCompleted: false, sourceName: "",
            accountName: "", color: CGColor(gray: 0, alpha: 1), recurrence: RecurrenceSpec(frequency: .daily)
        )
        source.snapshots[weekStart] = TimelineSnapshot(
            items: [pill, event("fri", "2026-11-13T09:00:00Z")], overdue: [], recurring: [pill]
        )
        let model = TimelineModel(source: source, calendar: utc, mode: .week) { self.today }
        await model.activate()

        model.selectNext()
        #expect(model.selection == grid("薬", 10))
        await model.selectRight()

        // 水・木には薬の将来回（仮想）しか無いので飛ばす
        #expect(model.selection == grid("fri", 13))
    }

    @Test func selectingAnItemDirectlyMovesTheSelectionThere() async {
        let (model, _) = await loaded([
            event("a", "2026-11-10T09:00:00Z"),
            event("b", "2026-11-10T12:00:00Z"),
            event("fri", "2026-11-13T09:00:00Z"),
        ])
        model.selectNext()

        model.select(grid("fri", 13))

        #expect(model.selection == grid("fri", 13))
        #expect(model.selectedItem?.id == "fri")
    }

    @Test func movingOnFromADirectSelectionStaysInItsColumn() async {
        let (model, _) = await loaded([
            event("a", "2026-11-10T09:00:00Z"),
            event("b", "2026-11-10T12:00:00Z"),
            event("fri", "2026-11-13T09:00:00Z"),
        ])

        model.select(grid("a", 10))
        model.selectNext()

        #expect(model.selection == grid("b", 10))
    }

    @Test func selectingAVirtualOccurrenceDirectlyKeepsTheSelection() async {
        let source = FakeSource()
        let pill = TimelineItem(
            id: "薬", calendarItemIdentifier: "薬", kind: .reminder, title: "薬",
            start: iso("2026-11-10T21:00:00Z"), end: nil, isAllDay: false, isCompleted: false, sourceName: "",
            accountName: "", color: CGColor(gray: 0, alpha: 1), recurrence: RecurrenceSpec(frequency: .daily)
        )
        source.snapshots[weekStart] = TimelineSnapshot(items: [pill], overdue: [], recurring: [pill])
        let model = TimelineModel(source: source, calendar: utc, mode: .week) { self.today }
        await model.activate()
        model.selectNext()
        let virtual = model.columns.first { $0.day == day(11) }?.placements.first { $0.item.isVirtual }

        model.select(TimelineSelection(itemID: virtual?.id ?? "", place: .grid(day: day(11))))

        #expect(virtual != nil)
        #expect(model.selection == grid("薬", 10))
    }

    @Test func clearSelectionDeselects() async {
        let (model, _) = await loaded([item("a", start: iso("2026-11-10T09:00:00Z"))])
        model.selectNext()

        model.clearSelection()

        #expect(model.selection == nil)
    }

    @Test func theSelectionSurvivesAReloadWhileItsItemRemains() async {
        let (model, source) = await loaded([
            item("a", start: iso("2026-11-10T09:00:00Z")),
            item("b", start: iso("2026-11-10T12:00:00Z")),
        ])
        model.selectNext()
        model.selectNext()

        source.snapshots[weekStart] = TimelineSnapshot(
            items: [item("b", start: iso("2026-11-10T13:00:00Z"))], overdue: []
        )
        await model.load()

        #expect(model.selection == grid("b", 10))
        #expect(model.selectedItem?.start == iso("2026-11-10T13:00:00Z"))
    }

    @Test func theSelectionIsClearedWhenItsItemDisappears() async {
        let (model, source) = await loaded([item("a", start: iso("2026-11-10T09:00:00Z"))])
        model.selectNext()

        source.snapshots[weekStart] = .empty
        await model.load()

        #expect(model.selection == nil)
    }

    @Test func theSelectionIsClearedWhenItsItemMovesToAnotherDay() async {
        let (model, source) = await loaded([item("a", start: iso("2026-11-10T09:00:00Z"))])
        model.selectNext()

        source.snapshots[weekStart] = TimelineSnapshot(
            items: [item("a", start: iso("2026-11-12T09:00:00Z"))], overdue: []
        )
        await model.load()

        #expect(model.selection == nil)
    }

    @Test func switchingToDayKeepsTheSelectionOnlyIfTheItemIsStillShown() async {
        let source = FakeSource()
        let a = item("a", start: iso("2026-11-10T09:00:00Z"))
        let fri = item("fri", start: iso("2026-11-13T09:00:00Z"))
        source.snapshots[today] = TimelineSnapshot(items: [a], overdue: [])
        let (model, _) = await loaded([a, fri], source: source)

        model.selectNext()
        await model.setMode(.day)
        #expect(model.selection == grid("a", 10))

        await model.setMode(.week)
        await model.selectRight()
        #expect(model.selection == grid("fri", 13))
        await model.setMode(.day)
        #expect(model.selection == nil)
    }

    @Test func movingToAnotherDayClearsTheSelection() async {
        let (model, _) = await loaded([item("a", start: iso("2026-11-10T09:00:00Z"))], mode: .day)
        model.selectNext()

        await model.showNext()

        #expect(model.selection == nil)
    }

    @Test func leftAndRightInDayModeShowTheNeighbouringDay() async {
        let (model, _) = await loaded([item("a", start: iso("2026-11-10T09:00:00Z"))], mode: .day)
        model.selectNext()

        await model.selectRight()
        #expect(model.day == day(11))
        #expect(model.selection == nil)

        await model.selectLeft()
        await model.selectLeft()
        #expect(model.day == day(9))
    }

    @Test func leftAndRightInWeekModeMoveBetweenDaysWithItems() async {
        let (model, _) = await loaded([
            event("mon", "2026-11-09T15:00:00Z"),
            event("a", "2026-11-10T09:00:00Z"),
            event("fri9", "2026-11-13T09:30:00Z"),
            event("fri15", "2026-11-13T15:00:00Z"),
        ])
        model.selectNext()

        await model.selectRight()
        #expect(model.selection == grid("fri9", 13))
        await model.selectLeft()
        await model.selectLeft()
        #expect(model.selection == grid("mon", 9))
        #expect(model.day == today)
    }

    @Test func rightWithoutASelectionInWeekModeStartsLikeNext() async {
        let (model, _) = await loaded([event("a", "2026-11-10T09:00:00Z"), event("fri", "2026-11-13T09:00:00Z")])

        await model.selectRight()

        #expect(model.selection == grid("a", 10))
    }

    @Test func rightAtTheLastDayWithItemsMovesToTheNextWeekAndSelectsTheNearestItemThere() async {
        let source = FakeSource()
        source.snapshots[nextWeekStart] = TimelineSnapshot(items: [
            event("n8", "2026-11-16T08:00:00Z"),
            event("n14", "2026-11-16T14:00:00Z"),
            event("later", "2026-11-18T13:00:00Z"),
        ], overdue: [])
        let (model, _) = await loaded([event("fri", "2026-11-13T13:00:00Z")], source: source)
        model.selectNext()
        #expect(model.selection == grid("fri", 13))

        await model.selectRight()

        #expect(model.range.start == nextWeekStart)
        #expect(model.selection == grid("n14", 16))
    }

    @Test func leftAtTheFirstDayWithItemsMovesToThePreviousWeekAndEntersFromItsEnd() async {
        let source = FakeSource()
        source.snapshots[previousWeekStart] = TimelineSnapshot(items: [
            event("early", "2026-11-02T09:00:00Z"),
            event("sat", "2026-11-07T09:00:00Z"),
        ], overdue: [])
        let (model, _) = await loaded([event("a", "2026-11-10T09:00:00Z")], source: source)
        model.selectNext()

        await model.selectLeft()

        #expect(model.range.start == previousWeekStart)
        #expect(model.selection == grid("sat", 7))
    }

    @Test func movingIntoAnEmptyWeekLeavesNothingSelected() async {
        let (model, _) = await loaded([event("a", "2026-11-10T09:00:00Z")])
        model.selectNext()

        await model.selectRight()

        #expect(model.range.start == nextWeekStart)
        #expect(model.selection == nil)
    }

    @Test func togglingCompletesTheSelectedReminder() async {
        let (model, source) = await loaded([item("todo", start: iso("2026-11-10T09:00:00Z"))])
        model.selectNext()

        await model.toggleSelectedCompleted()

        #expect(source.completions.map(\.id) == ["todo"])
        #expect(source.completions.map(\.completed) == [true])
        #expect(model.selection == grid("todo", 10))
    }

    @Test func togglingDoesNothingForEventsOrWithoutASelection() async {
        let (model, source) = await loaded([event("meeting", "2026-11-10T09:00:00Z")])
        let requests = source.requests.count

        await model.toggleSelectedCompleted()
        model.selectNext()
        await model.toggleSelectedCompleted()

        #expect(source.completions.isEmpty)
        #expect(source.requests.count == requests)
    }

    // MARK: - 選択中の項目を動かす

    private func make(
        _ id: String, calendarItem: String? = nil, kind: ItemKind = .event, _ start: String, hours: Double? = 1,
        allDay: Bool = false, editable: Bool = true
    ) -> TimelineItem {
        let start = iso(start)
        return TimelineItem(
            id: id, calendarItemIdentifier: calendarItem ?? id, kind: kind, title: id, start: start,
            end: kind == .event ? hours.map { start.addingTimeInterval($0 * 3600) } : nil,
            isAllDay: allDay, isCompleted: false, sourceName: "", accountName: "",
            color: CGColor(gray: 0, alpha: 1), recurrence: nil, isEditable: editable
        )
    }

    @Test func movingLaterGoesToTheNextQuarterHourAndKeepsTheSelection() async {
        let (model, source) = await loaded([make("todo", kind: .reminder, "2026-11-10T09:07:00Z")])
        model.selectNext()

        await model.moveSelectionInTime(1, span: .thisOccurrence)

        #expect(source.updates.map(\.draft.start) == [iso("2026-11-10T09:15:00Z")])
        #expect(source.updates.map(\.span) == [.thisOccurrence])
        #expect(model.selection == grid("todo", 10))
    }

    @Test func movingEarlierGoesToThePreviousQuarterHourAndKeepsTheDuration() async {
        let (model, source) = await loaded([make("meeting", "2026-11-10T09:00:00Z")])
        model.selectNext()

        await model.moveSelectionInTime(-1, span: .futureOccurrences)

        #expect(source.updates.map(\.draft.start) == [iso("2026-11-10T08:45:00Z")])
        #expect(source.updates.map(\.draft.end) == [iso("2026-11-10T09:45:00Z")])
        #expect(source.updates.map(\.span) == [.futureOccurrences])
    }

    @Test func movingInTimeStopsAtTheEndsOfTheDay() async {
        let (model, source) = await loaded([
            make("first", kind: .reminder, "2026-11-10T00:00:00Z"),
            make("last", "2026-11-10T23:00:00Z"),
        ])
        model.selectNext()
        await model.moveSelectionInTime(-1, span: .thisOccurrence)
        model.selectNext()
        await model.moveSelectionInTime(1, span: .thisOccurrence)

        #expect(model.selection == grid("last", 10))
        #expect(source.updates.isEmpty)
    }

    @Test func movingByADayKeepsTheTimeAndTheSelectionFollows() async {
        let source = FakeSource()
        let (model, _) = await loaded([make("x#1", calendarItem: "x", "2026-11-10T09:00:00Z")], source: source)
        model.selectNext()
        // 予定の id は開始日時を含むので、保存後の読み直しでは別の id になる
        source.snapshots[weekStart] = TimelineSnapshot(
            items: [make("x#2", calendarItem: "x", "2026-11-11T09:00:00Z")], overdue: []
        )

        await model.moveSelectionByDay(1, span: .thisOccurrence)

        #expect(source.updates.map(\.draft.start) == [iso("2026-11-11T09:00:00Z")])
        #expect(model.selection == grid("x#2", 11))
        #expect(model.selectedItem?.start == iso("2026-11-11T09:00:00Z"))
    }

    @Test func theSelectionFollowsBeforeTheSaveFinishes() async {
        let (model, source) = await loaded([make("x", "2026-11-10T09:00:00Z")])
        model.selectNext()
        source.gate = true

        let task = Task { await model.moveSelectionByDay(-1, span: .thisOccurrence) }
        await source.waitForPending(1)

        #expect(model.selection == grid("x", 9))
        source.release(at: 0)
        await task.value
    }

    @Test func aSecondMoveIsIgnoredWhileOneIsBeingSaved() async {
        let (model, source) = await loaded([make("x", "2026-11-10T09:00:00Z")])
        model.selectNext()
        source.gate = true

        let task = Task { await model.moveSelectionInTime(1, span: .thisOccurrence) }
        await source.waitForPending(1)
        await model.moveSelectionInTime(1, span: .thisOccurrence)
        await model.moveSelectionByDay(1, span: .thisOccurrence)

        #expect(source.updates.count == 1)
        source.release(at: 0)
        await task.value
    }

    @Test func movingByADayPastTheEndOfTheWeekFollowsTheItemToTheNextWeek() async {
        let source = FakeSource()
        source.snapshots[nextWeekStart] = TimelineSnapshot(
            items: [make("sat#2", calendarItem: "sat", "2026-11-15T09:00:00Z")], overdue: []
        )
        let (model, _) = await loaded([make("sat#1", calendarItem: "sat", "2026-11-14T09:00:00Z")], source: source)
        model.selectNext()
        #expect(model.selection == grid("sat#1", 14))

        await model.moveSelectionByDay(1, span: .futureOccurrences)

        #expect(source.updates.map(\.draft.start) == [iso("2026-11-15T09:00:00Z")])
        #expect(source.updates.map(\.span) == [.futureOccurrences])
        #expect(model.range.start == nextWeekStart)
        #expect(model.selection == grid("sat#2", 15))
    }

    @Test func movingByADayPastTheStartOfTheWeekFollowsTheItemToThePreviousWeek() async {
        let source = FakeSource()
        source.snapshots[previousWeekStart] = TimelineSnapshot(
            items: [make("sun", "2026-11-07T09:00:00Z")], overdue: []
        )
        let (model, _) = await loaded([make("sun", "2026-11-08T09:00:00Z")], source: source)
        model.selectNext()

        await model.moveSelectionByDay(-1, span: .thisOccurrence)

        #expect(source.updates.map(\.draft.start) == [iso("2026-11-07T09:00:00Z")])
        #expect(model.range.start == previousWeekStart)
        #expect(model.selection == grid("sun", 7))
    }

    @Test func theSelectionFollowsOutOfTheWeekEvenWhenAnotherLoadCutsIn() async {
        let source = FakeSource()
        source.snapshots[nextWeekStart] = TimelineSnapshot(
            items: [make("sat", "2026-11-15T09:00:00Z")], overdue: []
        )
        let (model, _) = await loaded([make("sat", "2026-11-14T09:00:00Z")], source: source)
        model.selectNext()
        source.gate = true

        // 保存の直後に来る変更通知の読み込みが、表示を進める読み込みを追い越す
        let move = Task { await model.moveSelectionByDay(1, span: .thisOccurrence) }
        await source.waitForPending(1)
        let notified = Task { await model.load() }
        await source.waitForPending(2)
        source.release(at: 0)
        // 追い越された側が読み直しても、どちらが先に終わっても、選択は付いていく。残りの読み込みは来た順に通す
        var finished = false
        let both = Task {
            await move.value
            await notified.value
            finished = true
        }
        while !finished {
            if source.pendingCount > 0 { source.release(at: 0) }
            await Task.yield()
        }
        await both.value

        #expect(model.range.start == nextWeekStart)
        #expect(model.selection == grid("sat", 15))
    }

    @Test func aFailedMoveOutOfTheWeekKeepsTheViewAndShowsTheError() async {
        let source = FakeSource()
        source.updateError = TestError()
        let (model, _) = await loaded([make("sat", "2026-11-14T09:00:00Z")], source: source)
        model.selectNext()

        await model.moveSelectionByDay(1, span: .thisOccurrence)

        #expect(model.range.start == weekStart)
        #expect(model.errorMessage != nil)
        #expect(model.selection == grid("sat", 14))
    }

    @Test func aSecondMoveIsIgnoredWhileAMoveOutOfTheWeekIsBeingSaved() async {
        let (model, source) = await loaded([make("sat", "2026-11-14T09:00:00Z")])
        model.selectNext()
        source.gate = true

        let task = Task { await model.moveSelectionByDay(1, span: .thisOccurrence) }
        await source.waitForPending(1)
        await model.moveSelectionByDay(1, span: .thisOccurrence)
        await model.moveSelectionInTime(1, span: .thisOccurrence)

        #expect(source.updates.count == 1)
        source.release(at: 0)
        await task.value
    }

    @Test func allDayItemsMoveByADayAndTheViewFollowsPastTheEdge() async {
        let source = FakeSource()
        source.snapshots[nextWeekStart] = TimelineSnapshot(
            items: [make("sat", "2026-11-15T00:00:00Z", hours: 24, allDay: true)], overdue: []
        )
        let (model, _) = await loaded([make("sat", "2026-11-14T00:00:00Z", hours: 24, allDay: true)], source: source)
        model.selectNext()
        #expect(model.selection == TimelineSelection(itemID: "sat", place: .allDay))

        await model.moveSelectionByDay(-1, span: .thisOccurrence)
        #expect(source.updates.map(\.draft.start) == [iso("2026-11-13T00:00:00Z")])
        #expect(source.updates.map(\.draft.isAllDay) == [true])
        #expect(model.selection == TimelineSelection(itemID: "sat", place: .allDay))
        #expect(model.range.start == weekStart)

        // 土曜の終日を右へ動かすと、次の週へ移って選択も付いていく
        await model.moveSelectionByDay(1, span: .thisOccurrence)
        #expect(source.updates.map(\.draft.start).last == iso("2026-11-15T00:00:00Z"))
        #expect(model.range.start == nextWeekStart)
        #expect(model.selection == TimelineSelection(itemID: "sat", place: .allDay))
        #expect(model.selectedItem?.start == iso("2026-11-15T00:00:00Z"))
    }

    @Test func aMultiDayAllDayItemMovesPartlyOutOfTheWeekWithoutMovingTheView() async {
        // 日〜月の帯を、月曜の列から選ぶ。左へ動かすと帯の頭は前の週へ出るが、いまいる列は日曜に残る
        let (model, source) = await loaded([
            make("trip", "2026-11-08T00:00:00Z", hours: 48, allDay: true),
            make("x", "2026-11-09T09:00:00Z"),
        ])
        model.selectNext()
        await model.selectRight()
        #expect(model.selection == grid("x", 9))
        model.selectPrevious()
        #expect(model.selection == TimelineSelection(itemID: "trip", place: .allDay))

        await model.moveSelectionByDay(-1, span: .thisOccurrence)

        #expect(source.updates.map(\.draft.start) == [iso("2026-11-07T00:00:00Z")])
        #expect(model.range.start == weekStart)
        #expect(model.selection == TimelineSelection(itemID: "trip", place: .allDay))
    }

    @Test func nothingMovesInTimeForAllDayOverdueOrReadOnlyItems() async {
        let old = item("old", start: iso("2026-11-01T09:00:00Z"))
        let (model, source) = await loaded([
            make("holiday", "2026-11-10T00:00:00Z", hours: 24, allDay: true),
            make("birthday", "2026-11-10T09:00:00Z", editable: false),
        ], overdue: [old])

        for _ in 0..<3 {
            model.selectNext()
            await model.moveSelectionInTime(1, span: .thisOccurrence)
            await model.moveSelectionByDay(1, span: .thisOccurrence)
        }

        #expect(model.selection == grid("birthday", 10))
        // 終日の予定だけが日単位で動く
        #expect(source.updates.map(\.item.id) == ["holiday"])
    }

    @Test func movingByADayInDayModeShowsTheDayTheItemMovedTo() async {
        let source = FakeSource()
        source.snapshots[day(11)] = TimelineSnapshot(
            items: [make("x#2", calendarItem: "x", "2026-11-11T09:00:00Z")], overdue: []
        )
        source.snapshots[today] = TimelineSnapshot(
            items: [make("x#1", calendarItem: "x", "2026-11-10T09:00:00Z")], overdue: []
        )
        let model = TimelineModel(source: source, calendar: utc, mode: .day) { self.today }
        await model.activate()
        model.selectNext()

        await model.moveSelectionByDay(1, span: .thisOccurrence)

        #expect(source.updates.map(\.draft.start) == [iso("2026-11-11T09:00:00Z")])
        #expect(model.day == day(11))
        #expect(model.selection == grid("x#2", 11))
    }

    @Test func movingAnAllDayItemByADayInDayModeShowsTheDayItMovedTo() async {
        let source = FakeSource()
        source.snapshots[day(9)] = TimelineSnapshot(
            items: [make("holiday", "2026-11-09T00:00:00Z", hours: 24, allDay: true)], overdue: []
        )
        let (model, _) = await loaded(
            [make("holiday", "2026-11-10T00:00:00Z", hours: 24, allDay: true)], mode: .day, source: source
        )
        model.selectNext()

        await model.moveSelectionByDay(-1, span: .thisOccurrence)

        #expect(source.updates.map(\.draft.start) == [iso("2026-11-09T00:00:00Z")])
        #expect(model.day == day(9))
        #expect(model.selection == TimelineSelection(itemID: "holiday", place: .allDay))
    }

    @Test func nothingMovesWithoutASelection() async {
        let (model, source) = await loaded([make("x", "2026-11-10T09:00:00Z")])

        await model.moveSelectionInTime(1, span: .thisOccurrence)
        await model.moveSelectionByDay(1, span: .thisOccurrence)

        #expect(source.updates.isEmpty)
    }

    // MARK: - 選択中の項目を削除する

    @Test func deletingSendsTheSelectedItemWithItsSpanAndReloads() async {
        let (model, source) = await loaded([make("a", "2026-11-10T09:00:00Z")])
        model.selectNext()
        let requests = source.requests.count

        await model.deleteSelection(span: .futureOccurrences)

        #expect(source.deletions.map(\.item.id) == ["a"])
        #expect(source.deletions.map(\.span) == [.futureOccurrences])
        #expect(source.requests.count == requests + 1)
        #expect(model.columns.flatMap(\.placements).isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test func afterDeletingTheNextItemInTheColumnIsSelected() async {
        let (model, _) = await loaded([
            make("a", "2026-11-10T09:00:00Z"),
            make("b", "2026-11-10T12:00:00Z"),
            make("c", "2026-11-10T15:00:00Z"),
            make("wed", "2026-11-11T09:00:00Z"),
        ])
        model.selectNext()
        model.selectNext()

        await model.deleteSelection(span: .thisOccurrence)

        #expect(model.selection == grid("c", 10))
    }

    @Test func afterDeletingTheLastItemOfTheColumnThePreviousOneIsSelected() async {
        let (model, _) = await loaded([
            make("a", "2026-11-10T09:00:00Z"),
            make("b", "2026-11-10T12:00:00Z"),
            make("wed", "2026-11-11T09:00:00Z"),
        ])
        model.selectPrevious()

        await model.deleteSelection(span: .thisOccurrence)

        #expect(model.selection == grid("a", 10))
    }

    @Test func deletingTheOnlyItemOfTheColumnLeavesNothingSelected() async {
        let (model, _) = await loaded([
            make("a", "2026-11-10T09:00:00Z"),
            make("wed", "2026-11-11T09:00:00Z"),
        ])
        model.selectNext()

        await model.deleteSelection(span: .thisOccurrence)

        #expect(model.selection == nil)
    }

    @Test func deletingAnAllDayItemSelectsTheNextEntryOfTheColumn() async {
        let (model, source) = await loaded([
            make("holiday", "2026-11-10T00:00:00Z", hours: 24, allDay: true),
            make("a", "2026-11-10T09:00:00Z"),
        ], mode: .day)
        model.selectNext()
        #expect(model.selection == TimelineSelection(itemID: "holiday", place: .allDay))

        await model.deleteSelection(span: .thisOccurrence)

        #expect(source.deletions.map(\.item.id) == ["holiday"])
        #expect(model.selection == grid("a", 10))
    }

    /// 週の中の過ぎた日の未完了は、期限切れ欄とその日の列の両方に出る。消したあとに同じ項目の別の場所を選ばない。
    @Test func deletingAnOverdueReminderSkipsItsOtherPlaceInTheSameColumn() async {
        let (model, _) = await loaded([
            make("mon", kind: .reminder, "2026-11-09T09:00:00Z"),
            make("later", "2026-11-09T12:00:00Z"),
        ])
        model.selectNext()
        await model.selectLeft()
        model.selectPrevious()
        #expect(model.selection == TimelineSelection(itemID: "mon", place: .overdue))

        await model.deleteSelection(span: .thisOccurrence)

        #expect(model.selection == grid("later", 9))
    }

    @Test func nothingIsDeletedForReadOnlyItemsOrWithoutASelection() async {
        let (model, source) = await loaded([make("birthday", "2026-11-10T09:00:00Z", editable: false)])
        let requests = source.requests.count

        await model.deleteSelection(span: .thisOccurrence)
        model.selectNext()
        await model.deleteSelection(span: .thisOccurrence)

        #expect(source.deletions.isEmpty)
        #expect(source.requests.count == requests)
        #expect(model.selection == grid("birthday", 10))
    }

    @Test func aFailedDeleteShowsTheErrorAndKeepsTheSelection() async {
        let source = FakeSource()
        source.deleteError = TestError()
        let (model, _) = await loaded([
            make("a", "2026-11-10T09:00:00Z"),
            make("b", "2026-11-10T12:00:00Z"),
        ], source: source)
        model.selectNext()
        let requests = source.requests.count

        await model.deleteSelection(span: .thisOccurrence)

        #expect(model.errorMessage != nil)
        #expect(model.selection == grid("a", 10))
        #expect(source.requests.count == requests)
    }

    @Test func aSecondDeleteIsIgnoredWhileOneIsBeingSaved() async {
        let (model, source) = await loaded([
            make("a", "2026-11-10T09:00:00Z"),
            make("b", "2026-11-10T12:00:00Z"),
        ])
        model.selectNext()
        source.gate = true

        let task = Task { await model.deleteSelection(span: .thisOccurrence) }
        await source.waitForPending(1)
        await model.deleteSelection(span: .thisOccurrence)
        await model.moveSelectionByDay(1, span: .thisOccurrence)

        #expect(source.deletions.count == 1)
        #expect(source.updates.isEmpty)
        source.release(at: 0)
        await task.value
        #expect(model.selection == grid("b", 10))
    }
}

@MainActor
@Suite struct TimelineModelThreeDaysTests {
    /// 2026-11-10 は火曜。週（日曜始まり）は 11-08 〜 11-14。
    let today = iso("2026-11-10T00:00:00Z")
    let weekStart = iso("2026-11-08T00:00:00Z")

    private func day(_ dayOfMonth: Int) -> Date {
        iso("2026-11-\(String(format: "%02d", dayOfMonth))T00:00:00Z")
    }

    private func makeModel(
        _ source: FakeSource, mode: TimelineMode = .threeDays, now: @escaping () -> Date
    ) -> TimelineModel {
        TimelineModel(source: source, calendar: utc, mode: mode, now: now)
    }

    @Test func threeDaysStartAtTodayAndHaveThreeColumns() async {
        let source = FakeSource()
        let tue = item("tue", start: iso("2026-11-10T09:00:00Z"))
        let thu = item("thu", start: iso("2026-11-12T15:00:00Z"))
        source.snapshots[today] = TimelineSnapshot(items: [thu, tue], overdue: [])
        let model = makeModel(source) { self.today }

        await model.activate()

        #expect(model.range == DateInterval(start: today, end: day(13)))
        #expect(source.requests.map(\.range) == [DateInterval(start: today, end: day(13))])
        #expect(model.columns.map(\.day) == [today, day(11), day(12)])
        #expect(model.columns[0].placements.map(\.id) == ["tue"])
        #expect(model.columns[2].placements.map(\.id) == ["thu"])
        #expect(model.isLoadedForRange)
    }

    @Test func previousAndNextMoveByOneDay() async {
        let source = FakeSource()
        let model = makeModel(source) { self.today }

        await model.showNext()
        #expect(model.columns.map(\.day) == [day(11), day(12), day(13)])
        await model.showPrevious()
        await model.showPrevious()

        #expect(model.columns.map(\.day) == [day(9), today, day(11)])
        #expect(source.requests.map(\.range.start) == [day(11), today, day(9)])
        #expect(source.requests.map(\.range.end) == [day(14), day(13), day(12)])
    }

    @Test func overdueIsRequestedOnlyWhileTheThreeDaysContainToday() async {
        let source = FakeSource()
        let model = makeModel(source) { self.today }

        // 今日が右端（8・9・10）→ 外れる（7・8・9）→ 今日が左端 → 外れる（11・12・13）
        await model.showPrevious()
        await model.showPrevious()
        #expect(model.containsToday)
        await model.showPrevious()
        #expect(model.containsToday == false)
        await model.showToday()
        await model.showNext()

        #expect(source.requests.map(\.includingOverdue) == [true, true, false, true, false])
    }

    @Test func pastDaysInTheThreeDaysAddTheirOpenRemindersToOverdue() async {
        let source = FakeSource()
        let yesterday = item("昨日", start: iso("2026-11-09T09:00:00Z"))
        source.snapshots[day(9)] = TimelineSnapshot(
            items: [yesterday, item("今日", start: iso("2026-11-10T09:00:00Z"))],
            overdue: [item("先週", start: iso("2026-11-01T09:00:00Z"))]
        )
        let model = makeModel(source) { iso("2026-11-10T08:00:00Z") }

        await model.showPrevious()

        #expect(model.timeline.overdue.map(\.id) == ["先週", "昨日"])
        #expect(model.columns[0].placements.map(\.id) == ["昨日"])
    }

    @Test func switchingFromDayPutsThatDayAtTheLeft() async {
        let source = FakeSource()
        let model = makeModel(source, mode: .day) { self.today }
        await model.showNext()
        await model.showNext()

        await model.setMode(.threeDays)

        #expect(model.columns.map(\.day) == [day(12), day(13), day(14)])
        #expect(source.requests.last?.range == DateInterval(start: day(12), end: day(15)))
    }

    @Test func switchingFromThisWeekPutsTodayAtTheLeft() async {
        let source = FakeSource()
        let model = makeModel(source, mode: .week) { self.today }
        await model.activate()

        await model.setMode(.threeDays)

        #expect(model.day == today)
        #expect(model.columns.map(\.day) == [today, day(11), day(12)])
    }

    @Test func switchingFromAnotherWeekKeepsItsDayAtTheLeft() async {
        let source = FakeSource()
        let model = makeModel(source, mode: .week) { self.today }
        await model.showNext()

        await model.setMode(.threeDays)

        #expect(model.columns.map(\.day) == [day(17), day(18), day(19)])
        #expect(model.containsToday == false)
    }

    @Test func switchingToDayShowsTodayWhenTheThreeDaysContainIt() async {
        let source = FakeSource()
        let model = makeModel(source) { self.today }
        await model.showPrevious()

        await model.setMode(.day)

        #expect(model.day == today)
    }

    @Test func switchingToDayKeepsTheLeftDayWhenTodayIsNotShown() async {
        let source = FakeSource()
        let model = makeModel(source) { self.today }
        await model.showNext()

        await model.setMode(.day)

        #expect(model.day == day(11))
    }

    @Test func switchingToWeekShowsThisWeekWhenTheThreeDaysContainToday() async {
        let source = FakeSource()
        // 日曜（週の始まり）が今日。土・日・月を見ていても、週表示は今日の週にする
        let model = makeModel(source) { self.weekStart }
        await model.showPrevious()
        #expect(model.day == day(7))

        await model.setMode(.week)

        #expect(model.range.start == weekStart)
        #expect(model.containsToday)
    }

    @Test func switchingBackFromThreeDaysWithTodayInTheMiddlePutsTodayAtTheLeft() async {
        let source = FakeSource()
        let model = makeModel(source) { self.today }
        await model.showPrevious()

        await model.setMode(.week)
        await model.setMode(.threeDays)

        #expect(model.columns.map(\.day) == [today, day(11), day(12)])
    }

    @Test func dayChangeKeepsTodayAtTheLeft() async {
        let source = FakeSource()
        var now = today
        let model = makeModel(source) { now }
        await model.activate()

        now = day(11)
        await model.handleDayChanged()

        #expect(model.columns.map(\.day) == [day(11), day(12), day(13)])
        #expect(source.requests.map(\.includingOverdue) == [true, true])
    }

    @Test func dayChangeDoesNotMoveThreeDaysTheUserShifted() async {
        let source = FakeSource()
        var now = today
        let model = makeModel(source) { now }
        // 今日が真ん中（9・10・11）。日付が変わっても、自分でずらした並びは動かさない
        await model.showPrevious()

        now = day(11)
        await model.handleDayChanged()

        #expect(model.columns.map(\.day) == [day(9), today, day(11)])
    }

    @Test func dayChangeResumesFollowingWhenTheLeftDayBecomesToday() async {
        let source = FakeSource()
        var now = today
        let model = makeModel(source) { now }
        await model.showNext()

        now = day(11)
        await model.handleDayChanged()
        now = day(12)
        await model.handleDayChanged()

        #expect(model.columns.map(\.day) == [day(12), day(13), day(14)])
    }

    @Test func todayButtonPutsTodayAtTheLeft() async {
        let source = FakeSource()
        let model = makeModel(source) { iso("2026-11-10T15:00:00Z") }
        await model.showPrevious()

        await model.showToday()

        #expect(model.columns.map(\.day) == [today, day(11), day(12)])
    }

    @Test func threeDaysAreAlignedWithTodayOnlyWhenTodayIsAtTheLeft() async {
        let source = FakeSource()
        let model = makeModel(source) { self.today }
        #expect(model.isAlignedWithToday)

        // 今日が真ん中。見えてはいるが、「今日」で左端へ戻せる
        await model.showPrevious()
        #expect(model.containsToday)
        #expect(model.isAlignedWithToday == false)

        await model.showToday()
        #expect(model.isAlignedWithToday)
    }

    @Test func dayAndWeekAreAlignedWithTodayWhileTheyContainIt() async {
        let source = FakeSource()
        let model = makeModel(source, mode: .week) { self.today }
        #expect(model.isAlignedWithToday)
        await model.showNext()
        #expect(model.isAlignedWithToday == false)

        await model.setMode(.day)
        await model.showToday()
        #expect(model.isAlignedWithToday)
        await model.showNext()
        #expect(model.isAlignedWithToday == false)
    }

    @Test func allDaySpansAreClippedToTheThreeColumns() async {
        let source = FakeSource()
        func allDay(_ id: String, from start: Date, to end: String) -> TimelineItem {
            TimelineItem(
                id: id, calendarItemIdentifier: id, kind: .event, title: id, start: start, end: iso(end),
                isAllDay: true, isCompleted: false, sourceName: "", accountName: "",
                color: CGColor(gray: 0, alpha: 1), recurrence: nil
            )
        }
        // 月〜水の出張は左で、木〜土の旅行は右で切れる
        let trip = allDay("trip", from: day(9), to: "2026-11-11T23:59:59Z")
        let travel = allDay("travel", from: day(12), to: "2026-11-14T23:59:59Z")
        source.snapshots[today] = TimelineSnapshot(items: [trip, travel], overdue: [])
        let model = makeModel(source) { self.today }

        await model.activate()

        #expect(model.allDaySpans.map(\.id).sorted() == ["travel", "trip"])
        let spans = Dictionary(uniqueKeysWithValues: model.allDaySpans.map { ($0.id, $0) })
        #expect(spans["trip"]?.firstColumn == 0)
        #expect(spans["trip"]?.columnSpan == 2)
        #expect(spans["travel"]?.firstColumn == 2)
        #expect(spans["travel"]?.columnSpan == 1)
    }

    // MARK: - 左右の選択

    private func event(_ id: String, _ start: String, editable: Bool = true) -> TimelineItem {
        let start = iso(start)
        return TimelineItem(
            id: id, calendarItemIdentifier: id, kind: .event, title: id, start: start,
            end: start.addingTimeInterval(3600), isAllDay: false, isCompleted: false, sourceName: "",
            accountName: "", color: CGColor(gray: 0, alpha: 1), recurrence: nil,
            isEditable: editable
        )
    }

    private func grid(_ id: String, _ dayOfMonth: Int) -> TimelineSelection {
        TimelineSelection(itemID: id, place: .grid(day: day(dayOfMonth)))
    }

    /// 今日（10 日）を左端にした 3 日表示。`later` は表示をずらしたあとの範囲（左端の日）ごとの内容。
    private func loaded(
        _ items: [TimelineItem], later: [Int: [TimelineItem]] = [:]
    ) async -> (TimelineModel, FakeSource) {
        let source = FakeSource()
        source.snapshots[today] = TimelineSnapshot(items: items, overdue: [])
        for (first, items) in later {
            source.snapshots[day(first)] = TimelineSnapshot(items: items, overdue: [])
        }
        let model = makeModel(source) { self.today }
        await model.activate()
        return (model, source)
    }

    @Test func leftAndRightMoveBetweenTheDaysWithItems() async {
        let (model, _) = await loaded([
            event("a", "2026-11-10T09:00:00Z"),
            event("c9", "2026-11-12T09:30:00Z"),
            event("c15", "2026-11-12T15:00:00Z"),
        ])
        model.selectNext()

        // 水曜は空なので飛ばす
        await model.selectRight()
        #expect(model.selection == grid("c9", 12))
        await model.selectLeft()
        #expect(model.selection == grid("a", 10))
        #expect(model.day == today)
    }

    @Test func rightWithoutASelectionStartsLikeNext() async {
        let (model, _) = await loaded([event("a", "2026-11-10T09:00:00Z"), event("c", "2026-11-12T09:00:00Z")])

        await model.selectRight()

        #expect(model.selection == grid("a", 10))
        #expect(model.day == today)
    }

    @Test func rightAtTheLastDayShiftsByOneDayAndSelectsTheNearestItemOfTheNewDay() async {
        let c = event("c", "2026-11-12T13:00:00Z")
        let (model, _) = await loaded([c], later: [11: [
            c, event("d8", "2026-11-13T08:00:00Z"), event("d14", "2026-11-13T14:00:00Z"),
        ]])
        model.selectNext()
        #expect(model.selection == grid("c", 12))

        await model.selectRight()

        #expect(model.columns.map(\.day) == [day(11), day(12), day(13)])
        #expect(model.selection == grid("d14", 13))
    }

    @Test func leftAtTheFirstDayShiftsByOneDayAndSelectsTheItemOfTheNewDay() async {
        let a = event("a", "2026-11-10T09:00:00Z")
        let (model, _) = await loaded([a], later: [9: [event("m", "2026-11-09T15:00:00Z"), a]])
        model.selectNext()

        await model.selectLeft()

        #expect(model.columns.map(\.day) == [day(9), today, day(11)])
        #expect(model.selection == grid("m", 9))
    }

    @Test func theSelectionStaysWhenTheNewDayIsEmptyAndItsItemIsStillShown() async {
        let b = event("b", "2026-11-11T09:00:00Z")
        let (model, _) = await loaded([b], later: [11: [b]])
        model.selectNext()

        await model.selectRight()

        #expect(model.columns.map(\.day) == [day(11), day(12), day(13)])
        #expect(model.selection == grid("b", 11))
    }

    @Test func holdingRightReachesTheNextDayWithItems() async {
        let (model, _) = await loaded(
            [event("a", "2026-11-10T09:00:00Z")], later: [12: [event("e", "2026-11-14T09:00:00Z")]]
        )
        model.selectNext()

        // 木曜は空。火曜の選択は画面の外へ出るので外れる
        await model.selectRight()
        #expect(model.columns.map(\.day) == [day(11), day(12), day(13)])
        #expect(model.selection == nil)

        // 選択が無く画面にも項目が無ければ、そのまま進んで新しい日の項目を選ぶ
        await model.selectRight()
        #expect(model.columns.map(\.day) == [day(12), day(13), day(14)])
        #expect(model.selection == grid("e", 14))
    }

    @Test func movingTheSelectionByADayPastTheEdgeShiftsTheThreeDaysByOneDay() async {
        let (model, source) = await loaded(
            [event("c", "2026-11-12T09:00:00Z")], later: [11: [event("c", "2026-11-13T09:00:00Z")]]
        )
        model.selectNext()
        #expect(model.selection == grid("c", 12))

        await model.moveSelectionByDay(1, span: .thisOccurrence)

        #expect(source.updates.map(\.draft.start) == [iso("2026-11-13T09:00:00Z")])
        #expect(model.columns.map(\.day) == [day(11), day(12), day(13)])
        #expect(model.selection == grid("c", 13))
    }

    @Test func movingTheSelectionByADayWorksInsideTheThreeDays() async {
        let (model, source) = await loaded([event("a", "2026-11-10T09:00:00Z")])
        model.selectNext()

        await model.moveSelectionByDay(1, span: .thisOccurrence)

        #expect(source.updates.map(\.draft.start) == [iso("2026-11-11T09:00:00Z")])
    }
}
