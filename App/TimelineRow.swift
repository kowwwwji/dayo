import DayoCore
import SwiftUI

/// 期限切れ欄の 1 行。予定はカレンダー色のバー、リマインダーは完了チェック。
/// 日時とリスト名はタイトルの横に並べる。幅が足りなければタイトルのほうを省略する。
struct TimelineRow: View {
    let item: TimelineItem
    let editing: ItemEditing
    /// エディタを開く場所のキー。同じ項目をほかの場所（グリッドや終日欄）にも出す画面で、そちらと区別する。
    var anchor: String?
    /// キー操作で選択中か
    var isSelected = false
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            leading
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                PriorityMark(priority: item.priority)
                Text(item.title)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .lineLimit(1)
                EarlyReminderMark(minutes: item.earlyReminderMinutes)
                HStack(spacing: 6) {
                    if let time = timeText {
                        Text(time).foregroundStyle(.red)
                    }
                    Text(item.sourceName).foregroundStyle(.tertiary)
                }
                .font(.dayoSmall)
                .lineLimit(1)
                .padding(.leading, 4)
                .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onEditGesture { editing.open(item, at: anchor) }
            .itemEditor(for: item, editing, at: anchor)
        }
        .padding(.vertical, 2)
        .selectionRing(isSelected)
    }

    @ViewBuilder
    private var leading: some View {
        switch item.kind {
        case .event:
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(cgColor: item.color))
                .frame(width: 4, height: 18)
        case .reminder:
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(Color(cgColor: item.color))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "未完了に戻す" : "完了にする")
        }
    }

    /// 期日。期限切れは今日より前なので日付から書く。
    private var timeText: String? {
        guard let start = item.start else { return nil }
        return item.isAllDay
            ? start.formatted(.dateTime.month().day())
            : start.formatted(.dateTime.month().day().hour().minute())
    }
}

extension View {
    /// キー操作で選択中の項目を示すアクセント色の枠。
    func selectionRing(_ isSelected: Bool) -> some View {
        overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
    }
}
