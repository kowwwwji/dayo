import DayoCore
import Observation

/// 新規登録を開いた位置。登録のポップオーバーは、この位置に置いた仮の項目から出す。
/// ダブルクリック（時間軸・終日欄）もキー（`o` / `⇧o`）もここを通すので、開き方によらず同じ場所に仮の項目が出る。
@MainActor
@Observable
final class NewItemPlacement {
    /// 時間軸の仮の項目に付ける場所のキー。
    static let gridAnchor = "grid-new"
    /// 終日欄の仮のチップに付ける場所のキー。
    static let allDayAnchor = "allDay-new"

    private(set) var slot: NewItemSlot?

    func open(_ slot: NewItemSlot, with editing: ItemEditing) {
        self.slot = slot
        editing.openNew(at: slot.start, isAllDay: slot.isAllDay, anchor: slot.isAllDay ? Self.allDayAnchor : Self.gridAnchor)
    }

    /// 表示する日が変わったら、前の日の位置は忘れる。
    func reset() {
        slot = nil
    }
}
