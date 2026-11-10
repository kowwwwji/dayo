import CoreGraphics
import Foundation
import Testing
@testable import DayoCore

/// テスト用の取得元。`gate` を立てると `snapshot` が `release` まで待つので、応答順を制御できる。
private final class FakeSource: CalendarSource {
    var accessResult: AccessStatus = .granted
    var snapshots: [Date: TimelineSnapshot] = [:]
    var setCompletedError: Error?
    private(set) var requests: [(range: DateInterval, includingOverdue: Bool)] = []
    private(set) var completions: [(id: String, completed: Bool)] = []
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
@Suite struct DayTimelineModelTests {
    let d0 = iso("2026-11-10T00:00:00Z")
    let d1 = iso("2026-11-11T00:00:00Z")
    let d2 = iso("2026-11-12T00:00:00Z")

    private func makeModel(_ source: FakeSource, now: @escaping () -> Date) -> DayTimelineModel {
        DayTimelineModel(source: source, calendar: utc, now: now)
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

        await model.showNextDay()
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

        let first = Task { await model.showNextDay() }
        await source.waitForPending(1)
        let second = Task { await model.showNextDay() }
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

        await model.showPreviousDay()
        now = d1
        await model.handleDayChanged()
        #expect(model.day == iso("2026-11-09T00:00:00Z"))

        await model.showToday()
        await model.showNextDay()
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
}
