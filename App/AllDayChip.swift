import DayoCore
import SwiftUI

/// 終日予定・期日のみのリマインダーを表す小さなチップ。グリッドの上に左から並べる。
struct AllDayChip: View {
    let item: TimelineItem
    let editing: ItemEditing
    let onToggle: () -> Void

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
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(color)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isCompleted ? "未完了に戻す" : "完了にする")
            }
            PriorityMark(priority: item.priority)
                .font(.caption)
            Text(item.title)
                .font(.caption)
                .lineLimit(1)
                .strikethrough(item.isCompleted)
                .foregroundStyle(item.isCompleted ? .secondary : .primary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
        // チップ全体をタップで編集（チェックのボタンはボタンが先に取る）
        .contentShape(Rectangle())
        .onTapGesture { editing.open(item) }
        .itemEditor(for: item, editing)
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
