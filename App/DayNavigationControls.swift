import DayoCore
import SwiftUI

/// 表示モード（日 | 3 日 | 週）の保存。起動時にモデルへ渡し、切り替えたら書き戻す。
enum TimelineModeSetting {
    static let key = "timelineMode"

    /// 3 日表示と週表示は当面 Mac のみ。iPhone は常に日表示。
    static var stored: TimelineMode {
        #if os(macOS)
        UserDefaults.standard.string(forKey: key).flatMap(TimelineMode.init(rawValue:)) ?? .day
        #else
        .day
        #endif
    }

    /// 表示モードを切り替えて保存する。
    @MainActor
    static func set(_ mode: TimelineMode, on model: TimelineModel) {
        UserDefaults.standard.set(mode.rawValue, forKey: key)
        Task { await model.setMode(mode) }
    }
}

/// 前後・今日へ移るボタン。指でもマウスでも押しやすいよう枠付きで大きめにする。
/// 「今日」は押すと表示が動くとき（今日を含まない範囲、3 日表示なら今日が左端でないとき）だけ ‹ › の左に現れる。‹ › は右端に固定して位置が変わらないようにする。
struct DayNavigationControls: View {
    let model: TimelineModel

    /// 「更新中」を出しているか。読み直しは一瞬で終わるので、押したことが分かるよう少しのあいだ残す
    @State private var showsRefreshing = false

    /// 前後に動く単位。3 日表示も 1 日ずつ動く。
    private var unit: String { model.mode == .week ? "週" : "日" }

    var body: some View {
        HStack(spacing: 6) {
            if showsRefreshing {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("更新中")
                        .font(.dayoSmall)
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 4)
                .transition(.opacity)
                .accessibilityElement(children: .combine)
            }
            if !model.isAlignedWithToday {
                Button("今日") { Task { await model.showToday() } }
            }
            Button { Task { await model.showPrevious() } } label: {
                Image(systemName: "chevron.left")
                    .frame(minWidth: 20, minHeight: 20)
            }
            .accessibilityLabel("前の\(unit)")
            Button { Task { await model.showNext() } } label: {
                Image(systemName: "chevron.right")
                    .frame(minWidth: 20, minHeight: 20)
            }
            .accessibilityLabel("次の\(unit)")
        }
        .animation(.default, value: model.isAlignedWithToday)
        .animation(.default, value: showsRefreshing)
        .onChange(of: model.isRefreshing) { _, refreshing in
            if refreshing {
                showsRefreshing = true
            } else {
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    if !model.isRefreshing { showsRefreshing = false }
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}

/// タイトルの週番号を出すかの保存。タイトルの組み立ては `TimelineTitle`。
enum DayTitle {
    static let showsWeekNumberKey = "showsWeekNumber"
}
