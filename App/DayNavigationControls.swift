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

    /// 更新の表示。変更がすぐ届いても押したことが分かるよう「更新中」は少しのあいだ残し、
    /// 変更が届かなかったときの知らせも数秒で消す
    private enum RefreshNotice { case refreshing, failed }
    @State private var refreshNotice: RefreshNotice?

    /// 前後に動く単位。3 日表示も 1 日ずつ動く。
    private var unit: String { model.mode == .week ? "週" : "日" }

    var body: some View {
        HStack(spacing: 6) {
            if let refreshNotice {
                HStack(spacing: 4) {
                    if refreshNotice == .refreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(refreshNotice == .refreshing ? "更新中" : "更新できません")
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
        .animation(.default, value: refreshNotice)
        .onChange(of: model.refreshState) { _, state in
            switch state {
            case .refreshing:
                refreshNotice = .refreshing
            case .idle:
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    if model.refreshState == .idle { refreshNotice = nil }
                }
            case .timedOut:
                refreshNotice = .failed
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    if model.refreshState == .timedOut { refreshNotice = nil }
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
