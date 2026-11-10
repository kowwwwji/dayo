import SwiftUI

struct SettingsView: View {
    @AppStorage(TimelineStyle.storageKey) private var style: TimelineStyle = .grid

    var body: some View {
        Form {
            TimelineStylePicker(style: $style)
                .pickerStyle(.inline)
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .padding()
    }
}
