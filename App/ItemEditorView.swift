import DayoCore
import SwiftUI

/// 項目をタップしたときにエディタを開くための配線。
/// 開いているエディタは 1 つで、どの項目の上に出すかは `item.id` と開いた場所（`anchor`）で判定する。
/// 日をまたぐ予定は複数の列に同じ項目が出るので、id だけだと全部の列に出てしまう。
@MainActor
struct ItemEditing {
    @Binding var editor: ItemEditorModel?
    @Binding var anchor: String?
    let make: @MainActor (TimelineItem) -> ItemEditorModel
    /// 新規登録のモデルを作る。引数は開始日時と、終日として開くか
    let makeNew: @MainActor (Date, Bool) -> ItemEditorModel

    func open(_ item: TimelineItem, at anchor: String? = nil) {
        // 繰り返しリマインダーの将来回は実体が無いので開かない
        guard !item.isVirtual else { return }
        self.anchor = anchor
        editor = make(item)
    }

    /// 新規登録を開く。`anchor` は登録先を示す仮の項目を置いた場所。
    func openNew(at start: Date, isAllDay: Bool, anchor: String) {
        self.anchor = anchor
        editor = makeNew(start, isAllDay)
    }

    func isPresented(for item: TimelineItem, at anchor: String? = nil) -> Binding<Bool> {
        Binding(
            get: { isOpen(for: item, at: anchor) },
            set: { if !$0, isOpen(for: item, at: anchor) { editor = nil } }
        )
    }

    func isPresentedForNew(at anchor: String) -> Binding<Bool> {
        Binding(
            get: { isOpenForNew(at: anchor) },
            set: { if !$0, isOpenForNew(at: anchor) { editor = nil } }
        )
    }

    private func isOpen(for item: TimelineItem, at anchor: String?) -> Bool {
        editor?.isNew == false && editor?.item.id == item.id && self.anchor == anchor
    }

    /// その場所で新規登録を開いているか。仮の項目を出すかどうかの判定にも使う。
    func isOpenForNew(at anchor: String) -> Bool {
        editor?.isNew == true && self.anchor == anchor
    }
}

extension TimelineSelection.Place {
    /// エディタを開く場所のキー。項目を描く側と、キー操作で開く側が同じ値を使う。
    var editorAnchor: String {
        switch self {
        case .overdue: "overdue"
        case .allDay: "allDay"
        case .grid(let day): "grid-\(day.timeIntervalSince1970)"
        }
    }
}

extension View {
    /// 新規登録のエディタを、登録先を示す仮の項目に付けて出す。
    func newItemEditor(_ editing: ItemEditing, at anchor: String) -> some View {
        modifier(NewItemEditorPresenter(editing: editing, anchor: anchor))
    }
}

private struct NewItemEditorPresenter: ViewModifier {
    let editing: ItemEditing
    let anchor: String

    func body(content: Content) -> some View {
        #if os(macOS)
        content.popover(isPresented: editing.isPresentedForNew(at: anchor), arrowEdge: .trailing) {
            if let editor = editing.editor {
                ItemEditorView(model: editor)
            }
        }
        #else
        content.sheet(isPresented: editing.isPresentedForNew(at: anchor)) {
            if let editor = editing.editor {
                NavigationStack { ItemEditorView(model: editor) }
            }
        }
        #endif
    }
}

extension View {
    /// Mac はその項目に付いたポップオーバー、iPhone はシートでエディタを出す。
    /// 同じ項目を複数の場所に出すビューは、場所ごとに違う `anchor` を渡す。
    func itemEditor(for item: TimelineItem, _ editing: ItemEditing, at anchor: String? = nil) -> some View {
        modifier(ItemEditorPresenter(item: item, editing: editing, anchor: anchor))
    }
}

private struct ItemEditorPresenter: ViewModifier {
    let item: TimelineItem
    let editing: ItemEditing
    let anchor: String?

    func body(content: Content) -> some View {
        #if os(macOS)
        content.popover(isPresented: editing.isPresented(for: item, at: anchor), arrowEdge: .trailing) {
            if let editor = editing.editor {
                ItemEditorView(model: editor)
            }
        }
        #else
        content.sheet(isPresented: editing.isPresented(for: item, at: anchor)) {
            if let editor = editing.editor {
                NavigationStack { ItemEditorView(model: editor) }
            }
        }
        #endif
    }
}

/// 詳細編集。タイトル・日時・繰り返し・保存先・メモを直し、削除もここから。
struct ItemEditorView: View {
    @Bindable var model: ItemEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var pendingAction: PendingAction?
    @State private var confirmsDelete = false
    @FocusState private var titleFocused: Bool
    @FocusState private var saveFocused: Bool
    @FocusState private var notesFocused: Bool

    private enum PendingAction { case save, delete }

    private var isEvent: Bool { model.item.kind == .event }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if model.isNew {
                    Picker("種別", selection: Binding(
                        get: { model.kind },
                        set: { kind in Task { await model.setKind(kind) } }
                    )) {
                        Text("予定").tag(ItemKind.event)
                        Text("リマインダー").tag(ItemKind.reminder)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                TextField("タイトル", text: $model.title)
                    .focused($titleFocused)
                    // 新規登録はタイトルを打って Enter で終わるようにする
                    .onSubmit { if model.isNew { trigger(.save) } }
                // 場所とビデオ会議は見るだけ。押すとブラウザで開く（直すのは純正カレンダーに任せる）
                if let url = model.locationMapURL {
                    LabeledContent("場所") {
                        Link(destination: url) {
                            Label(model.location, systemImage: "map")
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                        }
                        .help("Google マップで開く")
                    }
                }
                // Google カレンダーがメモに足すビデオ会議の案内は、メモ欄には出さずリンクにする
                if let url = model.conferenceURL {
                    LabeledContent("ビデオ会議") {
                        Link(destination: url) {
                            Label("参加", systemImage: "video")
                        }
                    }
                }
                if !isEvent {
                    Toggle("期日", isOn: $model.hasDate)
                }
                if isEvent || model.hasDate {
                    Toggle(isEvent ? "終日" : "時刻なし", isOn: $model.isAllDay)
                    // 開始と終了は 1 行にまとめ、間に区切り線を入れない
                    VStack(alignment: .leading, spacing: 8) {
                        DatePicker(isEvent ? "開始" : "期日", selection: $model.start, displayedComponents: dateComponents)
                        if isEvent {
                            DatePicker("終了", selection: $model.end, displayedComponents: dateComponents)
                        }
                    }
                    // Mac は上下ボタン（ステッパー）無しの入力欄。年月日・時分をクリックして直接打つ
                    #if os(macOS)
                    .datePickerStyle(.field)
                    #endif
                    // アプリは日本語の地域化を持たないので、既定だと英語の書式（日付と時刻の間に「,」）になる。
                    // 日本語の書式（2026/11/11 9:00）で出す
                    .environment(\.locale, Locale(identifier: "ja_JP"))
                }
                if !isEvent {
                    Picker("優先度", selection: $model.priority) {
                        ForEach(ReminderPriority.allCases, id: \.self) { priority in
                            Text(priority.label).tag(priority)
                        }
                    }
                    if model.hasDate, !model.isAllDay {
                        EarlyReminderPicker("早期リマインダー", minutes: $model.earlyReminderMinutes)
                    }
                }
                Picker("繰り返し", selection: $model.recurrence) {
                    ForEach(model.recurrenceOptions, id: \.self) { option in
                        Text(model.label(for: option)).tag(option)
                    }
                }
                .disabled(model.recurrence == .unsupported)
                Picker(isEvent ? "カレンダー" : "リスト", selection: $model.destinationID) {
                    // 一覧の読み込み前や書き込み不可の保存先でも、今の保存先を選択肢に残す
                    if !model.destinations.contains(where: { $0.id == model.item.calendarIdentifier }) {
                        Text(model.item.sourceName).tag(model.item.calendarIdentifier)
                    }
                    ForEach(model.destinations) { destination in
                        Text(destination.name).tag(destination.id)
                    }
                }
                // URL は空でも欄を出して書き込めるようにする。ブラウザで開けるものなら、隣のボタンで開く
                if isEvent {
                    HStack(spacing: 6) {
                        TextField("URL", text: $model.urlText)
                        if let url = model.linkURL {
                            Link(destination: url) {
                                Image(systemName: "safari")
                            }
                            .help("ブラウザで開く")
                            .accessibilityLabel("ブラウザで開く")
                        }
                    }
                }
                Section("メモ") {
                    TextEditor(text: $model.notes)
                        .frame(minHeight: 60)
                        // メモは空だとカーソルが見えにくく、フォーカスがあるか分からない。ある間は枠で示す
                        .focused($notesFocused)
                        .overlay {
                            if notesFocused {
                                // 文字に重ならないよう、欄の外側に描く
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                                    .padding(-5)
                                    .allowsHitTesting(false)
                            }
                        }
                        #if os(macOS)
                        // メモは最後の入力欄なので、Tab はタブ文字ではなく保存ボタンへ進む。Shift+Tab は前の入力欄へ戻る
                        // （Shift+Tab は配列によって別の文字で届くので、両方を受けて修飾キーで見分ける）
                        .onKeyPress(keys: [.tab, Self.backtab]) { press in
                            if press.modifiers.contains(.shift) || press.key == Self.backtab {
                                // 行き先は AppKit で決めるので、メモを離れたことは自分で伝える（伝えないと枠が残る）。
                                // 先に移すと、状態を下ろしたときにフォーカスごと外れるので、下ろしてから移す
                                let target = Self.fieldAboveNotes()
                                notesFocused = false
                                DispatchQueue.main.async { target?.window?.makeFirstResponder(target) }
                            } else {
                                saveFocused = true
                            }
                            return .handled
                        }
                        #endif
                }
                if !model.item.isEditable {
                    Text("このカレンダーは読み取り専用です（誕生日・祝日・購読など）")
                        .font(.dayoSmall)
                        .foregroundStyle(.secondary)
                }
                if let message = model.errorMessage {
                    Text(message)
                        .font(.dayoSmall)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .disabled(!model.item.isEditable)
            Divider()
            HStack {
                if !model.isNew {
                    Button("削除", role: .destructive) { trigger(.delete) }
                        .disabled(!model.item.isEditable || model.isSaving)
                }
                Spacer()
                Button("キャンセル") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(model.isNew ? "登録" : "保存") { trigger(.save) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.item.isEditable || model.isSaving)
                    #if os(macOS)
                    // メモから Tab で来られるよう、キーボード操作の設定に関わらずフォーカスを受ける
                    .focusable()
                    .focused($saveFocused)
                    .onKeyPress(.space) {
                        trigger(.save)
                        return .handled
                    }
                    #endif
            }
            .padding()
            // メモのように return が改行になる入力欄からでも、⌘return で保存できるようにする。
            // ボタン 1 つに付けられるショートカットは 1 つなので、見えないボタンで受ける
            .background {
                Button("") { trigger(.save) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.item.isEditable || model.isSaving)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        // 開始を動かしたら長さを保って終了も動かす
        .onChange(of: model.start) { old, new in
            guard isEvent else { return }
            model.end = model.end.addingTimeInterval(new.timeIntervalSince(old))
        }
        .confirmationDialog("「\(model.item.title)」を削除しますか？", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) { run(.delete, span: .thisOccurrence) }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("純正アプリと共有相手からも消えます。")
        }
        #if os(macOS)
        .frame(width: 380, height: 480)
        #endif
        // ポップオーバーが前面に出てからでないとフォーカスが入らないので、表示の次の周回で当てる
        .onAppear {
            if model.isNew {
                DispatchQueue.main.async { titleFocused = true }
            }
        }
        .task {
            await model.loadDestinations()
        }
        .confirmationDialog(
            "繰り返しの予定です",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("この回のみ") { run(pendingAction, span: .thisOccurrence) }
            Button("以降すべて") { run(pendingAction, span: .futureOccurrences) }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text(pendingAction == .delete ? "どの回を削除しますか？" : "どの回に変更を適用しますか？")
        }
    }

    #if os(macOS)
    /// Shift+Tab で届く文字（AppKit の back tab）。
    private static let backtab = KeyEquivalent("\u{19}")

    /// メモのすぐ上にある、フォーカスを受けられる欄。
    /// AppKit の「前のキービュー」は使えない（メモ自身を包むビューや下のボタンを返し、画面の並びと合わない）。
    /// どの欄がフォーカスを受けるかは期日の有無やキーボード操作の設定で変わるので、並びを自前で持たず、画面上の位置から探す。
    private static func fieldAboveNotes() -> NSView? {
        // ポップオーバーの中の欄は、親のウインドウの first responder としても報告される。探すのは、メモが実際に載っているウインドウの中
        guard let notes = NSApp.keyWindow?.firstResponder as? NSView, let window = notes.window,
              let root = window.contentView?.superview ?? window.contentView
        else { return nil }
        // ウインドウの座標は上が大きい
        let top = notes.convert(notes.bounds, to: nil).maxY
        var nearest: (view: NSView, frame: CGRect)?
        func visit(_ view: NSView) {
            guard !view.isHidden else { return }
            let frame = view.convert(view.bounds, to: nil)
            if view.canBecomeKeyView, !notes.isDescendant(of: view), frame.minY >= top - 1 {
                if let found = nearest?.frame {
                    if (frame.minY, -frame.maxX) < (found.minY, -found.maxX) { nearest = (view, frame) }
                } else {
                    nearest = (view, frame)
                }
            }
            view.subviews.forEach(visit)
        }
        visit(root)
        return nearest?.view
    }
    #endif

    private var dateComponents: DatePickerComponents {
        model.isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    /// 繰り返しの予定なら範囲を聞く。削除はそれ以外でも必ず確認する（同期先からも消えるため）。
    private func trigger(_ action: PendingAction) {
        if model.needsSpanChoice {
            pendingAction = action
        } else if action == .delete {
            confirmsDelete = true
        } else {
            run(action, span: .thisOccurrence)
        }
    }

    private func run(_ action: PendingAction?, span: EditSpan) {
        guard let action else { return }
        Task {
            let done = switch action {
            case .save: await model.save(span: span)
            case .delete: await model.delete(span: span)
            }
            if done { dismiss() }
        }
    }
}
