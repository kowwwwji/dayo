import DayoCore
import SwiftUI

extension View {
    /// 項目へのクリック。Mac は左クリックで選択、右クリック（control + クリックも）で選択して編集を開く。iPhone はタップで編集を開く。
    /// Mac で普通のクリックに編集を割り当てないのは、ドラッグやダブルクリックでの登録と取り違えて開いてしまうのを避けるため。
    func onItemClick(select: @escaping () -> Void, edit: @escaping () -> Void) -> some View {
        #if os(macOS)
        overlay(ClickCatcher(select: select, edit: edit).allowsHitTesting(false))
        #else
        onTapGesture(perform: edit)
        #endif
    }
}

extension EnvironmentValues {
    /// クリックした項目を選択する。タイムラインの画面が差し込む。
    @Entry var selectTimelineItem: (TimelineSelection) -> Void = { _ in }
}

#if os(macOS)
/// 項目へのクリックを拾う透明なビュー。
/// クリックを受けるビューとして上に重ねると下の SwiftUI のドラッグやボタンを塞いでしまうので、
/// ヒットテストには加わらず、アプリに届いたイベントを見て自分の範囲内なら拾う。
private struct ClickCatcher: NSViewRepresentable {
    let select: () -> Void
    let edit: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        CatcherView()
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.select = select
        view.edit = edit
    }

    final class CatcherView: NSView {
        var select: (() -> Void)?
        var edit: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                guard let self, self.catches(event) else { return event }
                self.select?()
                let isSecondaryClick = event.type == .rightMouseDown || event.modifierFlags.contains(.control)
                // 左クリックは選択するだけで、そのまま下へ通す（ドラッグ・ダブルクリック・チェックの丸が受ける）
                guard isSecondaryClick else { return event }
                self.edit?()
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

        /// このビューの見えている範囲へのクリックか。スクロールで隠れている部分には反応しない。
        private func catches(_ event: NSEvent) -> Bool {
            // シート（繰り返しの範囲を聞くダイアログなど）が出ている間は、その下の項目に触れない
            guard let window, event.window === window, window.attachedSheet == nil, !isHiddenOrHasHiddenAncestor
            else { return false }
            let point = convert(event.locationInWindow, from: nil)
            // `visibleRect` はスクロール領域で切り取られた範囲を返すが、自分の枠より広いことがあるので枠と重ねる
            return bounds.intersection(visibleRect).contains(point)
        }
    }
}
#endif
