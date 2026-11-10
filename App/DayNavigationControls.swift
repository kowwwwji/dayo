import DayoCore
import SwiftUI

/// 前日・翌日・今日へ移るボタン。指でもマウスでも押しやすいよう枠付きで大きめにする。
struct DayNavigationControls: View {
    let model: DayTimelineModel

    var body: some View {
        HStack(spacing: 6) {
            Button { Task { await model.showPreviousDay() } } label: {
                Image(systemName: "chevron.left")
                    .frame(minWidth: 20, minHeight: 20)
            }
            .accessibilityLabel("前の日")
            Button { Task { await model.showNextDay() } } label: {
                Image(systemName: "chevron.right")
                    .frame(minWidth: 20, minHeight: 20)
            }
            .accessibilityLabel("次の日")
            Button("今日") { Task { await model.showToday() } }
                .disabled(model.isToday)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}

extension DayTimelineModel {
    /// ウィンドウや画面のタイトルに出す表示中の日。
    var dayTitle: String {
        day.formatted(.dateTime.month().day().weekday(.wide))
    }
}
