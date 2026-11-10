import SwiftUI

struct SettingsView: View {
    @AppStorage(TimelineStyle.storageKey) private var style: TimelineStyle = .grid
    @AppStorage(DayHours.startKey) private var startHour = DayHours.defaultStart
    @AppStorage(DayHours.endKey) private var endHour = DayHours.defaultEnd

    var body: some View {
        Form {
            TimelineStylePicker(style: $style)
                .pickerStyle(.inline)
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
