import DayoCore
import SwiftUI

@main
struct DayoApp: App {
    @State private var model: DayTimelineModel
    @State private var quickInput: QuickInputModel
    private let source = EventKitRepository()

    init() {
        let timeline = DayTimelineModel(source: source)
        let quickInput = QuickInputModel(source: source)
        // 変更通知でも反映されるが、自分の登録は待たずに読み直す
        quickInput.onCreated = { await timeline.load() }
        _model = State(initialValue: timeline)
        _quickInput = State(initialValue: quickInput)
    }

    /// 詳細編集のモデル。保存・削除後はタイムラインを読み直す
    private func makeEditor(for item: TimelineItem) -> ItemEditorModel {
        let editor = ItemEditorModel(item: item, source: source)
        let timeline = model
        editor.onChanged = { await timeline.load() }
        return editor
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model, quickInput: quickInput, makeEditor: makeEditor(for:))
        }
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
