import Foundation

/// 時間軸グリッド上の 1 項目の位置。分は表示日の 0:00 からの経過分。
public struct GridPlacement: Equatable, Identifiable {
    public var id: String { item.id }
    public let item: TimelineItem
    public let startMinute: Int
    public let endMinute: Int
    /// 重なりグループ内の列番号（0 始まり）と列数。横幅の分割に使う。
    public let column: Int
    public let columnCount: Int

    public var durationMinutes: Int { endMinute - startMinute }

    /// ドラッグで日の中に収めるときに使う長さ。実際の長さと、この日に見えている長さの短いほう。
    /// 実際の長さだけで収めると、日をまたぐ予定は掴んだだけで手前へ寄ってしまう。
    /// リマインダーは長さ 0 なので 1 分として扱い、23:45 にも置けるようにする。
    public var movableMinutes: Int {
        let real = item.start.flatMap { start in item.end.map { Int($0.timeIntervalSince(start) / 60) } } ?? 0
        return max(1, min(real, durationMinutes))
    }
}

/// 時刻付きの項目を 1 日の時間軸に配置する。重なる項目は横に並べる。
public enum DayGridLayout {
    /// - Parameters:
    ///   - items: 時刻付き（`start != nil`、終日でない）の項目
    ///   - range: 表示日の範囲。はみ出す部分は日の端で切る
    ///   - minimumMinutes: 短い項目でも読めるよう確保する最小の高さ（分）
    public static func place(
        _ items: [TimelineItem],
        in range: DateInterval,
        minimumMinutes: Int = 30
    ) -> [GridPlacement] {
        let dayMinutes = Int(range.duration / 60)
        let spans: [(item: TimelineItem, start: Int, end: Int)] = items.compactMap { item in
            guard let start = item.start else { return nil }
            let end = item.end ?? start
            let startMinute = Int((start.timeIntervalSince(range.start) / 60).rounded(.down))
            let endMinute = Int((end.timeIntervalSince(range.start) / 60).rounded(.up))
            // 表示日より前に終わった項目は載せない（0:00 に寄せると最小の高さで出てしまう）
            guard startMinute >= 0 || endMinute > 0 else { return nil }
            let clampedStart = max(0, min(dayMinutes, startMinute))
            let clampedEnd = max(clampedStart + minimumMinutes, min(dayMinutes, endMinute))
            guard clampedStart < dayMinutes else { return nil }
            return (item, clampedStart, min(dayMinutes, max(clampedEnd, clampedStart + 1)))
        }
        .sorted { a, b in
            if a.start != b.start { return a.start < b.start }
            if a.end != b.end { return a.end > b.end }
            return a.item.id < b.item.id
        }

        var result: [GridPlacement] = []
        // 時間的に連結した塊ごとに列を割り当てる。塊が切れたら列数を確定して書き出す。
        var cluster: [(span: (item: TimelineItem, start: Int, end: Int), column: Int)] = []
        var columnEnds: [Int] = []
        var clusterEnd = 0

        func flush() {
            let count = columnEnds.count
            for entry in cluster {
                result.append(GridPlacement(
                    item: entry.span.item,
                    startMinute: entry.span.start,
                    endMinute: entry.span.end,
                    column: entry.column,
                    columnCount: count
                ))
            }
            cluster.removeAll()
            columnEnds.removeAll()
        }

        for span in spans {
            if !cluster.isEmpty, span.start >= clusterEnd {
                flush()
            }
            let column = columnEnds.firstIndex { $0 <= span.start } ?? columnEnds.count
            if column == columnEnds.count {
                columnEnds.append(span.end)
            } else {
                columnEnds[column] = span.end
            }
            cluster.append((span, column))
            clusterEnd = max(clusterEnd, span.end)
        }
        flush()
        return result
    }
}
