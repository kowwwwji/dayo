import SwiftUI

extension View {
    /// 項目の編集を開く操作。Mac は右クリック（control + クリックも）、iPhone はタップ。
    /// Mac で普通のクリックに割り当てないのは、ドラッグやダブルクリックでの登録と取り違えて開いてしまうのを避けるため。
    func onEditGesture(perform action: @escaping () -> Void) -> some View {
        #if os(macOS)
        overlay(RightClickCatcher(action: action).allowsHitTesting(false))
        #else
        onTapGesture(perform: action)
        #endif
    }
}

#if os(macOS)
/// 右クリックを拾う透明なビュー。
/// クリックを受けるビューとして上に重ねると下の SwiftUI のドラッグやボタンを塞いでしまうので、
/// ヒットテストには加わらず、アプリに届いたイベントを見て自分の範囲内なら拾う。
private struct RightClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        CatcherView()
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.action = action
    }

    final class CatcherView: NSView {
        var action: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                guard let self, self.catches(event) else { return event }
                self.action?()
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

        /// このビューの見えている範囲への右クリック（または control + クリック）か。
        /// スクロールで隠れている部分には反応しない。
        private func catches(_ event: NSEvent) -> Bool {
            // シート（繰り返しの範囲を聞くダイアログなど）が出ている間は、その下の項目を開かない
            guard let window, event.window === window, window.attachedSheet == nil, !isHiddenOrHasHiddenAncestor
            else { return false }
            let isSecondaryClick = event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            guard isSecondaryClick else { return false }
            let point = convert(event.locationInWindow, from: nil)
            // `visibleRect` はスクロール領域で切り取られた範囲を返すが、自分の枠より広いことがあるので枠と重ねる
            return bounds.intersection(visibleRect).contains(point)
        }
    }
}
#endif
