import DayoCore
import SwiftUI

/// 早期リマインダーの設定キーと既定値。
enum EarlyReminderSetting {
    static let key = "defaultEarlyReminderMinutes"
    /// 0 = なし。
    static let defaultMinutes = 0
}

/// 早期リマインダーの選択肢。分の数値を `@AppStorage` やモデルと直接やり取りする。
/// 選択肢に無い値（純正アプリで付けた 45 分前など）はその値のまま出す。
struct EarlyReminderPicker: View {
    let title: String
    @Binding var minutes: Int

    init(_ title: String, minutes: Binding<Int>) {
        self.title = title
        _minutes = minutes
    }

    private var options: [EarlyReminder] {
        let current = EarlyReminder(minutes: minutes)
        return EarlyReminder.presets.contains(current) ? EarlyReminder.presets : EarlyReminder.presets + [current]
    }

    var body: some View {
        Picker(title, selection: $minutes) {
            ForEach(options, id: \.self) { option in
                Text(option.label).tag(option.minutes ?? 0)
            }
        }
    }
}

/// 早期リマインダーが付いている項目に出す小さなベル。
struct EarlyReminderMark: View {
    let minutes: Int?

    var body: some View {
        if let minutes, minutes > 0 {
            Image(systemName: "bell")
                .font(.dayoDetail)
                .foregroundStyle(.secondary)
                .accessibilityLabel(EarlyReminder(minutes: minutes).label)
        }
    }
}
