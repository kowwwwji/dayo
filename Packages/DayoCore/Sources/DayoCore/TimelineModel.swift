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

    /// キー操作で選択中の項目。画面から消えたら外れる。
    public var selection: TimelineSelection? { cursorPosition?.selection }
    private var cursorPosition: TimelineCursor.Position?

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
            let virtual = futureOccurrences(of: snapshot.recurring, in: range)
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
    /// 表示は先に動かす（離した瞬間に元の位置へ戻ってちらつかないため）。
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
        await apply(ItemDraft(moving: item, to: shifted.addingTimeInterval(delta)), to: item, span: span)
    }

    /// 終日の項目を日単位で動かした。複数日にまたがる予定は長さを保つ。
    public func moveAllDay(_ item: TimelineItem, byDays days: Int, span: EditSpan) async {
        guard days != 0, isChangeable(item), item.isAllDay, let start = item.start,
              let shifted = calendar.date(byAdding: .day, value: days, to: start)
        else { return }
        await apply(ItemDraft(moving: item, to: shifted, isAllDay: true), to: item, span: span)
    }

    /// 終日の項目を時間軸へ落とした。その日のその時刻から始まる時刻付きの項目にする。
    public func makeTimed(_ item: TimelineItem, onDay day: Date, startMinute minute: Int, span: EditSpan) async {
        guard isChangeable(item), item.isAllDay,
              let start = calendar.date(byAdding: .minute, value: minute, to: calendar.startOfDay(for: day))
        else { return }
        await apply(ItemDraft(scheduling: item, at: start), to: item, span: span)
    }

    /// 時刻付きの項目を終日欄へ落とした。その日の終日にする。
    public func makeAllDay(_ item: TimelineItem, onDay day: Date, span: EditSpan) async {
        guard isChangeable(item), !item.isAllDay, item.start != nil else { return }
        await apply(ItemDraft(makingAllDay: item, on: calendar.startOfDay(for: day)), to: item, span: span)
    }

    /// 選択中の項目。
    public var selectedItem: TimelineItem? {
        cursorPosition.flatMap { cursor.item(for: $0.selection) }
    }

    /// 選択を下の項目へ。何も選択していなければ、今日（見えていなければ最初の日）の列の先頭を選ぶ。
    public func selectNext() {
        cursorPosition = movedVertically(by: 1)
    }

    /// 選択を上の項目へ。何も選択していなければ、今日（見えていなければ最初の日）の列の末尾を選ぶ。
    public func selectPrevious() {
        cursorPosition = movedVertically(by: -1)
    }

    /// 週表示では左隣の、項目のある日の列へ。無ければ前の週へ移る。日表示では前の日へ。
    public func selectLeft() async {
        await selectSideways(by: -1)
    }

    /// 週表示では右隣の、項目のある日の列へ。無ければ次の週へ移る。日表示では次の日へ。
    public func selectRight() async {
        await selectSideways(by: 1)
    }

    public func clearSelection() {
        cursorPosition = nil
    }

    /// 選択中のリマインダーを完了 / 未完了にする。予定には何もしない。
    public func toggleSelectedCompleted() async {
        guard let item = selectedItem, item.kind == .reminder else { return }
        await toggleCompleted(item)
    }

    private var cursor: TimelineCursor {
        TimelineCursor(days: days, overdue: timeline.overdue, allDaySpans: allDaySpans, columns: columns)
    }

    private func startPosition(at edge: TimelineCursor.Edge) -> TimelineCursor.Position? {
        cursor.start(on: containsToday ? calendar.startOfDay(for: now()) : nil, at: edge)
    }

    private func movedVertically(by step: Int) -> TimelineCursor.Position? {
        guard let cursorPosition else { return startPosition(at: step > 0 ? .first : .last) }
        return cursor.vertical(from: cursorPosition, by: step) ?? cursorPosition
    }

    private func selectSideways(by step: Int) async {
        guard mode == .week else {
            await showAdjacent(by: step)
            return
        }
        guard let cursorPosition else {
            cursorPosition = startPosition(at: .first)
            return
        }
        let cursor = cursor
        if let next = cursor.horizontal(from: cursorPosition, by: step) {
            self.cursorPosition = next
            return
        }
        // その方向に項目が無い。隣の週へ移り、来た側の端から近い時刻の項目を選ぶ
        let minute = cursor.startMinute(of: cursorPosition)
        await showAdjacent(by: step)
        guard isLoadedForRange else { return }
        self.cursorPosition = self.cursor.enter(by: step, nearMinute: minute)
    }

    private func showAdjacent(by step: Int) async {
        if step < 0 {
            await showPrevious()
        } else {
            await showNext()
        }
    }

    private func isChangeable(_ item: TimelineItem) -> Bool {
        !item.isVirtual && item.isEditable
    }

    /// 日時の変更を保存する。表示は先に変え（楽観更新）、保存後に読み直す。失敗したら元に戻してメッセージを出す。
    private func apply(_ draft: ItemDraft, to item: TimelineItem, span: EditSpan) async {
        let previous = timeline
        var updated = item
        updated.start = draft.start
        updated.end = draft.end
        updated.isAllDay = draft.isAllDay
        let others = (timeline.allDay + timeline.timed).filter { $0.id != item.id }
        timeline = DayTimeline(items: others + [updated], overdue: timeline.overdue)
        layOut()
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

    /// 表示範囲に入る将来回。「これから来る回」だけを出すので、過ぎた日の回と、今日の過ぎた時刻の回は除く。
    /// 終日の回には時刻が無いので、今日の分は残す。
    private func futureOccurrences(of recurring: [TimelineItem], in range: DateInterval) -> [TimelineItem] {
        let now = now()
        let start = max(range.start, calendar.startOfDay(for: now))
        guard start < range.end else { return [] }
        return VirtualOccurrences.expand(recurring, in: DateInterval(start: start, end: range.end), calendar: calendar)
            .filter { item in item.isAllDay || item.start.map { $0 > now } == true }
    }

    private func layOut() {
        let days = days
        columns = TimelineColumns.columns(for: timeline.timed, days: days, calendar: calendar)
        allDaySpans = TimelineColumns.allDaySpans(for: timeline.allDay, days: days, calendar: calendar)
        // 読み直しや表示範囲の変更で画面から消えた項目は、選択から外す
        cursorPosition = cursorPosition.flatMap(cursor.resolve)
    }
}
