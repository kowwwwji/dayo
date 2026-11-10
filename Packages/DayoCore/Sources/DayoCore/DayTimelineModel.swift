import Foundation
import Observation

/// 1 日分のタイムライン画面の状態。権限・表示日・読み込み・完了操作・変更監視を持つ。
@MainActor
@Observable
public final class DayTimelineModel {
    public private(set) var access: AccessStatus = .notDetermined
    /// 表示中の日（その日の 0:00）。
    public private(set) var day: Date
    public private(set) var timeline = DayTimeline(items: [], overdue: [])
    /// `timeline.timed` を時間軸グリッドに配置した結果。
    public private(set) var placements: [GridPlacement] = []
    /// 一度でも読み込みに成功したか。空表示を出す前の判定に使う。
    public private(set) var hasLoaded = false
    public private(set) var errorMessage: String?

    private let source: CalendarSource
    private let calendar: Calendar
    private let now: () -> Date
    /// 「今日」を表示中なら日付が変わったとき新しい今日へ追従する。
    private var followsToday = true
    /// 古い読み込み結果が新しい結果を上書きしないよう、最新の読み込みだけ採用する。
    private var loadGeneration = 0
    nonisolated(unsafe) private var observation: Task<Void, Never>?
    private var activation: Task<Void, Never>?

    public init(
        source: CalendarSource,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = { .now }
    ) {
        self.source = source
        self.calendar = calendar
        self.now = now
        day = calendar.startOfDay(for: now())
        // 監視は画面ではなくモデルが持つ。Mac で複数ウィンドウを開閉しても途切れない。
        let changes = source.changes
        observation = Task { [weak self] in
            for await _ in changes {
                guard let self, self.access == .granted else { continue }
                await self.load()
            }
        }
    }

    deinit {
        observation?.cancel()
    }

    public var isToday: Bool { calendar.isDate(day, inSameDayAs: now()) }

    /// 起動時と前面復帰時に呼ぶ。権限の再確認（設定で後から許可された場合を拾う）、
    /// 今日への追従、再読み込みを行う。同時に呼ばれても 1 回にまとめる。
    public func activate() async {
        if let activation {
            await activation.value
            return
        }
        let task = Task { await self.performActivation() }
        activation = task
        await task.value
        activation = nil
    }

    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        guard let range = calendar.dateInterval(of: .day, for: day) else { return }
        do {
            let snapshot = try await source.snapshot(for: range, includingOverdue: isToday)
            guard generation == loadGeneration else { return }
            timeline = DayTimeline(items: snapshot.items, overdue: snapshot.overdue)
            placements = DayGridLayout.place(timeline.timed, in: range)
            hasLoaded = true
            errorMessage = nil
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    public func toggleCompleted(_ item: TimelineItem) async {
        do {
            try await source.setCompleted(!item.isCompleted, for: item)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await load()
    }

    public func showPreviousDay() async {
        await show(day: calendar.date(byAdding: .day, value: -1, to: day))
    }

    public func showNextDay() async {
        await show(day: calendar.date(byAdding: .day, value: 1, to: day))
    }

    public func showToday() async {
        await show(day: now())
    }

    /// 日付が変わった。今日を追従中か、表示していた日が新しい今日になったなら今日へ移る。
    public func handleDayChanged() async {
        guard followsToday || isToday else { return }
        await showToday()
    }

    private func performActivation() async {
        do {
            access = try await source.requestAccess()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        guard access == .granted else { return }
        // 日付変更の通知を受けられないまま（バックグラウンドで日をまたぐ等）戻った場合に追従する。
        if followsToday, !isToday {
            day = calendar.startOfDay(for: now())
        }
        await load()
    }

    private func show(day newDay: Date?) async {
        guard let newDay else { return }
        day = calendar.startOfDay(for: newDay)
        followsToday = isToday
        await load()
    }
}
