import DayoCore
import SwiftUI

@main
struct DayoApp: App {
    @State private var model: TimelineModel
    @State private var quickInput: QuickInputModel
    @State private var quickInputFocus = QuickInputFocus()
    private let source = EventKitRepository()

    init() {
        let timeline = TimelineModel(source: source, mode: TimelineModeSetting.stored)
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

    /// 新規登録のモデル。種別は直近に登録したものから始め、登録できたら覚え直す
    private func makeNewEditor(start: Date, isAllDay: Bool) -> ItemEditorModel {
        let defaults = UserDefaults.standard
        let editor = ItemEditorModel(
            newItemOf: defaults.string(forKey: Self.lastCreatedKindKey) == "reminder" ? .reminder : .event,
            start: start,
            isAllDay: isAllDay,
            defaultEarlyReminderMinutes: defaults.object(forKey: EarlyReminderSetting.key) as? Int
                ?? EarlyReminderSetting.defaultMinutes,
            source: source
        )
        let timeline = model
        editor.onChanged = { [weak editor] in
            if let kind = editor?.kind {
                defaults.set(kind == .reminder ? "reminder" : "event", forKey: Self.lastCreatedKindKey)
            }
            await timeline.load()
        }
        return editor
    }

    private static let lastCreatedKindKey = "lastCreatedKind"

    var body: some Scene {
        WindowGroup {
            RootView(
                model: model,
                quickInput: quickInput,
                quickInputFocus: quickInputFocus,
                makeEditor: makeEditor(for:),
                makeNewEditor: makeNewEditor(start:isAllDay:)
            )
        }
        #if os(macOS)
        .commands {
            TimelineCommands(model: model, quickInputFocus: quickInputFocus)
        }
        #endif
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
