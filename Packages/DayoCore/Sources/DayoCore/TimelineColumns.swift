import Foundation

/// 時間軸グリッドの 1 日分の列。
public struct TimelineColumn: Equatable, Identifiable {
    public var id: Date { day }
    /// その日の 0:00。
    public let day: Date
    public let placements: [GridPlacement]
}

/// 終日欄の帯。複数日にまたがる項目は列をつないで 1 本にする。
public struct AllDaySpan: Equatable, Identifiable {
    public var id: String { item.id }
    public let item: TimelineItem
    /// 表示中の日の並びでの開始列（0 始まり）と、またぐ列数。表示範囲の外は切る。
    public let firstColumn: Int
    public let columnSpan: Int
    /// 帯どうしが重ならないよう割り当てた段（0 始まり）。
    public let lane: Int
}

/// 項目を「N 日分の列」に振り分ける。日表示は N=1、3 日表示は N=3、週表示は N=7。
public enum TimelineColumns {
    /// 時刻付きの項目を日ごとに配置する。日をまたぐ項目は各日に切って出す。
    /// - Parameter days: 表示する日（各日の 0:00）。昇順で連続していること
    public static func columns(for items: [TimelineItem], days: [Date], calendar: Calendar) -> [TimelineColumn] {
        let timed = items.filter { $0.start != nil && !$0.isAllDay }
        return days.map { day in
            guard let range = calendar.dateInterval(of: .day, for: day) else {
                return TimelineColumn(day: day, placements: [])
            }
            return TimelineColumn(day: day, placements: DayGridLayout.place(timed, in: range))
        }
    }

    /// 終日の項目を帯にする。左の列から、長いものを上の段に置く。
    public static func allDaySpans(for items: [TimelineItem], days: [Date], calendar: Calendar) -> [AllDaySpan] {
        let ranges: [(item: TimelineItem, columns: ClosedRange<Int>)] = items.compactMap { item in
            guard item.isAllDay, let start = item.start else { return nil }
            let firstDay = calendar.startOfDay(for: start)
            var end = max(item.end ?? start, start)
            // 終了を翌日 0:00 で持つ予定は、その日まで延びていない
            if end > start, end == calendar.startOfDay(for: end) { end = end.addingTimeInterval(-1) }
            let lastDay = calendar.startOfDay(for: end)
            guard let first = days.firstIndex(where: { $0 >= firstDay }),
                  let last = days.lastIndex(where: { $0 <= lastDay }),
                  first <= last
            else { return nil }
            return (item, first...last)
        }
        .sorted { a, b in
            if a.columns.lowerBound != b.columns.lowerBound { return a.columns.lowerBound < b.columns.lowerBound }
            if a.columns.count != b.columns.count { return a.columns.count > b.columns.count }
            if a.item.kind != b.item.kind { return a.item.kind == .event }
            if a.item.title != b.item.title { return a.item.title < b.item.title }
            return a.item.id < b.item.id
        }

        // 段ごとに、最後に使った列を覚えておく
        var laneEnds: [Int] = []
        return ranges.map { entry in
            let lane = laneEnds.firstIndex { $0 < entry.columns.lowerBound } ?? laneEnds.count
            if lane == laneEnds.count {
                laneEnds.append(entry.columns.upperBound)
            } else {
                laneEnds[lane] = entry.columns.upperBound
            }
            return AllDaySpan(
                item: entry.item,
                firstColumn: entry.columns.lowerBound,
                columnSpan: entry.columns.count,
                lane: lane
            )
        }
    }
}
