import DayoCore
import SwiftUI

/// 終日予定・期日のみのリマインダーを表す小さなチップ。グリッドの上に左から並べる。
/// 列が複数の表示では `fillsWidth` で日をまたぐ帯として使う。繰り返しリマインダーの将来回（仮想項目）は薄く描き、操作を受け付けない。
struct AllDayChip: View {
    let item: TimelineItem
    let editing: ItemEditing
    var fillsWidth = false
    /// キー操作で選択中か
    var isSelected = false
    /// ドラッグの設定。nil なら動かせない。
    var drag: AllDayChipDrag?
    /// チップの上をダブルクリックした（Mac）。引数はチップの左端からの距離。帯のどの日を押したかを求めるのに使う
    var onDoubleClick: ((CGFloat) -> Void)?
    let onToggle: () -> Void

    /// `@GestureState` はジェスチャが中断されても自動で nil に戻る
    @GestureState private var dragValue: DragValue?

    private struct DragValue {
        let translation: CGSize
        let location: CGPoint
    }

    /// エディタを開く場所のキー。同じリマインダーが期限切れ欄にも出ることがあるので、そちらと区別する。
    private static let anchor = TimelineSelection.Place.allDay.editorAnchor

    /// チップ全体の座標空間。ダブルクリックの位置をチップの左端から測る
    private static let space = "allDayChip"

    private var color: Color { Color(cgColor: item.color) }

    var body: some View {
        HStack(spacing: 5) {
            switch item.kind {
            case .event:
                EmptyView()
            case .reminder:
                Button(action: onToggle) {
                    Image(systemName: item.isVirtual ? "circle.dotted" : item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(color)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isVirtual ? "今後の回" : item.isCompleted ? "未完了に戻す" : "完了にする")
            }
            // チェックの丸以外。ダブルクリックでの登録はここで受ける（丸の上では完了の切替が 2 回走るだけにする）
            HStack(spacing: 5) {
                if item.kind == .event {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color)
                        .frame(width: 3, height: 12)
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
            .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
            .contentShape(Rectangle())
            #if os(macOS)
            .simultaneousGesture(
                SpatialTapGesture(count: 2, coordinateSpace: .named(Self.space)).onEnded { onDoubleClick?($0.location.x) }
            )
            #endif
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
        .coordinateSpace(name: Self.space)
        .selectionRing(isSelected)
        .contentShape(Rectangle())
        .onEditGesture { editing.open(item, at: Self.anchor) }
        .itemEditor(for: item, editing, at: Self.anchor)
        .opacity(item.isVirtual ? 0.45 : opacityWhileDragging)
        .offset(x: shiftWhileDragging)
        .zIndex(dragValue == nil ? 0 : 1)
        #if os(macOS)
        .gesture(isDraggable ? moveGesture : nil)
        .onChange(of: dragValue == nil) { _, ended in
            if ended { drag?.board.ghost = nil }
        }
        #endif
        .allowsHitTesting(!item.isVirtual)
    }
}

extension AllDayChip {
    private var isDraggable: Bool { drag != nil && item.isEditable && !item.isVirtual }

    /// 時間軸の上にいる間は影のほうを見せるので、チップは薄くする。
    private var opacityWhileDragging: Double {
        guard let dragValue else { return 1 }
        return gridTarget(at: dragValue.location) == nil ? 0.85 : 0.3
    }

    /// 終日欄の中では日単位で横にずらして見せる。
    private var shiftWhileDragging: CGFloat {
        guard let dragValue, let drag, let dayWidth = drag.dayWidth, gridTarget(at: dragValue.location) == nil
        else { return 0 }
        return CGFloat(dayOffset(for: dragValue.translation, in: drag)) * dayWidth
    }

    private func gridTarget(at location: CGPoint) -> (day: Date, minute: Int)? {
        // 予定は時間軸に落とすと 1 時間になる。リマインダーは長さが無い
        drag?.board.gridTarget(at: location, duration: item.kind == .event ? 60 : 1)
    }

    private func dayOffset(for translation: CGSize, in drag: AllDayChipDrag) -> Int {
        guard let dayWidth = drag.dayWidth, dayWidth > 0 else { return 0 }
        let offset = Int((translation.width / dayWidth).rounded())
        return max(drag.dayOffsets.lowerBound, min(drag.dayOffsets.upperBound, offset))
    }

    #if os(macOS)
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(TimelineDragBoard.space))
            .updating($dragValue) { value, state, _ in
                state = DragValue(translation: value.translation, location: value.location)
            }
            .onChanged { value in
                drag?.board.ghost = gridTarget(at: value.location).map { target in
                    TimelineDragBoard.Ghost(
                        title: item.title, color: item.color, label: timeText(minute: target.minute),
                        location: value.location
                    )
                }
            }
            .onEnded { value in
                guard let drag else { return }
                drag.board.ghost = nil
                if let target = gridTarget(at: value.location) {
                    drag.onMakeTimed(target.day, target.minute)
                } else {
                    let offset = dayOffset(for: value.translation, in: drag)
                    if offset != 0 { drag.onMoveDays(offset) }
                }
            }
    }
    #endif
}

/// 終日のチップのドラッグ。終日欄の中では日単位で動かし、時間軸へ落とすと時刻付きにする。
struct AllDayChipDrag {
    let board: TimelineDragBoard
    /// 1 日分の幅。日表示のチップ並びでは nil（横には動かせない）
    var dayWidth: CGFloat?
    /// 表示中の日の中で動かせる日数の範囲
    var dayOffsets: ClosedRange<Int> = 0...0
    let onMoveDays: (Int) -> Void
    /// 落とした日（その日の 0:00）と開始分
    let onMakeTimed: (Date, Int) -> Void
}

/// 終日欄で新規登録中の仮のチップ。エディタはここから出す。入力中のタイトルと種別を映す。
/// その場所で新規登録を開いていなければ何も描かない。
struct NewItemChip: View {
    let editing: ItemEditing
    /// エディタを開く場所のキー
    let anchor: String
    /// 帯として幅を決めるとき。nil なら中身の幅
    var width: CGFloat?

    var body: some View {
        if editing.isOpenForNew(at: anchor) {
            let editor = editing.editor
            let title = editor?.title ?? ""
            Text(title.isEmpty ? (editor?.kind == .reminder ? "新規リマインダー" : "新規予定") : title)
                .font(.dayoTitle.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .frame(width: width, alignment: .leading)
                .background(.tint.opacity(0.25), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.tint, lineWidth: 1))
                .newItemEditor(editing, at: anchor)
        }
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
