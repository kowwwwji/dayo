import DayoCore
import SwiftUI

/// プラットフォームごとの外枠。Mac はサイドバー付きウィンドウ、iPhone はタブ。
struct RootView: View {
    let model: DayTimelineModel

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            // TODO: フェーズ4以降でリマインダーリストの一覧に置き換える
            List {
                Label("今日", systemImage: "sun.max")
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 200)
        } detail: {
            DayTimelineView(model: model)
        }
        #else
        TabView {
            DayTimelineView(model: model)
                .tabItem { Label("今日", systemImage: "sun.max") }
        }
        #endif
    }
}
