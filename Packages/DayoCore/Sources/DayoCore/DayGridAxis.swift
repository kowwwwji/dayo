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

    /// `y(forMinute:)` の逆。帯の中なら帯の開始分。範囲外は 0〜1440 に収める。
    public func minute(forY y: CGFloat) -> Int {
        var currentY: CGFloat = 0
        var cursor = 0
        for range in collapsed {
            let linearHeight = CGFloat(range.lowerBound - cursor) / 60 * hourHeight
            if y < currentY + linearHeight {
                return max(0, cursor + Int(((y - currentY) / hourHeight * 60).rounded()))
            }
            currentY += linearHeight
            if y < currentY + collapsedHeight { return range.lowerBound }
            currentY += collapsedHeight
            cursor = range.upperBound
        }
        let minute = cursor + Int(((y - currentY) / hourHeight * 60).rounded())
        return max(0, min(24 * 60, minute))
    }

    /// ドラッグの落とし先。移動量を `step` 分刻みに丸めるので、9:10 の予定は 9:25、9:40 と元の分を保って動き、
    /// 元の位置の近くで離せば動かない。日の中に収め、畳んだ帯に掛からないよう寄せる。
    public func moveTarget(startMinute: Int, duration: Int, translation: CGFloat, step: Int = 15) -> Int {
        let originY = y(forMinute: startMinute)
        let delta = minute(forY: originY + translation) - minute(forY: originY)
        let snapped = Int((Double(delta) / Double(step)).rounded()) * step
        return clampedStart(minute: startMinute + snapped, duration: duration, step: 1)
    }

    /// ドロップ位置を項目の開始分に直す。`step` 分に丸め、日の中に収め、
    /// 畳んだ帯に掛からないよう寄せる（帯に落ちた項目は見えなくなるため）。
    public func clampedStart(minute: Int, duration: Int, step: Int = 15) -> Int {
        let dayEnd = 24 * 60
        let length = max(1, min(duration, dayEnd))
        var start = Int((Double(minute) / Double(step)).rounded()) * step
        start = max(0, min(dayEnd - length, start))
        for range in collapsed where start < range.upperBound && start + length > range.lowerBound {
            start = range.lowerBound == 0 ? range.upperBound : range.lowerBound - length
        }
        return max(0, min(dayEnd - length, start))
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
