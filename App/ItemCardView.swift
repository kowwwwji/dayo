import DayoCore
import SwiftUI

/// 情報カードを出している項目と場所。場所のキーは編集ポップオーバーと同じもの（同じ項目が複数の場所に出るため）。
struct ItemCardTarget: Equatable {
    let itemID: String
    let anchor: String?
}

/// 情報カードの状態。出せるカードは 1 つ。
@MainActor
@Observable
final class ItemCards {
    private(set) var target: ItemCardTarget?
    /// ポップオーバーが自分で閉じたカードと、その時刻
    @ObservationIgnored private var dismissal: (target: ItemCardTarget, at: Date)?

    func show(_ target: ItemCardTarget) {
        self.target = target
    }

    func close() {
        target = nil
    }

    /// ポップオーバーが自分で閉じた（カードの外をクリックした）。
    func popoverClosed(_ target: ItemCardTarget) {
        guard self.target == target else { return }
        self.target = nil
        dismissal = (target, .now)
    }

    /// その項目のカードを出しているか、たったいまポップオーバーが閉じたところか。
    /// カードを出している項目をクリックすると、ポップオーバーが先に閉じてからクリックが届くことがある。
    /// それを「出ていない」と見て出し直さないよう、閉じた直後も出ているものとして扱う。
    func isShowingOrJustClosed(_ target: ItemCardTarget) -> Bool {
        if self.target == target { return true }
        guard let dismissal, dismissal.target == target else { return false }
        return Date.now.timeIntervalSince(dismissal.at) < 0.3
    }
}

/// 情報カードを出す画面が、項目のビューへ渡すもの。
struct ItemCardContext {
    let cards: ItemCards
    let onToggle: (TimelineItem) -> Void
    let onDelete: (TimelineItem) -> Void
}

/// 項目のクリックでカードを出す / 閉じるための操作。
struct ItemCardClick {
    let isShowing: () -> Bool
    let open: () -> Void
    let close: () -> Void
}

#if os(macOS)
/// 項目の情報カード。中身を見るだけで、書き換える欄は無い（直すのは鉛筆から開く詳細編集）。
struct ItemCardView: View {
    let item: TimelineItem
    let onEdit: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    private var color: Color { Color(cgColor: item.color) }

    var body: some View {
        let summary = ItemSummary(item)
        VStack(alignment: .leading, spacing: 8) {
            header
            VStack(alignment: .leading, spacing: 6) {
                if let text = summary.dateText {
                    row("clock") { Text(text) }
                }
                if let text = summary.recurrenceText {
                    row("repeat") { Text(text) }
                }
                if item.priority != .none {
                    row("flag") {
                        HStack(spacing: 4) {
                            Text("優先度 \(item.priority.label)")
                            PriorityMark(priority: item.priority)
                        }
                    }
                }
                if let minutes = item.earlyReminderMinutes, minutes > 0 {
                    row("bell") { Text("\(EarlyReminder(minutes: minutes).label)に通知") }
                }
                if let location = summary.location, let url = summary.locationMapURL {
                    row("mappin.and.ellipse") {
                        Link(destination: url) {
                            Text(location)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .help("Google マップで開く")
                        .accessibilityLabel("\(location) を Google マップで開く")
                    }
                }
                if let url = summary.linkURL {
                    row("link") {
                        Link(destination: url) {
                            Text(url.absoluteString)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .help(url.absoluteString)
                    }
                }
                if let url = summary.conferenceURL {
                    row("video") {
                        Link("ビデオ会議に参加", destination: url)
                    }
                }
                row(item.kind == .event ? "calendar" : "list.bullet") {
                    Text(item.sourceName)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.dayoTitle)
            if let notes = summary.notes {
                Divider()
                Text(notes)
                    .font(.dayoSmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .background(CardWindowReader())
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            switch item.kind {
            case .event:
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 4, height: 16)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
            case .reminder:
                Button(action: onToggle) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(color)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel(item.isCompleted ? "未完了に戻す" : "完了にする")
            }
            Text(item.title)
                .font(.system(size: 15, weight: .semibold))
                .strikethrough(item.isCompleted)
                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .help("編集")
                .accessibilityLabel("編集")
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .help("削除")
                .accessibilityLabel("削除")
                .disabled(!item.isEditable)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .foregroundStyle(.secondary)
        }
    }

    /// 1 行。左に小さな印、右に中身。
    private func row(_ symbol: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.dayoDetail)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// いま出ている情報カードのウインドウ。カードはポップオーバー（別のウインドウ）に出るので、
/// そこへ届いたキーをタイムラインのキー操作として受けるために覚えておく。
@MainActor
enum ItemCardWindow {
    static weak var current: NSWindow?
}

private struct CardWindowReader: NSViewRepresentable {
    func makeNSView(context: Context) -> ReaderView {
        ReaderView()
    }

    func updateNSView(_ view: ReaderView, context: Context) {}

    final class ReaderView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { ItemCardWindow.current = window }
        }
    }
}
#endif
