import DayoCore
import SwiftUI

/// プラットフォームごとの外枠。Mac はサイドバー付きウィンドウ、iPhone はタブ。
/// クイック入力は Mac では上部、iPhone では下部に常設する。
struct RootView: View {
    let model: TimelineModel
    let quickInput: QuickInputModel
    var quickInputFocus: QuickInputFocus?
    /// メニュー（⌘g）からも開くので、アプリ側が持つものを受け取る。無ければ自前のものを使う
    var dateJumpRequest: DateJumpRequest?
    @State private var ownDateJump = DateJumpRequest()
    private var dateJump: DateJumpRequest { dateJumpRequest ?? ownDateJump }
    let makeEditor: @MainActor (TimelineItem) -> ItemEditorModel
    let makeNewEditor: @MainActor (Date, Bool) -> ItemEditorModel
    @AppStorage(DayTitle.showsWeekNumberKey) private var showsWeekNumber = true
    #if os(macOS)
    @AppStorage(SidebarSetting.hiddenKey) private var sidebarHidden = false
    @State private var undatedDrag = UndatedDrag()
    #endif

    private var title: String {
        switch model.mode {
        case .day: TimelineTitle.text(for: model.day, showsWeekNumber: showsWeekNumber)
        case .threeDays: TimelineTitle.text(forDays: model.days, showsWeekNumber: showsWeekNumber)
        case .week: TimelineTitle.text(forWeek: model.days, showsWeekNumber: showsWeekNumber)
        }
    }

    var body: some View {
        #if os(macOS)
        NavigationSplitView(columnVisibility: Binding(
            get: { sidebarHidden ? .detailOnly : .all },
            set: { sidebarHidden = $0 == .detailOnly }
        )) {
            VStack(spacing: 0) {
            // 表示（日 / 3 日 / 週）と、出すカレンダーをここで切り替える
            List(selection: Binding<TimelineMode?>(
                get: { model.mode },
                set: { mode in
                    if let mode { TimelineModeSetting.set(mode, on: model) }
                }
            )) {
                Label("日表示", systemImage: "sun.max").tag(TimelineMode.day)
                Label("3日表示", systemImage: "rectangle.split.3x1").tag(TimelineMode.threeDays)
                Label("週表示", systemImage: "calendar").tag(TimelineMode.week)
                // 見なくてよいカレンダーを隠して、列の幅を空ける
                SidebarCalendars(model: model)
            }
            // 時間軸に載らない期日なしのリマインダー。ここからタイムラインへドラッグして期日を付ける。
            // `List` の行にすると、ドラッグで出ていった行が戻ってきても次のクリックまで描かれないので、`List` の外に置く
            SidebarUndated(
                model: model, drag: undatedDrag, makeEditor: makeEditor, makeNewEditor: makeNewEditor
            )
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 200)
        } detail: {
            VStack(spacing: 0) {
                // 日付の移動は入力欄と同じ行の右端に置く。日付そのものはウィンドウタイトルに出す
                QuickInputBar(model: quickInput, focus: quickInputFocus) {
                    DayNavigationControls(model: model, dateJump: dateJump)
                }
                Divider()
                DayTimelineView(
                    model: model, makeEditor: makeEditor, makeNewEditor: makeNewEditor, dateJump: dateJump,
                    undatedDrag: undatedDrag
                )
            }
            .navigationTitle(title)
        }
        #else
        TabView {
            NavigationStack {
                DayTimelineView(model: model, makeEditor: makeEditor, makeNewEditor: makeNewEditor)
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                    QuickInputBar(model: quickInput)
                }
            }
            .tabItem { Label("今日", systemImage: "sun.max") }
        }
        #endif
    }
}
