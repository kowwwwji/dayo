#if os(macOS)
import AppKit
import DayoCore
import SwiftUI

/// タイムラインのキー操作。
enum TimelineKey {
    case selectNext
    case selectPrevious
    case selectLeft
    case selectRight
    case toggleCompleted
    case openEditor
    case clearSelection
    case showToday
    case showPrevious
    case showNext
    case toggleHelp
    case moveLater
    case moveEarlier
    case moveToPreviousDay
    case moveToNextDay

    /// キーを押し続けたときに繰り返すか。選択の移動だけ繰り返す。
    /// 完了の切替は保存が終わる前に次が来ると同じ状態を二重に書き込むので、繰り返さない。
    var repeats: Bool {
        switch self {
        case .selectNext, .selectPrevious, .selectLeft, .selectRight: true
        default: false
        }
    }

    /// キー入力に当たる操作。修飾キーなしの単キーと、⌘← / ⌘→。
    init?(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        // `?` は配列によって Shift が要るので、打たれた文字で判定する
        if event.characters == "?", modifiers.subtracting(.shift).isEmpty {
            self = .toggleHelp
            return
        }
        if modifiers == .command {
            switch event.specialKey {
            case .leftArrow: self = .showPrevious
            case .rightArrow: self = .showNext
            default: return nil
            }
            return
        }
        // Shift を押すと大文字で届くので、小文字に揃えて比べる（Caps Lock でも同じキーとして扱う）
        let character = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == .shift {
            switch character {
            case "j": self = .moveLater
            case "k": self = .moveEarlier
            case "h": self = .moveToPreviousDay
            case "l": self = .moveToNextDay
            default: return nil
            }
            return
        }
        guard modifiers.isEmpty else { return nil }
        switch character {
        case "j": self = .selectNext
        case "k": self = .selectPrevious
        case "h": self = .selectLeft
        case "l": self = .selectRight
        case "t": self = .showToday
        case " ": self = .toggleCompleted
        case "\r", "\u{3}": self = .openEditor
        case "\u{1b}": self = .clearSelection
        default: return nil
        }
    }
}

extension View {
    /// このビューのあるウインドウでのキー操作を受ける。`action` は処理したら true を返す（false ならキーは元の行き先へ流れる）。
    /// 文字入力中と、シートやポップオーバーが出ている間は呼ばれない。
    func onTimelineKey(isEnabled: Bool, perform action: @escaping (TimelineKey) -> Bool) -> some View {
        background(KeyCatcher(isEnabled: isEnabled, action: action))
    }
}

/// キー入力を拾う透明なビュー。
/// メニューの修飾キーなしショートカットは入力欄の文字入力まで奪うので、アプリに届いたイベントを見て、
/// 文字入力中でなければ拾う。⌘← / ⌘→ も入力欄の行頭 / 行末への移動を奪わないよう、ここで扱う。
private struct KeyCatcher: NSViewRepresentable {
    let isEnabled: Bool
    let action: (TimelineKey) -> Bool

    func makeNSView(context: Context) -> CatcherView {
        CatcherView()
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.isEnabled = isEnabled
        view.action = action
    }

    final class CatcherView: NSView {
        var isEnabled = true
        var action: ((TimelineKey) -> Bool)?
        private var monitor: Any?

        /// 入力欄の代わりにフォーカスを持つ。ウインドウは前面に戻るたびに first responder を復元するので、
        /// 誰も持っていないと入力欄へ戻ってしまい、編集を閉じたあとのキー操作が文字入力になる。
        override var acceptsFirstResponder: Bool { true }
        override var focusRingType: NSFocusRingType {
            get { .none }
            set {}
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard let window else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
                guard let self else { return event }
                if event.type == .leftMouseDown {
                    self.takeFocusIfClicked(event)
                    return event
                }
                if self.leavesTextField(event) { return nil }
                guard self.accepts(event), let key = TimelineKey(event) else { return event }
                // 押しっぱなしの繰り返しは、繰り返さない操作では捨てる
                if event.isARepeat, !key.repeats { return nil }
                return self.action?(key) == true ? nil : event
            }
            // 起動時はキー操作を受けられる状態から始める（入力欄へは ⌘N）
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window === window else { return }
                window.makeFirstResponder(self)
            }
        }

        /// 割り当ての無いキーは黙って捨てる（既定のままだと警告音が鳴る）。Esc だけは流して、フルスクリーンを抜ける等の既定動作を残す。
        override func keyDown(with event: NSEvent) {
            if event.charactersIgnoringModifiers == "\u{1b}" { super.keyDown(with: event) }
        }

        /// 入力欄にいるときにタイムラインをクリックしたら、キー操作を受けられる状態へ戻す。クリックそのものは奪わない。
        private func takeFocusIfClicked(_ event: NSEvent) {
            guard let window, event.window === window, window.attachedSheet == nil,
                  window.firstResponder is NSText,
                  bounds.contains(convert(event.locationInWindow, from: nil))
            else { return }
            window.makeFirstResponder(self)
        }

        /// 入力欄での Esc。入力欄を抜けてキー操作を受けられる状態へ戻す。変換中の Esc は変換の取り消しなので触らない。
        private func leavesTextField(_ event: NSEvent) -> Bool {
            guard let window, event.window === window, window.attachedSheet == nil,
                  event.charactersIgnoringModifiers == "\u{1b}",
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                  let text = window.firstResponder as? NSTextView, !text.hasMarkedText()
            else { return false }
            return window.makeFirstResponder(self)
        }

        deinit {
            removeMonitor()
        }

        private func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// このウインドウ宛てのキー入力で、文字入力中でないか。
        /// ポップオーバーや設定は別のウインドウなので、そこでのキー入力は `event.window` の比較で外れる。
        private func accepts(_ event: NSEvent) -> Bool {
            guard isEnabled, let window, event.window === window, window.attachedSheet == nil
            else { return false }
            // 入力欄を編集している間、ウインドウの first responder は NSText（フィールドエディタ）になる
            return !(window.firstResponder is NSText)
        }
    }
}

/// キー操作の一覧。`?` で出す。
/// キーはすべて小文字で書く。大文字は Shift を押すことを意味してしまうので、Shift は `⇧` で明示する。
struct KeyHelpView: View {
    let onClose: () -> Void

    private static let rows: [(keys: String, action: String)] = [
        ("j / k", "下 / 上の項目を選ぶ"),
        ("h / l", "週: 隣の日の列へ　日: 前 / 次の日へ"),
        ("⇧j / ⇧k", "選択中の項目を 15 分遅く / 早く"),
        ("⇧h / ⇧l", "選択中の項目を前 / 次の日へ（週表示）"),
        ("space", "選択中のリマインダーを完了 / 未完了"),
        ("return", "選択中の項目の編集を開く"),
        ("esc", "選択を解除（入力欄では入力欄を抜ける）"),
        ("t", "今日へ"),
        ("⌘n", "入力欄へ"),
        ("⌘1 / ⌘2", "日表示 / 週表示"),
        ("⌃⌘s", "サイドバーを出す / 隠す"),
        ("⌘← / ⌘→", "前 / 次の日（週表示では週）"),
        ("?", "この一覧を出す / 閉じる"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("キー操作")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(Self.rows, id: \.keys) { row in
                    GridRow {
                        Text(row.keys)
                            .font(.dayoTitle.monospaced().weight(.semibold))
                            .gridColumnAlignment(.trailing)
                        Text(row.action)
                            .font(.dayoTitle)
                    }
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        .shadow(radius: 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 一覧の外も含め、どこをクリックしても閉じる
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
    }
}

/// サイドバーを隠しているかの保存。メニューから切り替え、ウインドウは保存値を見て開閉する。
enum SidebarSetting {
    static let hiddenKey = "sidebarHidden"

    static func toggle() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: hiddenKey), forKey: hiddenKey)
    }
}

/// メニューに出すキー操作。⌘N は既定の「新規ウインドウ」を置き換える。
struct TimelineCommands: Commands {
    let model: TimelineModel
    let quickInputFocus: QuickInputFocus

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("クイック入力") { quickInputFocus.request() }
                .keyboardShortcut("n")
        }
        // 既定のサイドバーの項目は前面のウインドウにしか効かないので、保存値を切り替える自前の項目に置き換える。
        // 同じ場所に「前に足す」と「置き換える」を別々に書くと前者が消えるので、1 つにまとめる
        CommandGroup(replacing: .sidebar) {
            Button("日表示") { TimelineModeSetting.set(.day, on: model) }
                .keyboardShortcut("1")
            Button("週表示") { TimelineModeSetting.set(.week, on: model) }
                .keyboardShortcut("2")
            Divider()
            Button("サイドバーを表示 / 非表示") { SidebarSetting.toggle() }
                .keyboardShortcut("s", modifiers: [.control, .command])
        }
    }
}
#endif
