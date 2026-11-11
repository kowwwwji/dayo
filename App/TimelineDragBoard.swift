import DayoCore
import Observation
import SwiftUI

/// 終日欄と時間軸をまたぐドラッグの橋渡し。
/// 終日欄と時間軸は別々のビュー（時間軸はスクロールする）なので、互いの位置をここに届け出ておき、
/// ドラッグ中の位置がどちらのどこに当たるかをここで求める。位置はすべて `space` の座標。
@MainActor
@Observable
final class TimelineDragBoard {
    /// 終日欄と時間軸を含むビューに付ける座標空間の名前。
    static let space = "timeline"

    /// もう一方の領域へ持っていく途中の項目。元のビューは自分の領域で切り取られて見えなくなるので、代わりにこれを描く。
    struct Ghost: Equatable {
        let title: String
        let color: CGColor
        /// 落としたらどうなるか（「10:15」「終日」）
        let label: String
        let location: CGPoint
    }

    var ghost: Ghost?

    // 位置の届け出はドラッグのたびに読むだけで、画面の描き直しには関わらせない
    @ObservationIgnored var gridContentFrame: CGRect = .zero
    @ObservationIgnored var gridVisibleFrame: CGRect = .zero
    @ObservationIgnored var axis: DayGridAxis?
    @ObservationIgnored var days: [Date] = []
    /// 終日欄のうち、日の列が並ぶ範囲（列が複数の表示は曜日の行も含む見出し全体）。
    @ObservationIgnored var allDayFrame: CGRect?

    /// 時間軸の上なら、その位置の日と開始分（15 分刻み。`duration` 分が日の中・帯の外に収まるよう寄せる）。
    func gridTarget(at point: CGPoint, duration: Int) -> (day: Date, minute: Int)? {
        guard let axis, gridVisibleFrame.contains(point), !days.isEmpty else { return nil }
        let dayWidth = DayGridView.dayWidth(totalWidth: gridContentFrame.width, dayCount: days.count)
        let x = point.x - gridContentFrame.minX - DayGridView.labelWidth
        guard dayWidth > 0, x >= 0 else { return nil }
        let index = Int(x / dayWidth)
        guard days.indices.contains(index) else { return nil }
        let minute = axis.clampedStart(minute: axis.minute(forY: point.y - gridContentFrame.minY), duration: duration)
        return (days[index], minute)
    }

    /// 終日欄の上なら、その位置の日。
    func allDayTarget(at point: CGPoint) -> Date? {
        guard let allDayFrame, allDayFrame.contains(point), !days.isEmpty else { return nil }
        let index = Int((point.x - allDayFrame.minX) / (allDayFrame.width / CGFloat(days.count)))
        return days.indices.contains(index) ? days[index] : nil
    }
}

extension View {
    /// このビューの位置（`TimelineDragBoard.space` の座標）を届ける。スクロールで動いたときも届く。
    func onFrameChange(perform action: @escaping (CGRect) -> Void) -> some View {
        background {
            GeometryReader { geometry in
                let frame = geometry.frame(in: .named(TimelineDragBoard.space))
                Color.clear
                    .onAppear { action(frame) }
                    .onChange(of: frame) { _, new in action(new) }
            }
        }
    }
}

/// ドラッグ中の項目の影。カーソルの少し右下に出す。
struct DragGhostView: View {
    let board: TimelineDragBoard

    var body: some View {
        if let ghost = board.ghost {
            HStack(spacing: 6) {
                Text(ghost.label)
                    .font(.dayoDetail.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.tint)
                Text(ghost.title)
                    .font(.dayoTitle)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.background, in: RoundedRectangle(cornerRadius: 5))
            .background(Color(cgColor: ghost.color).opacity(0.3), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(cgColor: ghost.color), lineWidth: 1))
            .fixedSize()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .offset(x: ghost.location.x + 10, y: ghost.location.y + 6)
            .allowsHitTesting(false)
        }
    }
}

/// 分を「10:15」の形にする。
func timeText(minute: Int) -> String {
    String(format: "%d:%02d", minute / 60, minute % 60)
}
