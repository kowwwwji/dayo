#if os(macOS)
import AppKit
import DayoCore

/// 繰り返しの予定を変える・消す前に、どの回に及ぶかを聞く（Mac）。
/// SwiftUI の確認ダイアログは最初のフォーカスを選べず、キーボード操作をオンにしていると「キャンセル」に枠が付くのに
/// return は「この回のみ」に効く。枠と return の行き先を揃えるため、AppKit のダイアログで「この回のみ」に置く。
@MainActor
enum SpanAlert {
    /// 聞いて、選んだ範囲を `completion` へ渡す。キャンセルなら nil。
    /// キー操作やドラッグの処理の途中から呼ばれるので、その処理を抜けてから出す。
    static func present(message: String, completion: @escaping @MainActor (EditSpan?) -> Void) {
        DispatchQueue.main.async {
            completion(ask(message: message))
        }
    }

    /// 聞いて、選んだ範囲を返す。キャンセルなら nil。
    /// どこから聞いても同じ見た目になるよう、ウインドウに付けない独立したダイアログで出す
    /// （詳細編集のポップオーバーにはシートを付けられないため、付ける形では揃えられない）。
    static func ask(message: String) -> EditSpan? {
        let (alert, monitor) = make(message: message)
        defer {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        return span(for: alert.runModal())
    }

    private static func make(message: String) -> (alert: NSAlert, monitor: Any?) {
        let alert = NSAlert()
        alert.messageText = "繰り返しの予定です"
        alert.informativeText = message
        let thisOnly = alert.addButton(withTitle: "この回のみ")
        alert.addButton(withTitle: "以降すべて")
        let cancel = alert.addButton(withTitle: "キャンセル")
        cancel.keyEquivalent = "\u{1b}"
        alert.window.initialFirstResponder = thisOnly
        // 標準では return は既定のボタンに効き、枠のあるボタンは space で押す。tab で枠を動かしたあとの return が
        // 別のボタンに効くと取り違えるので、ダイアログが出ている間だけキーを見て、return を枠のあるボタンに効かせる
        let panel = alert.window
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isReturn = event.keyCode == 36 || event.keyCode == 76
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard isReturn, modifiers.isEmpty, event.window === panel, let focused = panel.firstResponder as? NSButton
            else { return event }
            focused.performClick(nil)
            return nil
        }
        return (alert, monitor)
    }

    private static func span(for response: NSApplication.ModalResponse) -> EditSpan? {
        switch response {
        case .alertFirstButtonReturn: .thisOccurrence
        case .alertSecondButtonReturn: .futureOccurrences
        default: nil
        }
    }
}
#endif
