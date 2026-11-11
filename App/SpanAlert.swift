#if os(macOS)
import AppKit
import DayoCore

/// 繰り返しの予定を変える・消す前に、どの回に及ぶかを聞く（Mac）。
/// SwiftUI の確認ダイアログは最初のフォーカスを選べず、キーボード操作をオンにしていると「キャンセル」に枠が付くのに
/// return は「この回のみ」に効く。枠と return の行き先を揃えるため、AppKit のダイアログで「この回のみ」に置く。
@MainActor
enum SpanAlert {
    /// 選んだ範囲を `completion` へ渡す。キャンセルなら nil。ウインドウが無ければ出さずに false を返す。
    @discardableResult
    static func present(message: String, completion: @escaping @MainActor (EditSpan?) -> Void) -> Bool {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return false }
        let alert = NSAlert()
        alert.messageText = "繰り返しの予定です"
        alert.informativeText = message
        let thisOnly = alert.addButton(withTitle: "この回のみ")
        alert.addButton(withTitle: "以降すべて")
        let cancel = alert.addButton(withTitle: "キャンセル")
        cancel.keyEquivalent = "\u{1b}"
        alert.window.initialFirstResponder = thisOnly
        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn: completion(.thisOccurrence)
            case .alertSecondButtonReturn: completion(.futureOccurrences)
            default: completion(nil)
            }
        }
        return true
    }
}
#endif
