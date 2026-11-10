import Foundation
import Observation

/// 1 日分のタイムライン画面の状態。権限・表示日・読み込み・完了操作・変更監視を持つ。
@MainActor
@Observable
public final class TimelineModel {
    public private(set) var access: AccessStatus = .notDetermined
    /// 表示中の日（その日の 0:00）。
    public private(set) var day: Date
    public private(set) var timeline = DayTimeline(items: [], overdue: [])
    /// `timeline.timed` を時間軸グリッドに配置した結果。
    public private(set) var placements: [GridPlacement] = []
    /// 一度でも読み込みに成功したか。空表示を出す前の判定に使う。
    public private(set) var hasLoaded = false
    /// 最後に読み込みが完了した日。`day` と一致していればいま表示中の日の内容が揃っている。
    public private(set) var loadedDay: Date?

    /// 表示中の日の内容が読み込み済みか。グリッドの初期スクロールはこれを待ってから行う
    /// （前の日の内容で帯の有無を決めると、読み込み後に位置がずれる）。
    public var isLoadedForDay: Bool { loadedDay == day }
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
            loadedDay = day
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

    /// ドラッグで同じ日の別の時刻へ動かした。
    /// 表示は先に動かし（楽観更新。離した瞬間に元の位置へ戻ってちらつかないため）、保存後に読み直す。
    /// 失敗したらメッセージを出し、読み直して元に戻す。
    public func move(_ item: TimelineItem, toStartMinute minute: Int, span: EditSpan) async {
        guard !item.isAllDay, let start = item.start,
              let range = calendar.dateInterval(of: .day, for: day),
              let placement = placements.first(where: { $0.id == item.id })
        else { return }
        // 表示上の移動量だけずらす。前日から続く予定は 0:00 で切って表示しているので、絶対位置にすると飛ぶ
        let delta = TimeInterval((minute - placement.startMinute) * 60)
        let draft = ItemDraft(moving: item, to: start.addingTimeInterval(delta))

        let previous = (timeline, placements)
        if let index = timeline.timed.firstIndex(where: { $0.id == item.id }) {
            timeline.timed[index].start = draft.start
            timeline.timed[index].end = draft.end
            placements = DayGridLayout.place(timeline.timed, in: range)
        }
        // 進行中の読み込み（同期通知など）が古い内容で楽観更新を上書きしないようにする
        loadGeneration += 1

        do {
            try await source.update(item, with: draft, span: span)
            await load()
        } catch {
            // まず元に戻し、読み直しが失敗しても動いたままに見えないようにする。メッセージは load が消すので最後に
            (timeline, placements) = previous
            await load()
            errorMessage = error.localizedDescription
        }
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
