import DayoCore
import SwiftUI

/// 表示モード（日 | 週）の保存。起動時にモデルへ渡し、切り替えたら書き戻す。
enum TimelineModeSetting {
    static let key = "timelineMode"

    /// 週表示は当面 Mac のみ。iPhone は常に日表示。
    static var stored: TimelineMode {
        #if os(macOS)
        UserDefaults.standard.string(forKey: key).flatMap(TimelineMode.init(rawValue:)) ?? .day
        #else
        .day
        #endif
    }
}

/// 日 | 週 の切替（Mac のみ）と、前後・今日へ移るボタン。指でもマウスでも押しやすいよう枠付きで大きめにする。
/// 「今日」は今日を含まない範囲を見ているときだけ ‹ › の左に現れる。‹ › は右端に固定して位置が変わらないようにする。
struct DayNavigationControls: View {
    let model: TimelineModel
    @AppStorage(TimelineModeSetting.key) private var storedMode = TimelineMode.day

    private var unit: String { model.mode == .week ? "週" : "日" }

    var body: some View {
        HStack(spacing: 6) {
            #if os(macOS)
            Picker("表示", selection: Binding(
                get: { model.mode },
                set: { mode in
                    storedMode = mode
                    Task { await model.setMode(mode) }
                }
            )) {
                Text("日").tag(TimelineMode.day)
                Text("週").tag(TimelineMode.week)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            #endif
            if !model.containsToday {
                Button("今日") { Task { await model.showToday() } }
            }
            Button { Task { await model.showPrevious() } } label: {
                Image(systemName: "chevron.left")
                    .frame(minWidth: 20, minHeight: 20)
            }
            .accessibilityLabel("前の\(unit)")
            Button { Task { await model.showNext() } } label: {
                Image(systemName: "chevron.right")
                    .frame(minWidth: 20, minHeight: 20)
            }
            .accessibilityLabel("次の\(unit)")
        }
        .animation(.default, value: model.containsToday)
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}

/// ウィンドウや画面のタイトルに出す日付。日表示は「2026 / 11 / 10 (火) W46」、週表示は「2026 / 11  W46」の形。
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

    /// 週表示のタイトル。年月は週の最初の日のもの。
    /// 週番号は週の中の木曜で決める（ISO の週は木曜が属する週。日曜始まりの週でも月〜土と同じ番号になる）。
    static func text(forWeek days: [Date], showsWeekNumber: Bool) -> String {
        guard let first = days.first else { return "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let parts = calendar.dateComponents([.year, .month], from: first)
        var text = "\(parts.year ?? 0) / \(parts.month ?? 0)"
        if showsWeekNumber {
            let thursday = days.first { calendar.component(.weekday, from: $0) == 5 } ?? first
            text += "  W\(Calendar(identifier: .iso8601).component(.weekOfYear, from: thursday))"
        }
        return text
    }
}
