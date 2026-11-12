import DayoCore
import SwiftUI

extension View {
    /// 項目へのクリック。Mac は左クリックで選択して情報カードを出し、右クリック（control + クリックも）で選択して編集を開く。iPhone はタップで編集を開く。
    /// Mac で普通のクリックに編集を割り当てないのは、ドラッグやダブルクリックでの登録と取り違えて開いてしまうのを避けるため。
    /// `cardInset` は左端からカードを出さない幅（リマインダーのチェックの丸。そこのクリックは完了だけ）。
    func onItemClick(
        select: @escaping () -> Void, card: ItemCardClick? = nil, cardInset: CGFloat = 0, edit: @escaping () -> Void
    ) -> some View {
        #if os(macOS)
        overlay(ClickCatcher(select: select, card: card, cardInset: cardInset, edit: edit).allowsHitTesting(false))
        #else
        onTapGesture(perform: edit)
        #endif
    }
}

/// 項目の左端にあるリマインダーのチェックの丸の幅（左の余白を含む）。ここのクリックは完了だけで、情報カードは出さない。
let checkCircleWidth: CGFloat = 24

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
    let card: ItemCardClick?
    let cardInset: CGFloat
    let edit: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        CatcherView()
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.select = select
        view.card = card
        view.cardInset = cardInset
        view.edit = edit
    }

    final class CatcherView: NSView {
        var select: (() -> Void)?
        var card: ItemCardClick?
        var cardInset: CGFloat = 0
        var edit: (() -> Void)?
        private var monitor: Any?
        /// 押した位置。離したときにカードを出すクリックなら入っている
        private var cardPress: CGPoint?
        /// 離したあと、ダブルクリックにならなかったら出すカード
        private var pendingOpen: DispatchWorkItem?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.rightMouseDown, .leftMouseDown, .leftMouseUp]
            ) { [weak self] event in
                guard let self else { return event }
                if event.type == .leftMouseUp {
                    self.openCardIfClicked(event)
                    return event
                }
                self.cardPress = nil
                // 次に押されたら、待っていたカードは出さない（ダブルクリックの 2 回目、別の項目のクリック）
                self.pendingOpen?.cancel()
                self.pendingOpen = nil
                guard self.catches(event) else { return event }
                // 選択すると、出ているカードは選択に付いてくる。出ていたかは先に見ておく
                let wasShowingCard = self.card?.isShowing() == true
                self.select?()
                let isSecondaryClick = event.type == .rightMouseDown || event.modifierFlags.contains(.control)
                // 左クリックは選択するだけで、そのまま下へ通す（ドラッグ・ダブルクリック・チェックの丸が受ける）
                guard isSecondaryClick else {
                    // カードは押したときに閉じ、離したときに出す。ドラッグとダブルクリック（新規登録）では出さない。
                    // カードの出ている項目のクリックは、閉じるだけ
                    self.card?.close()
                    let point = self.convert(event.locationInWindow, from: nil)
                    if !wasShowingCard, event.clickCount == 1, point.x >= self.cardInset {
                        self.cardPress = event.locationInWindow
                    }
                    return event
                }
                self.edit?()
                return nil
            }
        }

        /// 押した所からほとんど動かさずに離したら、ダブルクリックの間隔だけ待ってカードを出す。
        /// すぐ出すと、ダブルクリック（新規登録）の 1 回目でカードが一瞬出てしまう。
        private func openCardIfClicked(_ event: NSEvent) {
            guard let press = cardPress else { return }
            cardPress = nil
            let moved = hypot(event.locationInWindow.x - press.x, event.locationInWindow.y - press.y)
            guard let window, event.window === window, moved < 3 else { return }
            let open = DispatchWorkItem { [weak self] in
                self?.pendingOpen = nil
                self?.card?.open()
            }
            pendingOpen = open
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: open)
        }

        deinit {
            pendingOpen?.cancel()
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
