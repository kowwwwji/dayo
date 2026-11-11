import DayoCore
import SwiftUI

/// 予定と Todo を 1 本の時間軸で見せる。日表示は 1 列、3 日表示は 3 列、週表示は 7 列。
/// 上部に終日・期限切れ、中央に時刻付きのグリッド。期日なしのリマインダーはここには出さず、
/// サイドバーから落とされたものに期日を付けるだけ。
struct DayTimelineView: View {
    let model: TimelineModel
    /// 項目から詳細編集のモデルを作る。保存先（CalendarSource）は App が握る
    let makeEditor: @MainActor (TimelineItem) -> ItemEditorModel
    /// 新規登録のモデルを作る。引数は開始日時と、終日として開くか
    let makeNewEditor: @MainActor (Date, Bool) -> ItemEditorModel
    /// 日付ジャンプを開く入口（Mac の `g`）。ボタンは入力欄の行にある
    var dateJump: DateJumpRequest?
    #if os(macOS)
    /// サイドバーの「期日なし」からのドラッグ。落とされた日時を期日にする
    var undatedDrag: UndatedDrag?
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @State private var editor: ItemEditorModel?
    @State private var editorAnchor: String?
    @State private var board = TimelineDragBoard()
    /// 繰り返し予定の日時を変える・削除する前に、どの回に及ぶかを聞いている間の保留
    @State private var pendingChange: PendingChange?

    private struct PendingChange {
        var message = "どの回の日時を変えますか？"
        let perform: (EditSpan) async -> Void
    }
    @State private var showsSettings = false
    /// キー操作の一覧を出しているか（Mac のみ）
    @State private var showsKeyHelp = false

    private var editing: ItemEditing {
        ItemEditing(editor: $editor, anchor: $editorAnchor, make: makeEditor, makeNew: makeNewEditor)
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            // Mac は日付をウィンドウタイトルに、移動を入力欄の行に置くのでヘッダーは無い
            header
            Divider()
            #endif
            if let message = model.errorMessage {
                Text(message)
                    .font(.dayoSmall)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                Divider()
            }
            content
        }
        #if os(macOS)
        .overlay {
            if showsKeyHelp {
                KeyHelpView { showsKeyHelp = false }
            }
        }
        .onTimelineKey(
            isEnabled: model.access == .granted && editor == nil && pendingChange == nil
                && dateJump?.isPresented != true,
            perform: handle
        )
        #endif
        .environment(\.selectTimelineItem) { model.select($0) }
        .task { await model.activate() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.activate() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            Task { await model.handleDayChanged() }
        }
    }

    #if os(macOS)
    /// キー操作。何もしなかったキーは false を返して元の行き先へ流す。
    private func handle(_ key: TimelineKey) -> Bool {
        switch key {
        case .selectNext: model.selectNext()
        case .selectPrevious: model.selectPrevious()
        case .selectLeft: Task { await model.selectLeft() }
        case .selectRight: Task { await model.selectRight() }
        case .showToday: Task { await model.showToday() }
        case .showPrevious: Task { await model.showPrevious() }
        case .showNext: Task { await model.showNext() }
        case .toggleCompleted:
            guard model.selectedItem?.kind == .reminder else { return false }
            Task { await model.toggleSelectedCompleted() }
        case .openEditor:
            guard let selection = model.selection, let item = model.selectedItem else { return false }
            editing.open(item, at: selection.place.editorAnchor)
        case .toggleHelp: showsKeyHelp.toggle()
        case .moveLater: moveSelection { await model.moveSelectionInTime(1, span: $0) }
        case .moveEarlier: moveSelection { await model.moveSelectionInTime(-1, span: $0) }
        case .moveToPreviousDay: moveSelection { await model.moveSelectionByDay(-1, span: $0) }
        case .moveToNextDay: moveSelection { await model.moveSelectionByDay(1, span: $0) }
        case .lengthen: resizeSelection(1)
        case .shorten: resizeSelection(-1)
        case .deleteSelection:
            guard let item = model.selectedItem, item.isEditable else { return false }
            delete(item)
        case .undo: Task { await model.undo() }
        case .jumpToDate:
            guard let dateJump else { return false }
            dateJump.isPresented = true
        case .clearSelection:
            // 一覧が出ていれば、まずそれを閉じる
            if showsKeyHelp {
                showsKeyHelp = false
                return true
            }
            guard model.selection != nil else { return false }
            model.clearSelection()
        }
        return true
    }

    /// 選択中の項目をキーで動かす。ドラッグと同じく、繰り返しの予定は先に範囲を聞く。
    private func moveSelection(_ perform: @escaping (EditSpan) async -> Void) {
        guard let item = model.selectedItem else { return }
        change(item, perform)
    }

    /// 選択中の予定の長さをキーで変える。長さの無い項目（リマインダー、終日）では範囲も聞かない。
    private func resizeSelection(_ direction: Int) {
        guard let item = model.selectedItem, item.kind == .event, !item.isAllDay else { return }
        change(item) { await model.resizeSelection(direction, span: $0) }
    }

    /// 選択中の項目を削除する。確認は出さない（すぐには消さず、取り消せる間を置くため）。
    /// 繰り返しの予定だけは、どの回かを聞く。
    private func delete(_ item: TimelineItem) {
        if item.kind == .event, item.hasRecurrence {
            ask(PendingChange(message: "「\(item.title)」のどの回を削除しますか？") {
                await deleteSelection(item, span: $0)
            })
        } else {
            Task { await model.deleteSelection(span: .thisOccurrence) }
        }
    }

    /// 範囲を聞いている間に選択が変わっていたら（同期で消えた等）、何もしない。
    private func deleteSelection(_ item: TimelineItem, span: EditSpan) async {
        guard model.selectedItem?.id == item.id else { return }
        await model.deleteSelection(span: span)
    }
    #endif

    #if os(iOS)
    private var header: some View {
        HStack(spacing: 12) {
            DayNavigationControls(model: model)
            Spacer()
            // iPhone には設定ウィンドウが無いのでここから開く（Mac は ⌘,）
            Button { showsSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .sheet(isPresented: $showsSettings) {
                NavigationStack {
                    SettingsView()
                        .navigationTitle("設定")
                        .toolbar {
                            Button("完了") { showsSettings = false }
                        }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    #endif

    @ViewBuilder
    private var content: some View {
        switch model.access {
        case .granted:
            sections
        case .denied, .restricted:
            ContentUnavailableView(
                "カレンダーとリマインダーへのアクセスが必要です",
                systemImage: "lock",
                description: Text("システム設定のプライバシーで Dayo にフルアクセスを許可してください。")
            )
        case .notDetermined:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sections: some View {
        VStack(spacing: 0) {
            // 期限切れを上、終日を時間軸のすぐ上に置く。終日欄は時間軸とドラッグで行き来するので隣り合わせにする
            if !model.timeline.overdue.isEmpty {
                // 1 行およそ 30pt。多くても 3 行半で止めて残りはスクロール
                PinnedSection(
                    title: "期限切れ",
                    scrollHeight: min(CGFloat(model.timeline.overdue.count) * 30, 105),
                    scrollTarget: model.selection?.place == .overdue ? model.selection?.itemID : nil
                ) {
                    ForEach(model.timeline.overdue) { item in
                        overdueRow(item).id(item.id)
                    }
                }
                Divider()
            }
            // 終日欄は空でも出す。ダブルクリックでの登録と、時間軸からのドラッグの落とし先になるため
            if model.mode != .day {
                // 列と見出しがずれないよう、日付はモデルの範囲ではなく実際に並んでいる列から取る
                WeekHeaderView(
                    days: model.columns.map(\.day),
                    spans: model.allDaySpans,
                    selection: model.selection,
                    editing: editing,
                    board: board,
                    onToggle: { item in Task { await model.toggleCompleted(item) } },
                    onMoveDays: { item, days in
                        change(item) { await model.moveAllDay(item, byDays: days, span: $0) }
                    },
                    onMakeTimed: makeTimed
                )
            } else {
                // 日表示にも 3 日・週と同じ曜日と日付を出す。終日欄との間隔は `WeekHeaderView` の上の余白に合わせる
                DayLabelsRow(days: model.columns.map(\.day))
                    .padding(.top, 6)
                dayAllDay
            }
            Divider()
            timed
        }
        .overlay { DragGhostView(board: board) }
        .coordinateSpace(name: TimelineDragBoard.space)
        #if os(macOS)
        // 落とした位置は、このビューの座標（`TimelineDragBoard.space` と同じ）で届く
        .onDrop(of: [.plainText], delegate: UndatedDropDelegate(drag: undatedDrag, board: board, model: model))
        #endif
        .confirmationDialog(
            "繰り返しの予定です",
            isPresented: Binding(get: { pendingChange != nil }, set: { if !$0 { pendingChange = nil } }),
            titleVisibility: .visible,
            presenting: pendingChange
        ) { pending in
            Button("この回のみ") { Task { await pending.perform(.thisOccurrence) } }
            Button("以降すべて") { Task { await pending.perform(.futureOccurrences) } }
            Button("キャンセル", role: .cancel) {}
        } message: { pending in
            Text(pending.message)
        }
        .overlay {
            // 列が複数の表示は空でも曜日と時間軸を見せる
            if model.mode == .day, model.hasLoaded, model.timeline.isEmpty {
                ContentUnavailableView("予定も Todo もありません", systemImage: "checkmark.circle")
            }
        }
    }

    /// 日表示の終日欄で新規登録のエディタを開く場所のキー。
    private static let newAllDayAnchor = "allDay-new"

    /// 日表示の終日欄。チップを左から並べる。
    private var dayAllDay: some View {
        PinnedSection(title: "終日") {
            FlowLayout(spacing: 6) {
                ForEach(model.timeline.allDay) { item in
                    // 日表示は列が 1 つなので横には動かせない。時間軸へ落とすことだけできる
                    AllDayChip(
                        item: item,
                        editing: editing,
                        isSelected: model.selection == TimelineSelection(itemID: item.id, place: .allDay),
                        drag: AllDayChipDrag(
                            board: board,
                            onMoveDays: { _ in },
                            onMakeTimed: { day, minute in makeTimed(item, day, minute) }
                        ),
                        onDoubleClick: { _ in
                            editing.openNew(at: model.day, isAllDay: true, anchor: Self.newAllDayAnchor)
                        },
                        onSelect: { model.select(TimelineSelection(itemID: item.id, place: .allDay)) }
                    ) {
                        Task { await model.toggleCompleted(item) }
                    }
                }
                NewItemChip(editing: editing, anchor: Self.newAllDayAnchor)
            }
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .topLeading)
            #if os(macOS)
            // 空いているところのダブルクリックで、この日の終日として登録を開く。チップの上のダブルクリックはチップが受ける
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(TapGesture(count: 2).onEnded {
                        editing.openNew(at: model.day, isAllDay: true, anchor: Self.newAllDayAnchor)
                    })
            }
            #endif
            // 時間軸からここへ落とした項目を終日にする
            .onFrameChange { board.allDayFrame = $0 }
        }
    }

    private var timed: some View {
        DayGridView(
            columns: model.columns,
            selection: model.selection,
            isLoaded: model.isLoadedForRange,
            editing: editing,
            board: board,
            onToggle: { item in Task { await model.toggleCompleted(item) } },
            onMove: { move, span in
                Task {
                    await model.move(
                        move.item, from: move.originDay, toDay: move.targetDay, startMinute: move.minute, span: span
                    )
                }
            },
            onMakeAllDay: { item, day in
                change(item) { await model.makeAllDay(item, onDay: day, span: $0) }
            },
            onResize: { item, end, span in
                Task { await model.resize(item, toEnd: end, span: span) }
            }
        )
    }

    private func makeTimed(_ item: TimelineItem, _ day: Date, _ minute: Int) {
        change(item) { await model.makeTimed(item, onDay: day, startMinute: minute, span: $0) }
    }

    /// 日時を変える。繰り返しの予定は回ごとに分けて変えられるので、先に範囲を聞く。
    private func change(_ item: TimelineItem, _ perform: @escaping (EditSpan) async -> Void) {
        if item.kind == .event, item.hasRecurrence {
            ask(PendingChange(perform: perform))
        } else {
            Task { await perform(.thisOccurrence) }
        }
    }

    /// どの回に及ぶかを聞く。Mac は「この回のみ」に枠を置ける AppKit のダイアログ、iPhone は確認ダイアログ。
    private func ask(_ pending: PendingChange) {
        #if os(macOS)
        SpanAlert.present(message: pending.message) { span in
            guard let span else { return }
            Task { await pending.perform(span) }
        }
        #else
        pendingChange = pending
        #endif
    }

    /// 期限切れ欄の 1 行。
    private func overdueRow(_ item: TimelineItem) -> some View {
        TimelineRow(
            item: item,
            editing: editing,
            anchor: TimelineSelection.Place.overdue.editorAnchor,
            isSelected: model.selection == TimelineSelection(itemID: item.id, place: .overdue),
            onSelect: { model.select(TimelineSelection(itemID: item.id, place: .overdue)) }
        ) {
            Task { await model.toggleCompleted(item) }
        }
    }
}

#if os(macOS)
/// サイドバーの「期日なし」から落とされたリマインダーを受ける。時間軸ならその日時、終日欄ならその日が期日になる。
private struct UndatedDropDelegate: DropDelegate {
    let drag: UndatedDrag?
    let board: TimelineDragBoard
    let model: TimelineModel

    private enum Target: Sendable {
        case timed(day: Date, minute: Int)
        case allDay(day: Date)

        var label: String {
            switch self {
            case .timed(_, let minute): timeText(minute: minute)
            case .allDay: "終日"
            }
        }
    }

    private func target(at point: CGPoint) -> Target? {
        if let day = board.allDayTarget(at: point) { return .allDay(day: day) }
        // リマインダーには長さが無い
        return board.gridTarget(at: point, duration: 1).map { .timed(day: $0.day, minute: $0.minute) }
    }

    /// 行き先の時刻を、タイムラインの中のドラッグと同じ影で見せる。
    private func showGhost(_ info: DropInfo) -> Bool {
        guard let item = drag?.item, let target = target(at: info.location) else {
            board.ghost = nil
            return false
        }
        board.ghost = TimelineDragBoard.Ghost(
            title: item.title, color: item.color, label: target.label, location: info.location
        )
        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        drag?.item != nil
    }

    func dropEntered(info: DropInfo) {
        _ = showGhost(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: showGhost(info) ? .copy : .forbidden)
    }

    func dropExited(info: DropInfo) {
        board.ghost = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        board.ghost = nil
        guard let drag, let item = drag.item, let target = target(at: info.location),
              let provider = info.itemProviders(for: [.plainText]).first
        else { return false }
        let carried = drag.text
        drag.end()
        // 掴んだまま落とさなかったリマインダーが残っていると、ほかのアプリから文字を落としたときにそれへ期日が付く。
        // 運ばれてきた中身が掴んだものと同じかを確かめる
        let (id, model) = (item.id, model)
        _ = provider.loadObject(ofClass: NSString.self) { text, _ in
            guard let text = text as? NSString, text as String == carried else { return }
            Task { @MainActor in
                guard let item = model.undated.first(where: { $0.id == id }) else { return }
                switch target {
                case .timed(let day, let minute):
                    await model.makeTimed(item, onDay: day, startMinute: minute, span: .thisOccurrence)
                case .allDay(let day):
                    await model.makeAllDay(item, onDay: day, span: .thisOccurrence)
                }
            }
        }
        return true
    }
}
#endif

/// グリッドの上に固定する小さなセクション。左にラベル、右に中身を置く（Apple カレンダーの「終日」行と同じ形）。
/// ラベル幅はグリッドの時刻ラベルに合わせ、縦の線が揃うようにする。
/// `scrollHeight` を渡すと行数に応じた高さ（上限あり）で内部スクロールする。渡さなければ中身の高さそのまま。
private struct PinnedSection<Content: View>: View {
    let title: String
    var scrollHeight: CGFloat?
    /// 見えるところまでスクロールしたい行の id。`scrollHeight` を渡したときだけ効く
    var scrollTarget: String?
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(title)
                .font(.dayoDetail)
                .foregroundStyle(.secondary)
                .frame(width: DayGridView.labelWidth - 6, alignment: .trailing)
                .padding(.top, 4)
            if let scrollHeight {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            content
                        }
                        // ScrollView は中身が狭いと中央に寄せるので、左端に固定する
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: scrollTarget) { _, target in
                        if let target { proxy.scrollTo(target) }
                    }
                }
                .frame(height: scrollHeight)
            } else {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // 左余白は付けない。グリッドの時刻ラベルが左端 0 から始まるので、同じ x に揃える
        .padding(.trailing, DayGridView.trailingInset)
        .padding(.vertical, 6)
    }
}
