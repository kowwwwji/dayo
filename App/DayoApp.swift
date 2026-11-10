import DayoCore
import SwiftUI

@main
struct DayoApp: App {
    @State private var model: DayTimelineModel
    @State private var quickInput: QuickInputModel

    init() {
        let source = EventKitRepository()
        let timeline = DayTimelineModel(source: source)
        let quickInput = QuickInputModel(source: source)
        // 変更通知でも反映されるが、自分の登録は待たずに読み直す
        quickInput.onCreated = { await timeline.load() }
        _model = State(initialValue: timeline)
        _quickInput = State(initialValue: quickInput)
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model, quickInput: quickInput)
        }
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
