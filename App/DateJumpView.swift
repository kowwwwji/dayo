import DayoCore
import Observation
import SwiftUI

/// 日付ジャンプを開いているか。メニュー（`⌘g`）とボタンの両方から開くので、置き場所を 1 つにする。
/// 開いている間はタイムラインのキー操作を止める（ポップオーバーが前面を取れなかったとき、打った文字が項目の操作にならないように）。
@MainActor
@Observable
final class DateJumpRequest {
    var isPresented = false
}

/// 離れた日へ移るための小さな画面。日付を打って Return するか、月のカレンダーから日を選ぶ。
/// 表示モードは変えない。
struct DateJumpView: View {
    let model: TimelineModel
    let onClose: () -> Void
    @State private var text = ""
    @FocusState private var isFocused: Bool

    /// 入力欄の読み取り結果。読めなければ nil。
    private var typedDay: Date? {
        DateJump.day(from: text, reference: .now, calendar: .autoupdatingCurrent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("11/20、来週水曜、2026/11/1", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    if let typedDay { go(to: typedDay) }
                }
            Text(interpretation)
                .font(.dayoSmall)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            // 選んだ日へすぐ移る。月をめくるだけでは選択は変わらない
            DatePicker(
                "日付",
                selection: Binding(get: { model.day }, set: { go(to: $0) }),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            // 見出しや詳細編集と同じく、月と曜日は日本語で出す
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(minWidth: 240)
        // ポップオーバーが前面に出てからでないとフォーカスが入らないので、表示の次の周回で当てる
        .onAppear {
            DispatchQueue.main.async { isFocused = true }
        }
    }

    /// 入力欄の下に出す 1 行。Return でどこへ移るかを先に見せる。
    private var interpretation: String {
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            return "日付を入力して return、または日を選ぶ"
        }
        guard let typedDay else { return "日付として読めません" }
        return "\(TimelineTitle.text(for: typedDay, showsWeekNumber: false)) へ移動"
    }

    private func go(to day: Date) {
        Task { await model.show(day: day) }
        onClose()
    }
}
