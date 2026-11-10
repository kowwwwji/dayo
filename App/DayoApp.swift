import DayoCore
import SwiftUI

@main
struct DayoApp: App {
    @State private var model = DayTimelineModel(source: EventKitRepository())

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
