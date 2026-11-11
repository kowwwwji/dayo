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

    /// キー入力に当たる操作。修飾キーなしの単キーと、⌘← / ⌘→。
    init?(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command {
            switch event.specialKey {
            case .leftArrow: self = .showPrevious
            case .rightArrow: self = .showNext
            default: return nil
            }
            return
        }
        guard modifiers.isEmpty else { return nil }
        switch event.charactersIgnoringModifiers {
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

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.accepts(event), let key = TimelineKey(event), self.action?(key) == true
                else { return event }
                return nil
            }
        }

        deinit {
            removeMonitor()
        }

        private func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// このウインドウが前面で、文字入力中でないか。
        /// ポップオーバーは別のウインドウなので、そこでのキー入力は `event.window` の比較で外れる。
        private func accepts(_ event: NSEvent) -> Bool {
            guard isEnabled, let window, event.window === window, window.isKeyWindow, window.attachedSheet == nil
            else { return false }
            // 入力欄を編集している間、ウインドウの first responder は NSText（フィールドエディタ）になる
            return !(window.firstResponder is NSText)
        }
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
        CommandGroup(before: .sidebar) {
            Button("日") { TimelineModeSetting.set(.day, on: model) }
                .keyboardShortcut("1")
            Button("週") { TimelineModeSetting.set(.week, on: model) }
                .keyboardShortcut("2")
            Divider()
        }
    }
}
#endif
