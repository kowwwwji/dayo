import DayoCore
import SwiftUI

/// 終日予定・期日のみのリマインダーを表す小さなチップ。グリッドの上に左から並べる。
/// 週表示では `fillsWidth` で日をまたぐ帯として使う。繰り返しリマインダーの将来回（仮想項目）は薄く描き、操作を受け付けない。
struct AllDayChip: View {
    let item: TimelineItem
    let editing: ItemEditing
    var fillsWidth = false
    let onToggle: () -> Void

    /// エディタを開く場所のキー。同じリマインダーが期限切れ欄にも出ることがあるので、そちらと区別する。
    private static let anchor = "allDay"

    private var color: Color { Color(cgColor: item.color) }

    var body: some View {
        HStack(spacing: 5) {
            switch item.kind {
            case .event:
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 3, height: 12)
            case .reminder:
                Button(action: onToggle) {
                    Image(systemName: item.isVirtual ? "circle.dotted" : item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(color)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isVirtual ? "今後の回" : item.isCompleted ? "未完了に戻す" : "完了にする")
            }
            PriorityMark(priority: item.priority)
                .font(.dayoTitle)
            Text(item.title)
                .font(.dayoTitle)
                .lineLimit(1)
                .strikethrough(item.isCompleted)
                .foregroundStyle(item.isCompleted ? .secondary : .primary)
            EarlyReminderMark(minutes: item.earlyReminderMinutes)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onEditGesture { editing.open(item, at: Self.anchor) }
        .itemEditor(for: item, editing, at: Self.anchor)
        .opacity(item.isVirtual ? 0.45 : 1)
        .allowsHitTesting(!item.isVirtual)
    }
}

/// 優先度の「!」。純正アプリと同じくアクセント色で、なしのときは何も出さない。
struct PriorityMark: View {
    let priority: ReminderPriority

    var body: some View {
        if priority != .none {
            Text(priority.marker)
                .fontWeight(.semibold)
                .foregroundStyle(.tint)
        }
    }
}

/// 左上から横に並べ、幅に収まらなければ次の行へ折り返す。
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let frames = layout(subviews: subviews, in: width)
        let height = frames.map(\.maxY).max() ?? 0
        let usedWidth = frames.map(\.maxX).max() ?? 0
        return CGSize(width: width.isFinite ? width : usedWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, layout(subviews: subviews, in: bounds.width)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func layout(subviews: Subviews, in width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}
