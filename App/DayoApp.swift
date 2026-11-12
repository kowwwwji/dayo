import DayoCore
import SwiftUI

@main
struct DayoApp: App {
    @State private var model: TimelineModel
    @State private var quickInput: QuickInputModel
    @State private var quickInputFocus = QuickInputFocus()
    @State private var dateJump = DateJumpRequest()
    private let source: CalendarSource = Self.makeSource()
    #if os(macOS)
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    #endif

    init() {
        let timeline = TimelineModel(
            source: source, mode: TimelineModeSetting.stored, hiddenCalendarIDs: CalendarVisibilitySetting.stored
        )
        let quickInput = QuickInputModel(source: source)
        // 変更通知でも反映されるが、自分の登録は待たずに読み直す
        quickInput.onCreated = { await timeline.load() }
        _model = State(initialValue: timeline)
        #if os(macOS)
        AppDelegate.timeline = timeline
        #endif
        _quickInput = State(initialValue: quickInput)
    }

    /// 詳細編集のモデル。保存後はタイムラインを読み直す。削除はタイムラインへ任せる（取り消せる間を置くため）
    private func makeEditor(for item: TimelineItem) -> ItemEditorModel {
        let editor = ItemEditorModel(item: item, source: source)
        let timeline = model
        editor.onChanged = { await timeline.load() }
        editor.onDelete = { await timeline.delete($0, span: $1) }
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
            let draft = editor?.draft
            if let draft {
                defaults.set(draft.kind == .reminder ? "reminder" : "event", forKey: Self.lastCreatedKindKey)
            }
            await timeline.load()
            // 続けて o で後ろに足せるよう、登録した項目を選ぶ
            if let draft, let start = draft.start { timeline.selectCreated(title: draft.title, start: start) }
        }
        return editor
    }

    private static let lastCreatedKindKey = "lastCreatedKind"

    /// 起動引数 `-demo YES` なら架空の中身を出す（App Store のスクリーンショット用）。提出するビルドには入らない。
    private static func makeSource() -> CalendarSource {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "demo") { return DemoSource() }
        #endif
        return EventKitRepository()
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                model: model,
                quickInput: quickInput,
                quickInputFocus: quickInputFocus,
                dateJumpRequest: dateJump,
                makeEditor: makeEditor(for:),
                makeNewEditor: makeNewEditor(start:isAllDay:)
            )
        }
        #if os(macOS)
        .commands {
            TimelineCommands(model: model, quickInputFocus: quickInputFocus, dateJump: dateJump)
        }
        #endif
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
