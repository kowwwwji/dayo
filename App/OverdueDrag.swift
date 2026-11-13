#if os(macOS)
import DayoCore
import SwiftUI

/// 期限切れ欄の行のドラッグ。時間軸へ落とすとその日時、終日欄へ落とすとその日を新しい期日にする。
/// 期限切れ欄は内側でスクロールして行が欄の外へ出られないので、行は動かさず、行き先は影（`TimelineDragBoard.ghost`）で見せる。
struct OverdueDragModifier: ViewModifier {
    let item: TimelineItem
    let board: TimelineDragBoard
    /// 落とした日（その日の 0:00）と開始分。終日欄なら開始分は nil
    let onDrop: (Date, Int?) -> Void

    @GestureState private var isDragging = false

    private enum Target {
        case timed(day: Date, minute: Int)
        case allDay(day: Date)

        var label: String {
            switch self {
            case .timed(_, let minute): timeText(minute: minute)
            case .allDay: "終日"
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .opacity(isDragging ? 0.4 : 1)
            .gesture(item.isEditable ? moveGesture : nil)
            .onChange(of: isDragging) { _, dragging in
                if !dragging { board.ghost = nil }
            }
    }

    private func target(at point: CGPoint) -> Target? {
        if let day = board.allDayTarget(at: point) { return .allDay(day: day) }
        // リマインダーには長さが無い
        return board.gridTarget(at: point, duration: 1).map { .timed(day: $0.day, minute: $0.minute) }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(TimelineDragBoard.space))
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { value in
                board.ghost = target(at: value.location).map { target in
                    TimelineDragBoard.Ghost(
                        title: item.title, color: item.color, label: target.label, location: value.location
                    )
                }
            }
            .onEnded { value in
                board.ghost = nil
                switch target(at: value.location) {
                case .timed(let day, let minute): onDrop(day, minute)
                case .allDay(let day): onDrop(day, nil)
                case nil: break
                }
            }
    }
}
#endif
