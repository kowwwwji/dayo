import DayoCore
import SwiftUI

/// タイムラインの 1 行。予定はカレンダー色のバー、リマインダーは完了チェック。
struct TimelineRow: View {
    let item: TimelineItem
    var isOverdue = false
    let editing: ItemEditing
    /// エディタを開く場所のキー。同じ項目をほかの場所（グリッドや終日欄）にも出す画面で、そちらと区別する。
    var anchor: String?
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            leading
            // チェック以外の部分をタップで詳細編集
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    PriorityMark(priority: item.priority)
                    Text(item.title)
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    EarlyReminderMark(minutes: item.earlyReminderMinutes)
                }
                HStack(spacing: 6) {
                    if let time = timeText {
                        Text(time).foregroundStyle(isOverdue ? .red : .secondary)
                    }
                    Text(item.sourceName).foregroundStyle(.tertiary)
                }
                .font(.dayoSmall)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { editing.open(item, at: anchor) }
            .itemEditor(for: item, editing, at: anchor)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var leading: some View {
        switch item.kind {
        case .event:
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(cgColor: item.color))
                .frame(width: 4, height: 30)
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

    private var timeText: String? {
        guard let start = item.start else { return nil }
        if isOverdue {
            return item.isAllDay
                ? start.formatted(.dateTime.month().day())
                : start.formatted(.dateTime.month().day().hour().minute())
        }
        if item.isAllDay { return "終日" }
        let startText = start.formatted(date: .omitted, time: .shortened)
        guard let end = item.end else { return startText }
        return "\(startText)–\(end.formatted(date: .omitted, time: .shortened))"
    }
}
