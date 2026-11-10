import DayoCore
import SwiftUI

/// プラットフォームごとの外枠。Mac はサイドバー付きウィンドウ、iPhone はタブ。
/// クイック入力は Mac では上部、iPhone では下部に常設する。
struct RootView: View {
    let model: TimelineModel
    let quickInput: QuickInputModel
    let makeEditor: @MainActor (TimelineItem) -> ItemEditorModel
    @AppStorage(DayTitle.showsWeekNumberKey) private var showsWeekNumber = true

    private var title: String {
        switch model.mode {
        case .day: DayTitle.text(for: model.day, showsWeekNumber: showsWeekNumber)
        case .week: DayTitle.text(forWeek: model.days, showsWeekNumber: showsWeekNumber)
        }
    }

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            // TODO: フェーズ4以降でリマインダーリストの一覧に置き換える
            List {
                Label("今日", systemImage: "sun.max")
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 200)
        } detail: {
            VStack(spacing: 0) {
                // 日 | 週 の切替と日付の移動は入力欄と同じ行の右端に置く。日付そのものはウィンドウタイトルに出す
                QuickInputBar(model: quickInput) {
                    DayNavigationControls(model: model)
                }
                Divider()
                DayTimelineView(model: model, makeEditor: makeEditor)
            }
            .navigationTitle(title)
        }
        #else
        TabView {
            NavigationStack {
                DayTimelineView(model: model, makeEditor: makeEditor)
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
