import SwiftUI

/// 表示の切替（時間軸／リスト）はヘッダーにあるので、ここには置かない。
struct SettingsView: View {
    @AppStorage(DayHours.startKey) private var startHour = DayHours.defaultStart
    @AppStorage(DayHours.endKey) private var endHour = DayHours.defaultEnd
    @AppStorage(DayTitle.showsWeekNumberKey) private var showsWeekNumber = true
    @AppStorage(EarlyReminderSetting.key) private var defaultEarlyReminder = EarlyReminderSetting.defaultMinutes

    var body: some View {
        Form {
            Section("日付") {
                Toggle("週番号を表示", isOn: $showsWeekNumber)
            }
            Section {
                EarlyReminderPicker("既定の早期リマインダー", minutes: $defaultEarlyReminder)
            } header: {
                Text("リマインダー")
            } footer: {
                Text("クイック入力で時刻付きのリマインダーを登録したとき、この分だけ前にも通知します。")
            }
            Section {
                DayHoursPicker(startHour: $startHour, endHour: $endHour)
            } header: {
                Text("表示時間帯")
            } footer: {
                Text("この範囲の外に予定もリマインダーも無いときは、時間軸でその時間帯を 1 本の帯に畳みます。")
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(width: 360)
        .padding()
        #endif
    }
}
