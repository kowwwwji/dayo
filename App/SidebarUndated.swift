#if os(macOS)
import DayoCore
import Observation
import SwiftUI

/// サイドバーからタイムラインへのドラッグの橋渡し。
/// サイドバーとタイムラインは別の列なので、タイムラインの中のドラッグ（`TimelineDragBoard`）では運べない。
/// OS のドラッグ＆ドロップで運び、何を掴んでいるかはここに置いておく（落とし先はドラッグ中に中身を読めないため）。
@MainActor
@Observable
final class UndatedDrag {
    /// 掴んでいるリマインダー。落とすか、次に掴むまで残る。
    private(set) var item: TimelineItem?
    /// ドラッグで運んでいる文字列。落とされたものが、掴んだものと同じかを確かめるのに使う。
    private(set) var text = ""

    /// ドラッグで運ぶ中身。タイトルの文字列なので、ほかのアプリへ落とせばタイトルが入る。
    /// 読み取り専用のリストのものは期日を付けられないので、何も運ばない。
    func begin(_ item: TimelineItem) -> NSItemProvider {
        guard item.isEditable else {
            end()
            return NSItemProvider()
        }
        self.item = item
        // 空の文字列は運べないので、タイトルの無いものは仮の名前にする
        text = item.title.isEmpty ? "リマインダー" : item.title
        return NSItemProvider(object: text as NSString)
    }

    func end() {
        item = nil
        text = ""
    }
}

/// サイドバーの「期日なし」。期日の無い未完了リマインダーは時間軸に置き場所が無いので、ここに並べる。
/// 行をタイムラインへドラッグすると、落とした日時が期日になる。
struct SidebarUndated: View {
    let model: TimelineModel
    let drag: UndatedDrag
    let makeEditor: @MainActor (TimelineItem) -> ItemEditorModel
    let makeNewEditor: @MainActor (Date, Bool) -> ItemEditorModel
    @State private var editor: ItemEditorModel?
    @State private var editorAnchor: String?

    /// エディタを開く場所のキー。
    private static let anchor = "undated"

    private var editing: ItemEditing {
        ItemEditing(editor: $editor, anchor: $editorAnchor, make: makeEditor, makeNew: makeNewEditor)
    }

    var body: some View {
        if !model.undated.isEmpty {
            Section {
                ForEach(model.undated) { item in
                    row(item)
                }
            } header: {
                HStack {
                    Text("期日なし")
                    Spacer(minLength: 0)
                    Text("\(model.undated.count)")
                        .monospacedDigit()
                }
                // 見出しは行より右へはみ出すので、件数が端で切れないよう寄せる
                .padding(.trailing, 8)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func row(_ item: TimelineItem) -> some View {
        HStack(spacing: 6) {
            Button {
                Task { await model.toggleCompleted(item) }
            } label: {
                Image(systemName: "circle")
                    .foregroundStyle(Color(cgColor: item.color))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("完了にする")
            // 丸以外。右クリックでの編集とドラッグはここで受ける
            HStack(spacing: 4) {
                PriorityMark(priority: item.priority)
                Text(item.title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onItemClick(select: {}) { editing.open(item, at: Self.anchor) }
            .itemEditor(for: item, editing, at: Self.anchor)
            .onDrag { drag.begin(item) }
        }
    }
}
#endif
