import CoreGraphics
import Foundation

/// 0〜24 時を縦に並べる座標系。畳んだ区間（予定の無い早朝・深夜）は一定の高さの帯に潰す。
/// 分→y が非線形になるので、画面ではなくここで計算してテストする。
public struct DayGridAxis: Equatable {
    /// 畳める側。開始時刻より前と、終了時刻以降。
    public enum Edge: Hashable, Sendable {
        case early
        case late
    }

    public let hourHeight: CGFloat
    public let collapsedHeight: CGFloat
    /// 畳んだ区間（分）。昇順で重ならない。
    public let collapsed: [Range<Int>]

    public init(hourHeight: CGFloat, collapsedHeight: CGFloat, collapsed: [Range<Int>]) {
        self.hourHeight = hourHeight
        self.collapsedHeight = collapsedHeight
        self.collapsed = collapsed.filter { !$0.isEmpty }.sorted { $0.lowerBound < $1.lowerBound }
    }

    public var totalHeight: CGFloat { y(forMinute: 24 * 60) }

    /// その分の y。畳んだ区間の中なら帯の上端。
    public func y(forMinute minute: Int) -> CGFloat {
        var y: CGFloat = 0
        var cursor = 0
        for range in collapsed {
            if minute <= range.lowerBound { break }
            y += CGFloat(range.lowerBound - cursor) / 60 * hourHeight
            if minute < range.upperBound { return y }
            y += collapsedHeight
            cursor = range.upperBound
        }
        return y + CGFloat(minute - cursor) / 60 * hourHeight
    }

    public func height(fromMinute start: Int, to end: Int) -> CGFloat {
        y(forMinute: end) - y(forMinute: start)
    }

    /// 目盛りを描く時刻。畳んだ区間の中は描かない。
    public var visibleHours: [Int] {
        (0..<24).filter { hour in !isCollapsed(minute: hour * 60) }
    }

    public func isCollapsed(minute: Int) -> Bool {
        collapsed.contains { $0.contains(minute) }
    }

    public func bandFrame(for range: Range<Int>) -> (y: CGFloat, height: CGFloat) {
        (y(forMinute: range.lowerBound), collapsedHeight)
    }

    /// 開始時刻より前・終了時刻以降のうち、項目が 1 つも掛かっておらず、ユーザーが開いてもいない側を畳む。
    /// `nowMinute`（今日なら現在時刻）を含む側も畳まない。赤線が帯の上に乗ると時刻が読めないため。
    /// `endHour` が 24 なら深夜側は畳まない。開始 ≥ 終了のような設定なら何も畳まない。
    public static func collapsedRanges(
        placements: [GridPlacement],
        startHour: Int,
        endHour: Int,
        expanded: Set<Edge> = [],
        nowMinute: Int? = nil
    ) -> [Range<Int>] {
        guard (0...24).contains(startHour), (0...24).contains(endHour), startHour < endHour else { return [] }
        var result: [Range<Int>] = []
        let early = 0..<(startHour * 60)
        if !early.isEmpty, !expanded.contains(.early),
           !(nowMinute.map(early.contains) ?? false),
           !placements.contains(where: { $0.startMinute < early.upperBound }) {
            result.append(early)
        }
        let late = (endHour * 60)..<(24 * 60)
        if !late.isEmpty, !expanded.contains(.late),
           !(nowMinute.map(late.contains) ?? false),
           !placements.contains(where: { $0.endMinute > late.lowerBound }) {
            result.append(late)
        }
        return result
    }
}
