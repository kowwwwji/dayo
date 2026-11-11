import DayoCore
import SwiftUI

/// ドラッグで落とした先。`originDay` は掴んだ列の日（日をまたぐ予定は列ごとに切れ端が出る）。
struct GridMove {
    let item: TimelineItem
    let originDay: Date
    let targetDay: Date
    let minute: Int
}

/// 0〜24 時の時間軸に予定とリマインダーを配置する。日ごとの列を横に並べ（日表示は 1 列）、時刻目盛りは左に 1 本だけ描く。
/// 重なりは列の中でさらに分けて横に並べる。
/// 設定した表示時間帯の外に何も無ければ、その時間帯は帯に畳む（クリックで開く）。
struct DayGridView: View {
    let columns: [TimelineColumn]
    /// キー操作で選択中の項目
    var selection: TimelineSelection?
    /// 表示中の範囲の内容が読み込み済みか。帯の有無が確定してから初期位置へスクロールする
    let isLoaded: Bool
    let editing: ItemEditing
    let board: TimelineDragBoard
    let onToggle: (TimelineItem) -> Void
    /// ドラッグで落とした。繰り返し予定ならどの回に及ぶかも渡す
    let onMove: (GridMove, EditSpan) -> Void
    /// 終日欄へ落とした。その日の終日にする
    let onMakeAllDay: (TimelineItem, Date) -> Void

    private let hourHeight: CGFloat = 56
    private let collapsedHeight: CGFloat = 22
    /// 時刻ラベルの列幅。上に固定する「終日」行のラベルも同じ幅にして揃える。
    static let labelWidth: CGFloat = 48
    private var labelWidth: CGFloat { Self.labelWidth }
    static let trailingInset: CGFloat = 12
    private var trailingInset: CGFloat { Self.trailingInset }

    /// 1 日分の列幅。上に固定する週の見出しも同じ式で揃える。
    static func dayWidth(totalWidth: CGFloat, dayCount: Int) -> CGFloat {
        max(0, totalWidth - labelWidth - trailingInset) / CGFloat(max(1, dayCount))
    }

    @AppStorage(DayHours.startKey) private var startHour = DayHours.defaultStart
    @AppStorage(DayHours.endKey) private var endHour = DayHours.defaultEnd
    /// ユーザーが開いた側。表示する日を変えたら畳み直す。
    @State private var expanded: Set<DayGridAxis.Edge> = []
    @State private var now = Date.now
    /// 繰り返し予定を落としたあと、範囲を聞いている間の保留。確定するまで落とした位置に置いたままにする
    @State private var pendingMove: GridMove?
    /// ダブルクリックで新規登録を開いた場所。エディタを閉じるまで、そこに仮の項目を置く
    @State private var newSlot: NewSlot?
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private struct NewSlot {
        let day: Date
        let minute: Int
    }

    /// 新規登録のエディタを開く場所のキー。
    private static let newItemAnchor = "grid-new"

    private var days: [Date] { columns.map(\.day) }

    /// 今日の列。表示範囲に今日が無ければ nil。
    private var todayIndex: Int? {
        days.firstIndex { Calendar.autoupdatingCurrent.isDate($0, inSameDayAs: now) }
    }

    private var axis: DayGridAxis {
        DayGridAxis(
            hourHeight: hourHeight,
            collapsedHeight: collapsedHeight,
            // 全列をまとめて渡し、どの日にも何も無い時間帯だけを畳む（軸は全列で 1 本）
            collapsed: DayGridAxis.collapsedRanges(
                placements: columns.flatMap(\.placements),
                startHour: startHour,
                endHour: endHour,
                expanded: expanded,
                nowMinute: todayIndex != nil ? nowMinute : nil
            )
        )
    }

    var body: some View {
        let axis = self.axis
        // 終日欄から落とされた位置を日と時刻に直せるよう、いまの軸と日の並びを届けておく
        let _ = (board.axis, board.days) = (axis, days)
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    scrollAnchors(axis)
                    selectionAnchor(axis)
                    hourLines(axis)
                    daySeparators
                    GeometryReader { geometry in
                        let dayWidth = Self.dayWidth(totalWidth: geometry.size.width, dayCount: columns.count)
                        ZStack(alignment: .topLeading) {
                            #if os(macOS)
                            newItemSurface(axis, dayWidth: dayWidth)
                            #endif
                            items(axis, dayWidth: dayWidth)
                            newItemPlaceholder(axis, dayWidth: dayWidth)
                            if let todayIndex {
                                nowIndicator(axis, dayIndex: todayIndex, dayWidth: dayWidth, totalWidth: geometry.size.width)
                            }
                        }
                    }
                    // 帯は登録用の面より上に置く。下だとダブルクリックの判定に取られて、クリックで開けなくなる
                    bands(axis)
                }
                .frame(height: axis.totalHeight, alignment: .top)
                .onFrameChange { board.gridContentFrame = $0 }
                .padding(.vertical, 8)
            }
            .onFrameChange { board.gridVisibleFrame = $0 }
            .onAppear {
                if isLoaded { scrollToStart(proxy) }
            }
            .onChange(of: days) { _, _ in
                expanded = []
                newSlot = nil
            }
            // 日を変えた直後は前の日の内容で帯が決まっているので、読み込み完了を待ってから位置を合わせる
            .onChange(of: isLoaded) { _, loaded in
                if loaded { scrollToStart(proxy) }
            }
            .onReceive(clock) { now = $0 }
            // 選択した項目が画面の外なら、見えるところまでだけ動かす
            .onChange(of: selection) { _, _ in
                if selectedPlacement != nil { proxy.scrollTo(Self.selectionID) }
            }
            .confirmationDialog(
                "繰り返しの予定です",
                isPresented: Binding(get: { pendingMove != nil }, set: { if !$0 { pendingMove = nil } }),
                titleVisibility: .visible,
                presenting: pendingMove
            ) { move in
                Button("この回のみ") { onMove(move, .thisOccurrence) }
                Button("以降すべて") { onMove(move, .futureOccurrences) }
                Button("キャンセル", role: .cancel) {}
            } message: { _ in
                Text("どの回の日時を変えますか？")
            }
        }
    }

    /// 落とし先。縦は移動量を 15 分刻みに丸め、日の中・帯の外に収める（収める長さは `movableMinutes`）。
    /// 横は列単位で、表示中の日の外へは出さない。
    private func dropTarget(
        for placement: GridPlacement, dayIndex: Int, translation: CGSize, axis: DayGridAxis, dayWidth: CGFloat
    ) -> GridDropTarget {
        let minute = axis.moveTarget(
            startMinute: placement.startMinute, duration: placement.movableMinutes, translation: translation.height
        )
        let shift = dayWidth > 0 ? Int((translation.width / dayWidth).rounded()) : 0
        let targetIndex = max(0, min(columns.count - 1, dayIndex + shift))
        return GridDropTarget(dayOffset: targetIndex - dayIndex, minute: minute)
    }

    private func requestMove(_ placement: GridPlacement, from dayIndex: Int, to target: GridDropTarget) {
        guard target.minute != placement.startMinute || target.dayOffset != 0,
              columns.indices.contains(dayIndex + target.dayOffset)
        else { return }
        let item = placement.item
        let move = GridMove(
            item: item,
            originDay: columns[dayIndex].day,
            targetDay: columns[dayIndex + target.dayOffset].day,
            minute: target.minute
        )
        if item.kind == .event, item.hasRecurrence {
            pendingMove = move
        } else {
            onMove(move, .thisOccurrence)
        }
    }

    /// 確認待ちの項目を落とした位置に置いておくためのずらし量。
    private func pendingOffset(
        for placement: GridPlacement, dayIndex: Int, axis: DayGridAxis, dayWidth: CGFloat
    ) -> CGSize {
        guard let pendingMove, pendingMove.item.id == placement.id, pendingMove.originDay == columns[dayIndex].day,
              let targetIndex = days.firstIndex(of: pendingMove.targetDay)
        else { return .zero }
        return CGSize(
            width: CGFloat(targetIndex - dayIndex) * dayWidth,
            height: axis.y(forMinute: pendingMove.minute) - axis.y(forMinute: placement.startMinute)
        )
    }

    private func hourLines(_ axis: DayGridAxis) -> some View {
        ForEach(axis.visibleHours, id: \.self) { hour in
            HStack(alignment: .center, spacing: 6) {
                Text(DayHours.label(hour))
                    .font(.dayoDetail.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: labelWidth - 6, alignment: .trailing)
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 1)
            }
            .frame(height: 12)
            .offset(y: axis.y(forMinute: hour * 60) - 6)
        }
    }

    /// 初期スクロールの行き先。目盛りや帯は `offset` で置いていて配置上の位置を持たないので、
    /// 時刻ごとに位置を持つ透明な線を別に置く。畳んだ時間帯の時刻は帯の上端になる。
    private func scrollAnchors(_ axis: DayGridAxis) -> some View {
        ForEach(0..<24, id: \.self) { hour in
            Color.clear
                .frame(height: 1)
                .alignmentGuide(.top) { _ in -axis.y(forMinute: hour * 60) }
                .id(Self.hourID(hour))
        }
    }

    /// 選択中の項目の配置。グリッドにあるものだけ。
    private var selectedPlacement: GridPlacement? {
        guard let selection, case .grid(let day) = selection.place else { return nil }
        return columns.first { $0.day == day }?.placements.first { $0.id == selection.itemID }
    }

    /// 選択へスクロールするときの行き先。項目も `offset` で置いているので、同じ位置と高さの目印を別に置く。
    @ViewBuilder
    private func selectionAnchor(_ axis: DayGridAxis) -> some View {
        if let placement = selectedPlacement {
            Color.clear
                .frame(height: max(18, axis.height(fromMinute: placement.startMinute, to: placement.endMinute)))
                .alignmentGuide(.top) { _ in -axis.y(forMinute: placement.startMinute) }
                .id(Self.selectionID)
                .allowsHitTesting(false)
        }
    }

    /// 空いている時間のダブルクリックを受ける面。項目より下に置くので、項目の上では反応しない。
    private func newItemSurface(_ axis: DayGridAxis, dayWidth: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture(count: 2).onEnded { value in
                let x = value.location.x - labelWidth
                guard dayWidth > 0, x >= 0 else { return }
                let dayIndex = Int(x / dayWidth)
                guard columns.indices.contains(dayIndex) else { return }
                // 押した位置を含む 15 分の枠から始める。予定の既定の長さ（1 時間）が日の中・帯の外に収まるよう寄せる
                let minute = axis.clampedStart(minute: axis.minute(forY: value.location.y) / 15 * 15, duration: 60)
                let day = columns[dayIndex].day
                guard let start = Calendar.autoupdatingCurrent.date(byAdding: .minute, value: minute, to: day) else { return }
                newSlot = NewSlot(day: day, minute: minute)
                editing.openNew(at: start, isAllDay: false, anchor: Self.newItemAnchor)
            })
    }

    /// 新規登録中の仮の項目。エディタはここから出す。入力中のタイトルと種別を映す。
    @ViewBuilder
    private func newItemPlaceholder(_ axis: DayGridAxis, dayWidth: CGFloat) -> some View {
        if let newSlot, editing.isOpenForNew(at: Self.newItemAnchor), let dayIndex = days.firstIndex(of: newSlot.day) {
            let editor = editing.editor
            let isEvent = editor?.kind != .reminder
            let title = editor?.title ?? ""
            Text(title.isEmpty ? (isEvent ? "新規予定" : "新規リマインダー") : title)
                .font(.dayoTitle.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(
                    width: max(0, dayWidth - (columns.count > 1 ? 5 : 2)),
                    height: axis.height(fromMinute: newSlot.minute, to: min(24 * 60, newSlot.minute + (isEvent ? 60 : 30))) - 1,
                    alignment: .topLeading
                )
                .background(.tint.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.tint, lineWidth: 1))
                .newItemEditor(editing, at: Self.newItemAnchor)
                .offset(x: labelWidth + dayWidth * CGFloat(dayIndex), y: axis.y(forMinute: newSlot.minute))
                .zIndex(2)
        }
    }

    /// 日の区切り線。1 列なら描かない。
    private var daySeparators: some View {
        HStack(spacing: 0) {
            ForEach(columns.indices, id: \.self) { index in
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .leading) {
                        if index > 0 {
                            Rectangle().fill(.quaternary).frame(width: 1)
                        }
                    }
            }
        }
        .padding(.leading, labelWidth)
        .padding(.trailing, trailingInset)
        .allowsHitTesting(false)
    }

    /// 畳んだ時間帯。クリックで開く。
    private func bands(_ axis: DayGridAxis) -> some View {
        ForEach(axis.collapsed, id: \.lowerBound) { range in
            let frame = axis.bandFrame(for: range)
            HStack(spacing: 6) {
                Text("\(DayHours.label(range.lowerBound / 60)) 〜 \(DayHours.label(range.upperBound / 60))")
                    .font(.dayoDetail.monospacedDigit())
                Text("予定なし")
                    .font(.dayoDetail)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.dayoDetail)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: frame.height)
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.5))
            .contentShape(Rectangle())
            .onTapGesture { expanded.insert(range.lowerBound == 0 ? .early : .late) }
            .offset(y: frame.y)
        }
    }

    private func items(_ axis: DayGridAxis, dayWidth: CGFloat) -> some View {
        // 複数列のときは隣の日の項目とくっつかないよう、列の右に少し隙間を空ける
        let contentWidth = max(0, dayWidth - (columns.count > 1 ? 3 : 0))
        return ForEach(Array(columns.enumerated()), id: \.element.id) { dayIndex, column in
            ForEach(column.placements) { placement in
                let columnWidth = contentWidth / CGFloat(max(1, placement.columnCount))
                let x = labelWidth + dayWidth * CGFloat(dayIndex) + columnWidth * CGFloat(placement.column)
                let pending = pendingOffset(for: placement, dayIndex: dayIndex, axis: axis, dayWidth: dayWidth)
                GridItemView(
                    placement: placement,
                    anchor: Self.anchor(for: column.day),
                    isSelected: selection == TimelineSelection(itemID: placement.id, place: .grid(day: column.day)),
                    editing: editing,
                    labelColumnWidth: labelWidth - 6,
                    distanceToGridLeft: x,
                    dayWidth: dayWidth,
                    board: board,
                    onToggle: { onToggle(placement.item) },
                    dropTarget: { translation in
                        dropTarget(
                            for: placement, dayIndex: dayIndex, translation: translation, axis: axis, dayWidth: dayWidth
                        )
                    },
                    onDrop: { target in requestMove(placement, from: dayIndex, to: target) },
                    onDropAllDay: { day in onMakeAllDay(placement.item, day) }
                )
                .frame(
                    width: max(0, columnWidth - 2),
                    height: max(18, axis.height(fromMinute: placement.startMinute, to: placement.endMinute) - 1),
                    alignment: .topLeading
                )
                .opacity(pending == .zero ? 1 : 0.85)
                .zIndex(pending == .zero ? 0 : 1)
                .offset(x: x + pending.width, y: axis.y(forMinute: placement.startMinute) + pending.height)
            }
        }
    }

    private var nowMinute: Int {
        let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: now)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    /// 現在時刻の赤線。今日の列に引く。現在時刻を含む側は畳まないので、常に目盛りの上に出る。
    private func nowIndicator(_ axis: DayGridAxis, dayIndex: Int, dayWidth: CGFloat, totalWidth: CGFloat) -> some View {
        let x = labelWidth - 4 + dayWidth * CGFloat(dayIndex)
        return HStack(spacing: 0) {
            Circle().fill(.red).frame(width: 7, height: 7)
            Rectangle().fill(.red).frame(height: 1)
        }
        // 1 列なら右端まで、複数列なら今日の列の幅だけ
        .frame(width: columns.count > 1 ? dayWidth + 4 : max(0, totalWidth - x))
        .offset(x: x, y: axis.y(forMinute: nowMinute) - 3.5)
        .allowsHitTesting(false)
    }

    /// 今日を含むなら現在時刻の 1 時間前、含まなければ一日の開始（畳まれていればその帯）が上端に来るようにする。
    private func scrollToStart(_ proxy: ScrollViewProxy) {
        let targetHour = todayIndex != nil
            ? max(0, Calendar.autoupdatingCurrent.component(.hour, from: now) - 1)
            : startHour
        proxy.scrollTo(Self.hourID(targetHour), anchor: .top)
    }

    /// エディタを開いた場所のキー。日をまたぐ予定は複数の列に出るので、列の日で区別する。
    private static func anchor(for day: Date) -> String { TimelineSelection.Place.grid(day: day).editorAnchor }
    private static func hourID(_ hour: Int) -> String { "hour-\(hour)" }
    private static let selectionID = "selection"
}

/// ドラッグの落とし先。`dayOffset` は掴んだ列から何列動かすか。
private struct GridDropTarget {
    let dayOffset: Int
    let minute: Int
}

/// グリッド上の 1 項目。予定はカレンダー色のブロック、リマインダーはチェック付きの行。
/// ドラッグすると時刻と日を変える（Mac はそのまま、iPhone は長押ししてから）。縦は自由に、横は列単位で動く。
/// ドラッグ中のずらしと時刻ラベルはこの中で描く。親の状態を毎フレーム更新するとグリッド全体が描き直されてちらつくため。
/// 繰り返しリマインダーの将来回（仮想項目）は薄く描き、操作を受け付けない。
private struct GridItemView: View {
    let placement: GridPlacement
    /// エディタを開く場所のキー
    let anchor: String
    /// キー操作で選択中か
    let isSelected: Bool
    let editing: ItemEditing
    /// 目盛りの列の幅と、この項目の左端からグリッド左端までの距離。ドラッグ中の時刻をその列に出すのに使う
    let labelColumnWidth: CGFloat
    let distanceToGridLeft: CGFloat
    let dayWidth: CGFloat
    let board: TimelineDragBoard
    let onToggle: () -> Void
    /// 移動量（pt）から落とし先を求める
    let dropTarget: (CGSize) -> GridDropTarget
    let onDrop: (GridDropTarget) -> Void
    /// 終日欄へ落とした。その日
    let onDropAllDay: (Date) -> Void

    /// `@GestureState` はジェスチャが中断（スクロール開始・ウィンドウ切替）されても自動で 0 に戻る
    @GestureState private var translation: CGSize = .zero
    /// ドラッグ中の位置（`TimelineDragBoard.space` の座標）。終日欄の上にいるかの判定に使う
    @GestureState private var dragLocation: CGPoint?

    private var item: TimelineItem { placement.item }
    private var color: Color { Color(cgColor: item.color) }
    private var isDragging: Bool { translation != .zero }

    var body: some View {
        // 終日欄の上にいる間は影のほうを見せるので、時刻は出さず項目は薄くする
        let isOverAllDay = dragLocation.flatMap(board.allDayTarget(at:)) != nil
        let target = isDragging && !isOverAllDay ? dropTarget(translation) : nil
        let shiftX = CGFloat(target?.dayOffset ?? 0) * dayWidth
        content
            .selectionRing(isSelected)
            .opacity(item.isVirtual ? 0.45 : isOverAllDay ? 0.3 : isDragging ? 0.85 : 1)
            .onChange(of: isDragging) { _, dragging in
                if !dragging { board.ghost = nil }
            }
            .overlay(alignment: .topLeading) {
                if let target {
                    Text(timeText(minute: target.minute))
                        .font(.dayoDetail.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(width: labelColumnWidth, alignment: .trailing)
                        .padding(.vertical, 1)
                        .background(.background)
                        // 項目ごと横へずれるので、その分を戻して目盛りの列に留める
                        .offset(x: -distanceToGridLeft - shiftX, y: -7)
                        .allowsHitTesting(false)
                }
            }
            .offset(x: shiftX, y: translation.height)
            .zIndex(isDragging ? 1 : 0)
            .gesture(item.isEditable ? moveGesture : nil)
            .allowsHitTesting(!item.isVirtual)
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .event:
            HStack(alignment: .top, spacing: 0) {
                Rectangle().fill(color).frame(width: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.dayoTitle.weight(.semibold))
                        .lineLimit(placement.durationMinutes >= 60 ? 2 : 1)
                    if placement.durationMinutes >= 45, let start = item.start, let end = item.end {
                        Text("\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))")
                            .font(.dayoDetail)
                            // 週表示の狭い列で 1 文字ずつ折り返さないようにする
                            .lineLimit(1)
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
            .onEditGesture { editing.open(item, at: anchor) }
            .itemEditor(for: item, editing, at: anchor)
        case .reminder:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button(action: onToggle) {
                    Image(systemName: item.isVirtual ? "circle.dotted" : item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(color)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isVirtual ? "今後の回" : item.isCompleted ? "未完了に戻す" : "完了にする")
                HStack(spacing: 4) {
                    PriorityMark(priority: item.priority)
                        .font(.dayoTitle)
                    Text(item.title)
                        .font(.dayoTitle)
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                        .lineLimit(1)
                    EarlyReminderMark(minutes: item.earlyReminderMinutes)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .onEditGesture { editing.open(item, at: anchor) }
            .itemEditor(for: item, editing, at: anchor)
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
                    state = drag.translation
                }
            }
            .onEnded { value in
                if case .second(true, let drag?) = value {
                    onDrop(dropTarget(drag.translation))
                }
            }
    }
    #else
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(TimelineDragBoard.space))
            .updating($translation) { value, state, _ in state = value.translation }
            .updating($dragLocation) { value, state, _ in state = value.location }
            .onChanged { value in
                board.ghost = board.allDayTarget(at: value.location).map { _ in
                    TimelineDragBoard.Ghost(title: item.title, color: item.color, label: "終日", location: value.location)
                }
            }
            .onEnded { value in
                board.ghost = nil
                if let day = board.allDayTarget(at: value.location) {
                    onDropAllDay(day)
                } else {
                    onDrop(dropTarget(value.translation))
                }
            }
    }
    #endif
}
