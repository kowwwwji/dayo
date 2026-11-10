import SwiftUI

/// 今日タイムラインの中央部分の見た目。`@AppStorage(TimelineStyle.storageKey)` で保存する。
enum TimelineStyle: String, CaseIterable, Identifiable {
    /// Apple カレンダーの日表示のような時間軸グリッド。
    case grid
    /// 時刻順のリスト。
    case list

    static let storageKey = "timelineStyle"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .grid: "時間軸"
        case .list: "リスト"
        }
    }

    var symbol: String {
        switch self {
        case .grid: "calendar.day.timeline.left"
        case .list: "list.bullet"
        }
    }
}

struct TimelineStylePicker: View {
    @Binding var style: TimelineStyle

    var body: some View {
        Picker("表示", selection: $style) {
            ForEach(TimelineStyle.allCases) { style in
                Label(style.label, systemImage: style.symbol).tag(style)
            }
        }
    }
}
