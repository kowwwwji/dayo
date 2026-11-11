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
/// カレンダーのボタンは日付ジャンプを開く。
/// 「今日」は押すと表示が動くとき（今日を含まない範囲、3 日表示なら今日が左端でないとき）だけ ‹ › の左に現れる。‹ › は右端に固定して位置が変わらないようにする。
struct DayNavigationControls: View {
    let model: TimelineModel
    /// キー操作から日付ジャンプを開く入口。iPhone には無い
    var dateJump: DateJumpRequest?

    @State private var showsDateJump = false
    /// 「更新中」を出しているか。変更がすぐ届いても押したことが分かるよう、少しのあいだ残す
    @State private var showsRefreshing = false

    /// 前後に動く単位（ボタンの読み上げ用）。
    private var unit: String {
        switch model.mode {
        case .day: "日"
        case .threeDays: "3日"
        case .week: "週"
        }
    }

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
            if let deletion = model.pendingDeletion {
                deletionNotice(deletion)
            }
            if !model.isAlignedWithToday {
                Button("今日") { Task { await model.showToday() } }
            }
            Button { showsDateJump = true } label: {
                Image(systemName: "calendar")
                    .frame(minWidth: 20, minHeight: 20)
            }
            .accessibilityLabel("日付へ移動")
            .help("日付へ移動（g）")
            .popover(isPresented: $showsDateJump, arrowEdge: .bottom) {
                DateJumpView(model: model) { showsDateJump = false }
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
        .animation(.default, value: model.pendingDeletion?.item.id)
        .onChange(of: dateJump?.requests) { showsDateJump = true }
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

extension DayNavigationControls {
    /// 削除して保留にしている間の通知。実際に消すまでの間は取り消せることを知らせる。
    private func deletionNotice(_ deletion: PendingDeletion) -> some View {
        HStack(spacing: 8) {
            // 長いタイトルは途中を省く。「削除しました」と取り消し方は必ず読めるようにする
            Text("「\(deletion.item.title)」を削除しました")
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 220, alignment: .trailing)
            #if os(macOS)
            Text("⌘z で取り消し")
                .lineLimit(1)
                .fixedSize()
            #else
            // iPhone にはキーが無いので、ここから取り消す
            Button("取り消す") { Task { await model.undo() } }
                .controlSize(.small)
            #endif
        }
        .font(.dayoSmall)
        .foregroundStyle(.secondary)
        // 入力欄に押されて折り返さないよう、通知は自分の幅を保つ（縮むのは入力欄の側）
        .fixedSize()
        .padding(.trailing, 4)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }
}

/// タイトルの週番号を出すかの保存。タイトルの組み立ては `TimelineTitle`。
enum DayTitle {
    static let showsWeekNumberKey = "showsWeekNumber"
}
