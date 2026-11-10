import Foundation
import Observation

/// 一度に表示する範囲。
public enum TimelineMode: String, CaseIterable, Sendable {
    case day
    case week
}

/// タイムライン画面の状態。権限・表示範囲・読み込み・完了操作・変更監視を持つ。
/// 日表示と週表示は列の数が違うだけで、同じ状態から導く。
@MainActor
@Observable
public final class TimelineModel {
    public private(set) var access: AccessStatus = .notDetermined
    public private(set) var mode: TimelineMode
    /// 表示の基準日（その日の 0:00）。週表示ではこの日を含む週を出す。
    public private(set) var day: Date
    /// 表示範囲の項目（将来回の仮想項目を含む）をセクションに振り分けたもの。
    public private(set) var timeline = DayTimeline(items: [], overdue: [])
    /// 表示範囲の日ごとの列。日表示なら 1 列。
    public private(set) var columns: [TimelineColumn] = []
    /// 終日欄の帯。週表示で使う。
    public private(set) var allDaySpans: [AllDaySpan] = []
    /// 一度でも読み込みに成功したか。空表示を出す前の判定に使う。
    public private(set) var hasLoaded = false
    /// 最後に読み込みが完了した範囲。`range` と一致していればいま表示中の範囲の内容が揃っている。
    public private(set) var loadedRange: DateInterval?

    /// 表示中の範囲の内容が読み込み済みか。グリッドの初期スクロールはこれを待ってから行う
    /// （前の範囲の内容で帯の有無を決めると、読み込み後に位置がずれる）。
    public var isLoadedForRange: Bool { loadedRange == range }
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
        mode: TimelineMode = .day,
        now: @escaping () -> Date = { .now }
    ) {
        self.source = source
        self.calendar = calendar
        self.mode = mode
        self.now = now
        day = calendar.startOfDay(for: now())
        columns = TimelineColumns.columns(for: [], days: days, calendar: calendar)
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

    /// 表示範囲。日表示なら `day` の 1 日、週表示なら `day` を含む週（週の始まりは暦の設定に従う）。
    public var range: DateInterval {
        let component: Calendar.Component = mode == .day ? .day : .weekOfYear
        return calendar.dateInterval(of: component, for: day) ?? DateInterval(start: day, duration: 86_400)
    }

    /// 表示範囲の各日の 0:00。
    public var days: [Date] { days(in: range) }

    /// 全列の配置。時間帯の畳み込みは列をまたいで 1 本の軸で決めるので、まとめて渡す。
    public var placements: [GridPlacement] { columns.flatMap(\.placements) }

    /// 表示範囲が今日を含むか。
    public var containsToday: Bool {
        // `DateInterval.contains` は終端を含むので、翌日 0:00 を今日と数えないよう自前で比べる
        let range = range, now = now()
        return range.start <= now && now < range.end
    }

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
        let range = range
        let includesOverdue = containsToday
        let today = calendar.startOfDay(for: now())
        do {
            let snapshot = try await source.snapshot(for: range, includingOverdue: includesOverdue)
            guard generation == loadGeneration else { return }
            // 取得元の期限切れは範囲より前のものだけ。週表示では週の中の過ぎた日の未完了も足して、
            // 日表示で今日を見たときと同じ内容にする（その日の列にも残る）
            let overdueInRange = includesOverdue
                ? snapshot.items.filter { item in
                    item.kind == .reminder && !item.isCompleted && item.start.map { $0 < today } == true
                }
                : []
            let virtual = futureRange(in: range).map {
                VirtualOccurrences.expand(snapshot.recurring, in: $0, calendar: calendar)
            } ?? []
            timeline = DayTimeline(items: snapshot.items + virtual, overdue: snapshot.overdue + overdueInRange)
            layOut()
            hasLoaded = true
            loadedRange = range
            errorMessage = nil
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    public func toggleCompleted(_ item: TimelineItem) async {
        guard !item.isVirtual else { return }
        do {
            try await source.setCompleted(!item.isCompleted, for: item)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await load()
    }

    /// ドラッグで別の時刻・別の日へ動かした。`originDay` は掴んだ列の日、`minute` は落とした列での開始分。
    /// 表示は先に動かし（楽観更新。離した瞬間に元の位置へ戻ってちらつかないため）、保存後に読み直す。
    /// 失敗したらメッセージを出し、読み直して元に戻す。
    public func move(
        _ item: TimelineItem,
        from originDay: Date,
        toDay: Date,
        startMinute minute: Int,
        span: EditSpan
    ) async {
        guard !item.isVirtual, !item.isAllDay, let start = item.start,
              let placement = columns.first(where: { $0.day == originDay })?
                  .placements.first(where: { $0.id == item.id }),
              let dayDelta = calendar.dateComponents([.day], from: originDay, to: toDay).day,
              let shifted = calendar.date(byAdding: .day, value: dayDelta, to: start)
        else { return }
        // 表示上の移動量だけずらす。前日から続く予定は 0:00 で切って表示しているので、絶対位置にすると飛ぶ
        let delta = TimeInterval((minute - placement.startMinute) * 60)
        let draft = ItemDraft(moving: item, to: shifted.addingTimeInterval(delta))

        let previous = timeline
        if let index = timeline.timed.firstIndex(where: { $0.id == item.id }) {
            timeline.timed[index].start = draft.start
            timeline.timed[index].end = draft.end
            layOut()
        }
        // 進行中の読み込み（同期通知など）が古い内容で楽観更新を上書きしないようにする
        loadGeneration += 1

        do {
            try await source.update(item, with: draft, span: span)
            await load()
        } catch {
            // まず元に戻し、読み直しが失敗しても動いたままに見えないようにする。メッセージは load が消すので最後に
            timeline = previous
            layOut()
            await load()
            errorMessage = error.localizedDescription
        }
    }

    public func setMode(_ newMode: TimelineMode) async {
        guard newMode != mode else { return }
        // 今週を見ていて日表示へ戻すなら、基準日ではなく今日を出す
        if newMode == .day, containsToday {
            day = calendar.startOfDay(for: now())
        }
        mode = newMode
        followsToday = containsToday
        // 列の数は読み込みを待たずに合わせる。1 列のまま週の見出しが出ると列がずれて見える
        layOut()
        await load()
    }

    /// 前の日、週表示なら前の週へ。
    public func showPrevious() async {
        await show(day: calendar.date(byAdding: stepComponent, value: -1, to: day))
    }

    /// 次の日、週表示なら次の週へ。
    public func showNext() async {
        await show(day: calendar.date(byAdding: stepComponent, value: 1, to: day))
    }

    public func showToday() async {
        await show(day: now())
    }

    /// 日付が変わった。今日を追従中か、表示していた日が新しい今日になったなら今日へ移る。
    public func handleDayChanged() async {
        guard followsToday || containsToday else { return }
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
        if followsToday, !calendar.isDate(day, inSameDayAs: now()) {
            day = calendar.startOfDay(for: now())
        }
        await load()
    }

    private func show(day newDay: Date?) async {
        guard let newDay else { return }
        day = calendar.startOfDay(for: newDay)
        followsToday = containsToday
        await load()
    }

    private var stepComponent: Calendar.Component { mode == .day ? .day : .weekOfYear }

    private func days(in range: DateInterval) -> [Date] {
        var result: [Date] = []
        var day = range.start
        while day < range.end {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// 将来回を展開する範囲。過ぎた時刻の回は「これから来る回」ではないので、いまより前は切る。
    private func futureRange(in range: DateInterval) -> DateInterval? {
        let start = max(range.start, now())
        return start < range.end ? DateInterval(start: start, end: range.end) : nil
    }

    private func layOut() {
        let days = days
        columns = TimelineColumns.columns(for: timeline.timed, days: days, calendar: calendar)
        allDaySpans = TimelineColumns.allDaySpans(for: timeline.allDay, days: days, calendar: calendar)
    }
}
