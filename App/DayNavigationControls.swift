import DayoCore
import SwiftUI

/// 前日・翌日・今日へ移るボタン。指でもマウスでも押しやすいよう枠付きで大きめにする。
/// 「今日」は今日以外を見ているときだけ ‹ › の左に現れる。‹ › は右端に固定して位置が変わらないようにする。
struct DayNavigationControls: View {
    let model: DayTimelineModel

    var body: some View {
        HStack(spacing: 6) {
            if !model.isToday {
                Button("今日") { Task { await model.showToday() } }
            }
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
        }
        .animation(.default, value: model.isToday)
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}

/// ウィンドウや画面のタイトルに出す日付。「2026 / 11 / 10 (火) W46」の形。
/// 年は西暦（システムが和暦でも）。週番号は ISO 8601（月曜始まり）。設定で消せる。
enum DayTitle {
    static let showsWeekNumberKey = "showsWeekNumber"

    static func text(for day: Date, showsWeekNumber: Bool) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        let weekday = day.formatted(.dateTime.weekday(.narrow).locale(Locale(identifier: "ja_JP")))
        var text = "\(parts.year ?? 0) / \(parts.month ?? 0) / \(parts.day ?? 0) (\(weekday))"
        if showsWeekNumber {
            let week = Calendar(identifier: .iso8601).component(.weekOfYear, from: day)
            text += " W\(week)"
        }
        return text
    }
}
