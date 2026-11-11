import Foundation

/// キー操作で選択中の項目。同じ項目が複数の場所（期限切れ欄とその日の列、日をまたぐ予定の各日）に出るので、場所も持つ。
public struct TimelineSelection: Hashable, Sendable {
    public enum Place: Hashable, Sendable {
        case overdue
        case allDay
        /// 時間軸の列。`day` はその日の 0:00。
        case grid(day: Date)
    }

    public let itemID: String
    public let place: Place

    public init(itemID: String, place: Place) {
        self.itemID = itemID
        self.place = place
    }
}

/// 選択を上下左右へ動かしたときの行き先を決める。画面に出ている並びだけから導く。
/// 将来回の仮想項目は操作できないので、並びに入れない。
public struct TimelineCursor {
    /// 選択と、いまいる列の日。期限切れ欄と終日の帯は列に属さないので、上下に戻る先の列を別に覚える。
    public struct Position: Equatable, Sendable {
        public let selection: TimelineSelection
        public let day: Date

        public init(selection: TimelineSelection, day: Date) {
            self.selection = selection
            self.day = day
        }
    }

    public enum Edge: Sendable {
        case first
        case last
    }

    private let days: [Date]
    private let overdue: [TimelineItem]
    private let spans: [AllDaySpan]
    private let columns: [TimelineColumn]

    public init(days: [Date], overdue: [TimelineItem], allDaySpans: [AllDaySpan], columns: [TimelineColumn]) {
        self.days = days
        self.overdue = overdue.filter { !$0.isVirtual }
        // 帯は上の段から、同じ段なら左から
        spans = allDaySpans.filter { !$0.item.isVirtual }
            .sorted { ($0.lane, $0.firstColumn) < ($1.lane, $1.firstColumn) }
        self.columns = columns
    }

    /// その日の列の縦の並び。期限切れ → その日に掛かる終日 → 時刻順。
    public func entries(on day: Date) -> [TimelineSelection] {
        overdue.map { TimelineSelection(itemID: $0.id, place: .overdue) } + ownEntries(on: day)
    }

    public func item(for selection: TimelineSelection) -> TimelineItem? {
        switch selection.place {
        case .overdue:
            overdue.first { $0.id == selection.itemID }
        case .allDay:
            spans.first { $0.item.id == selection.itemID }?.item
        case .grid(let day):
            placement(selection.itemID, on: day)?.item
        }
    }

    /// 時刻付きの選択の、その列での開始分。隣の日で近い時刻の項目を探すのに使う。
    public func startMinute(of position: Position) -> Int? {
        guard case .grid(let day) = position.selection.place else { return nil }
        return placement(position.selection.itemID, on: day)?.startMinute
    }

    /// 何も選択していないところからの最初の選択。`preferred`（無ければ最初の日）の列の端を選ぶ。
    /// その列に何も無ければ、項目のある最初の日の列にする。
    public func start(on preferred: Date?, at edge: Edge) -> Position? {
        let preferred = preferred.flatMap { days.contains($0) ? $0 : nil } ?? days.first
        let candidates = [preferred].compactMap { $0 } + days
        for day in candidates {
            let entries = entries(on: day)
            if let selection = edge == .first ? entries.first : entries.last {
                return Position(selection: selection, day: day)
            }
        }
        return nil
    }

    /// 同じ列の中で上下へ。端なら nil。
    public func vertical(from position: Position, by step: Int) -> Position? {
        let entries = entries(on: position.day)
        guard let index = entries.firstIndex(of: position.selection),
              entries.indices.contains(index + step)
        else { return nil }
        return Position(selection: entries[index + step], day: position.day)
    }

    /// 隣の日の列へ。項目の無い日は飛ばす。その方向に項目のある日が無ければ nil。
    public func horizontal(from position: Position, by step: Int) -> Position? {
        guard let index = days.firstIndex(of: position.day) else { return nil }
        let minute = startMinute(of: position)
        let excluded = position.selection.place == .allDay ? position.selection.itemID : nil
        var next = index + step
        while days.indices.contains(next) {
            if let found = pick(on: days[next], nearMinute: minute, excludingAllDay: excluded) {
                return found
            }
            next += step
        }
        return nil
    }

    /// 前後の週へ移ったあとの選択。来た側の端に近い、項目のある日から選ぶ。
    public func enter(by step: Int, nearMinute minute: Int?) -> Position? {
        for day in step > 0 ? days : days.reversed() {
            if let found = pick(on: day, nearMinute: minute, excludingAllDay: nil) {
                return found
            }
        }
        return nil
    }

    /// 読み直しや表示範囲の変更のあとも選択が画面に残っているかを確かめる。残っていなければ nil。
    public func resolve(_ position: Position) -> Position? {
        guard days.contains(position.day), item(for: position.selection) != nil else { return nil }
        if position.selection.place == .allDay,
           let span = spans.first(where: { $0.item.id == position.selection.itemID }),
           !covers(span, position.day) {
            return Position(selection: position.selection, day: days[span.firstColumn])
        }
        return position
    }

    /// その日の列だけに属する並び（期限切れを除く）。
    private func ownEntries(on day: Date) -> [TimelineSelection] {
        allDayEntries(on: day) + gridPlacements(on: day).map {
            TimelineSelection(itemID: $0.item.id, place: .grid(day: day))
        }
    }

    private func allDayEntries(on day: Date) -> [TimelineSelection] {
        spans.filter { covers($0, day) }.map { TimelineSelection(itemID: $0.item.id, place: .allDay) }
    }

    private func covers(_ span: AllDaySpan, _ day: Date) -> Bool {
        guard let index = days.firstIndex(of: day) else { return false }
        return span.firstColumn <= index && index < span.firstColumn + span.columnSpan
    }

    /// 時刻順。同じ時刻なら左に並ぶほうを先にする。
    private func gridPlacements(on day: Date) -> [GridPlacement] {
        (columns.first { $0.day == day }?.placements ?? [])
            .filter { !$0.item.isVirtual }
            .sorted { a, b in
                if a.startMinute != b.startMinute { return a.startMinute < b.startMinute }
                if a.column != b.column { return a.column < b.column }
                return a.item.id < b.item.id
            }
    }

    private func placement(_ id: String, on day: Date) -> GridPlacement? {
        gridPlacements(on: day).first { $0.item.id == id }
    }

    /// 別の列から来たときに選ぶ項目。時刻付きから来たなら開始時刻の近い時刻付き、それ以外は列の先頭。
    private func pick(on day: Date, nearMinute minute: Int?, excludingAllDay excluded: String?) -> Position? {
        let placements = gridPlacements(on: day)
        if let minute,
           let nearest = placements.min(by: { abs($0.startMinute - minute) < abs($1.startMinute - minute) }) {
            return Position(selection: TimelineSelection(itemID: nearest.item.id, place: .grid(day: day)), day: day)
        }
        let allDay = allDayEntries(on: day).first { $0.itemID != excluded }
        let firstTimed = placements.first.map { TimelineSelection(itemID: $0.item.id, place: .grid(day: day)) }
        return (allDay ?? firstTimed).map { Position(selection: $0, day: day) }
    }
}
