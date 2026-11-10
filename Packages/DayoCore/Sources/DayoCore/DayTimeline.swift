import Foundation

/// 1 日分の TimelineItem を画面のセクションに振り分けた結果。並び順もここで決める。
public struct DayTimeline: Equatable {
    /// 終日予定と期日のみのリマインダー。予定 → リマインダー、同種はタイトル順。
    public var allDay: [TimelineItem]
    /// 期限切れの未完了リマインダー。古いものから。
    public var overdue: [TimelineItem]
    /// 時刻付き。時刻順、同時刻は予定 → リマインダー → id。
    public var timed: [TimelineItem]

    /// 期日なし（`start == nil`）は時間軸に載せないため捨てる。
    public init(items: [TimelineItem], overdue: [TimelineItem]) {
        allDay = items.filter { $0.start != nil && $0.isAllDay }
            .sorted(by: Self.kindThenTitle)
        self.overdue = overdue.sorted(by: Self.startThenTieBreak)
        timed = items.filter { $0.start != nil && !$0.isAllDay }
            .sorted(by: Self.startThenTieBreak)
    }

    public var isEmpty: Bool {
        allDay.isEmpty && overdue.isEmpty && timed.isEmpty
    }

    private static func startThenTieBreak(_ a: TimelineItem, _ b: TimelineItem) -> Bool {
        switch (a.start, b.start) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return kindThenID(a, b)
        }
    }

    private static func kindThenTitle(_ a: TimelineItem, _ b: TimelineItem) -> Bool {
        if a.kind != b.kind { return a.kind == .event }
        return titleThenID(a, b)
    }

    private static func kindThenID(_ a: TimelineItem, _ b: TimelineItem) -> Bool {
        if a.kind != b.kind { return a.kind == .event }
        return a.id < b.id
    }

    private static func titleThenID(_ a: TimelineItem, _ b: TimelineItem) -> Bool {
        if a.title != b.title { return a.title < b.title }
        return a.id < b.id
    }
}
