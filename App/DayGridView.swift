import DayoCore
import SwiftUI

/// 0〜24 時の時間軸に予定とリマインダーを配置する。重なりは列に分けて横に並べる。
/// 設定した表示時間帯の外に何も無ければ、その時間帯は帯に畳む（クリックで開く）。
struct DayGridView: View {
    let placements: [GridPlacement]
    let day: Date
    let isToday: Bool
    /// 表示中の日の内容が読み込み済みか。帯の有無が確定してから初期位置へスクロールする
    let isLoaded: Bool
    let editing: ItemEditing
    let onToggle: (TimelineItem) -> Void
    /// ドラッグで落とした。開始分と、繰り返し予定ならどの回に及ぶか
    let onMove: (TimelineItem, Int, EditSpan) -> Void

    private let hourHeight: CGFloat = 56
    private let collapsedHeight: CGFloat = 22
    /// 時刻ラベルの列幅。上に固定する「終日」行のラベルも同じ幅にして揃える。
    static let labelWidth: CGFloat = 48
    private var labelWidth: CGFloat { Self.labelWidth }
    static let trailingInset: CGFloat = 12
    private var trailingInset: CGFloat { Self.trailingInset }

    @AppStorage(DayHours.startKey) private var startHour = DayHours.defaultStart
    @AppStorage(DayHours.endKey) private var endHour = DayHours.defaultEnd
    /// ユーザーが開いた側。日を変えたら畳み直す。
    @State private var expanded: Set<DayGridAxis.Edge> = []
    @State private var now = Date.now
    /// ドラッグ中の項目と移動量。項目側のジェスチャが中断されて 0 に戻れば nil になる
    @State private var dragging: Dragging?
    /// 繰り返し予定を落としたあと、範囲を聞いている間の保留。確定するまで落とした位置に置いたままにする
    @State private var pendingMove: PendingMove?
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private struct Dragging {
        let placement: GridPlacement
        let translation: CGFloat
    }

    private struct PendingMove: Identifiable {
        let item: TimelineItem
        let minute: Int
        var id: String { item.id }
    }

    private var axis: DayGridAxis {
        DayGridAxis(
            hourHeight: hourHeight,
            collapsedHeight: collapsedHeight,
            collapsed: DayGridAxis.collapsedRanges(
                placements: placements,
                startHour: startHour,
                endHour: endHour,
                expanded: expanded,
                nowMinute: isToday ? nowMinute : nil
            )
        )
    }

    var body: some View {
        let axis = self.axis
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    hourLines(axis)
                    bands(axis)
                    GeometryReader { geometry in
                        items(axis, availableWidth: geometry.size.width)
                    }
                    if isToday {
                        nowIndicator(axis)
                    }
                    dragTimeLabel(axis)
                }
                .frame(height: axis.totalHeight)
                .padding(.vertical, 8)
            }
            .onAppear {
                if isLoaded { scrollToStart(proxy, axis) }
            }
            .onChange(of: day) { _, _ in expanded = [] }
            // 日を変えた直後は前の日の内容で帯が決まっているので、読み込み完了を待ってから位置を合わせる
            .onChange(of: isLoaded) { _, loaded in
                if loaded { scrollToStart(proxy, self.axis) }
            }
            .onReceive(clock) { now = $0 }
            .confirmationDialog(
                "繰り返しの予定です",
                isPresented: Binding(get: { pendingMove != nil }, set: { if !$0 { pendingMove = nil } }),
                titleVisibility: .visible,
                presenting: pendingMove
            ) { move in
                Button("この回のみ") { onMove(move.item, move.minute, .thisOccurrence) }
                Button("以降すべて") { onMove(move.item, move.minute, .futureOccurrences) }
                Button("キャンセル", role: .cancel) {}
            } message: { _ in
                Text("どの回の時刻を変えますか？")
            }
        }
    }

    /// 落とし先の開始分。移動量を 15 分刻みに丸め、実際の長さで日の中・帯の外に収める
    /// （表示上の最小の高さではなく実際の長さを使う。リマインダーは長さ 0 なので 23:45 にも置ける）。
    private func dropMinute(for placement: GridPlacement, translation: CGFloat, axis: DayGridAxis) -> Int {
        let item = placement.item
        let realDuration = item.start.flatMap { start in item.end.map { Int($0.timeIntervalSince(start) / 60) } } ?? 0
        return axis.moveTarget(startMinute: placement.startMinute, duration: max(1, realDuration), translation: translation)
    }

    private func requestMove(_ placement: GridPlacement, to minute: Int) {
        guard minute != placement.startMinute else { return }
        let item = placement.item
        if item.kind == .event, item.hasRecurrence {
            pendingMove = PendingMove(item: item, minute: minute)
        } else {
            onMove(item, minute, .thisOccurrence)
        }
    }

    /// ドラッグ中・確認待ちの項目を本来の位置からずらす量。
    private func dragOffset(for placement: GridPlacement, axis: DayGridAxis) -> CGFloat {
        if let dragging, dragging.placement.id == placement.id {
            return dragging.translation
        }
        if let pendingMove, pendingMove.id == placement.id {
            return axis.y(forMinute: pendingMove.minute) - axis.y(forMinute: placement.startMinute)
        }
        return 0
    }

    /// ドラッグ中の落とし先の時刻。目盛りの列に、ブロックの上端と揃えて出す。
    private func dragTimeLabel(_ axis: DayGridAxis) -> some View {
        Group {
            if let dragging {
                let minute = dropMinute(for: dragging.placement, translation: dragging.translation, axis: axis)
                Text(Self.timeText(minute: minute))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: labelWidth - 6, alignment: .trailing)
                    .padding(.vertical, 1)
                    .background(.background)
                    .offset(y: axis.y(forMinute: dragging.placement.startMinute) + dragging.translation - 7)
            }
        }
        .allowsHitTesting(false)
    }

    private static func timeText(minute: Int) -> String {
        String(format: "%d:%02d", minute / 60, minute % 60)
    }

    private func hourLines(_ axis: DayGridAxis) -> some View {
        ForEach(axis.visibleHours, id: \.self) { hour in
            HStack(alignment: .center, spacing: 6) {
                Text(DayHours.label(hour))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: labelWidth - 6, alignment: .trailing)
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 1)
            }
            .frame(height: 12)
            .offset(y: axis.y(forMinute: hour * 60) - 6)
            .id(Self.hourID(hour))
        }
    }

    /// 畳んだ時間帯。クリックで開く。
    private func bands(_ axis: DayGridAxis) -> some View {
        ForEach(axis.collapsed, id: \.lowerBound) { range in
            let frame = axis.bandFrame(for: range)
            HStack(spacing: 6) {
                Text("\(DayHours.label(range.lowerBound / 60)) 〜 \(DayHours.label(range.upperBound / 60))")
                    .font(.caption2.monospacedDigit())
                Text("予定なし")
                    .font(.caption2)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: frame.height)
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.5))
            .contentShape(Rectangle())
            .onTapGesture { expanded.insert(range.lowerBound == 0 ? .early : .late) }
            .offset(y: frame.y)
            .id(Self.bandID(range))
        }
    }

    private func items(_ axis: DayGridAxis, availableWidth: CGFloat) -> some View {
        let gridWidth = max(0, availableWidth - labelWidth - trailingInset)
        return ForEach(placements) { placement in
            let columnWidth = gridWidth / CGFloat(max(1, placement.columnCount))
            let lifted = dragOffset(for: placement, axis: axis)
            GridItemView(
                placement: placement,
                editing: editing,
                onToggle: { onToggle(placement.item) },
                onDragChanged: { translation in
                    dragging = translation == 0 ? nil : Dragging(placement: placement, translation: translation)
                },
                onDragEnded: { translation in
                    dragging = nil
                    requestMove(placement, to: dropMinute(for: placement, translation: translation, axis: axis))
                }
            )
                .frame(
                    width: max(0, columnWidth - 2),
                    height: max(18, axis.height(fromMinute: placement.startMinute, to: placement.endMinute) - 1),
                    alignment: .topLeading
                )
                .opacity(lifted == 0 ? 1 : 0.85)
                .zIndex(lifted == 0 ? 0 : 1)
                .offset(
                    x: labelWidth + columnWidth * CGFloat(placement.column),
                    y: axis.y(forMinute: placement.startMinute) + lifted
                )
        }
    }

    private var nowMinute: Int {
        let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: now)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    /// 現在時刻の赤線。現在時刻を含む側は畳まないので、常に目盛りの上に出る。
    private func nowIndicator(_ axis: DayGridAxis) -> some View {
        let minute = nowMinute
        return HStack(spacing: 0) {
            Circle().fill(.red).frame(width: 7, height: 7)
            Rectangle().fill(.red).frame(height: 1)
        }
        .padding(.leading, labelWidth - 4)
        .offset(y: axis.y(forMinute: minute) - 3.5)
        .allowsHitTesting(false)
    }

    /// 今日は現在時刻の 1 時間前、他の日は一日の開始（畳まれていればその帯）が上端に来るようにする。
    private func scrollToStart(_ proxy: ScrollViewProxy, _ axis: DayGridAxis) {
        let targetHour = isToday
            ? max(0, Calendar.autoupdatingCurrent.component(.hour, from: now) - 1)
            : startHour
        if let band = axis.collapsed.first(where: { $0.contains(targetHour * 60) }) {
            proxy.scrollTo(Self.bandID(band), anchor: .top)
        } else {
            proxy.scrollTo(Self.hourID(targetHour), anchor: .top)
        }
    }

    private static func hourID(_ hour: Int) -> String { "hour-\(hour)" }
    private static func bandID(_ range: Range<Int>) -> String { "band-\(range.lowerBound)" }
}

/// グリッド上の 1 項目。予定はカレンダー色のブロック、リマインダーはチェック付きの行。
/// 上下にドラッグすると時刻を変える（Mac はそのまま、iPhone は長押ししてから）。
/// 位置のずらしとラベルは親が描く。ここは移動量を通知するだけ。
private struct GridItemView: View {
    let placement: GridPlacement
    let editing: ItemEditing
    let onToggle: () -> Void
    /// 移動量（pt）。ジェスチャが中断されると 0 で呼ばれる
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat) -> Void

    /// `@GestureState` はジェスチャが中断（スクロール開始・ウィンドウ切替）されても自動で 0 に戻る
    @GestureState private var translation: CGFloat = 0

    private var item: TimelineItem { placement.item }
    private var color: Color { Color(cgColor: item.color) }

    var body: some View {
        content
            .gesture(item.isEditable ? moveGesture : nil)
            .onChange(of: translation) { _, new in onDragChanged(new) }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .event:
            HStack(alignment: .top, spacing: 0) {
                Rectangle().fill(color).frame(width: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(placement.durationMinutes >= 60 ? 2 : 1)
                    if placement.durationMinutes >= 45, let start = item.start, let end = item.end {
                        Text("\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .onTapGesture { editing.open(item) }
            .itemEditor(for: item, editing)
        case .reminder:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button(action: onToggle) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(color)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isCompleted ? "未完了に戻す" : "完了にする")
                HStack(spacing: 4) {
                    PriorityMark(priority: item.priority)
                        .font(.caption)
                    Text(item.title)
                        .font(.caption)
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture { editing.open(item) }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            .itemEditor(for: item, editing)
        }
    }

    // MARK: - ドラッグ

    #if os(iOS)
    /// スクロールと競合しないよう、長押ししてからドラッグ
    private var moveGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($translation) { value, state, _ in
                if case .second(true, let drag?) = value {
                    state = drag.translation.height
                }
            }
            .onEnded { value in
                if case .second(true, let drag?) = value {
                    onDragEnded(drag.translation.height)
                }
            }
    }
    #else
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($translation) { value, state, _ in state = value.translation.height }
            .onEnded { value in onDragEnded(value.translation.height) }
    }
    #endif
}
