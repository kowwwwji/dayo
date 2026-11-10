import DayoCore
import SwiftUI

/// 1 行入力と解釈チップ。Return で登録する。Mac は上部、iPhone は下部に常設する。
struct QuickInputBar: View {
    let model: QuickInputModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
                // 送信中も disabled にしない。フォーカスが外れて連続入力できなくなるため
                TextField("例: 明日 15時 歯医者 #家族", text: Bindable(model).text)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit { Task { await model.submit() } }
                if model.isSubmitting {
                    ProgressView().controlSize(.small)
                }
            }
            if let parsed = model.parsed {
                chips(for: parsed)
            }
            if let message = model.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func chips(for parsed: ParsedInput) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Chip(text: parsed.kind == .event ? "予定" : "リマインダー",
                     symbol: parsed.kind == .event ? "calendar" : "checklist")
                if let recurrence = parsed.recurrence {
                    Chip(text: RecurrenceText.describe(recurrence), symbol: "repeat")
                }
                if let date = parsed.date {
                    Chip(text: Self.dateText(date), symbol: "calendar.badge.clock")
                }
                if let time = parsed.time {
                    Chip(text: Self.timeText(time, end: parsed.endTime), symbol: "clock")
                }
                if let list = parsed.listName {
                    Chip(text: list, symbol: "list.bullet")
                }
            }
        }
    }

    private static func dateText(_ components: DateComponents) -> String {
        guard let date = Calendar.autoupdatingCurrent.date(from: components) else { return "" }
        return date.formatted(.dateTime.month().day().weekday(.abbreviated))
    }

    private static func timeText(_ time: DateComponents, end: DateComponents?) -> String {
        let start = String(format: "%d:%02d", time.hour ?? 0, time.minute ?? 0)
        guard let end else { return start }
        return "\(start)–\(String(format: "%d:%02d", end.hour ?? 0, end.minute ?? 0))"
    }
}

private struct Chip: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }
}

/// 繰り返し規則の日本語表現。
enum RecurrenceText {
    private static let weekdayNames = ["", "日", "月", "火", "水", "木", "金", "土"]

    static func describe(_ spec: RecurrenceSpec) -> String {
        switch spec.frequency {
        case .daily:
            return spec.interval == 1 ? "毎日" : "\(spec.interval)日ごと"
        case .weekly:
            let days = spec.weekdays.map { weekdayNames[$0] }.joined()
            if spec.weekdays == [2, 3, 4, 5, 6] { return "平日" }
            let prefix = spec.interval == 2 ? "隔週" : "毎週"
            return days.isEmpty ? prefix : "\(prefix)\(days)曜"
        case .monthly:
            if !spec.daysOfMonth.isEmpty {
                return "毎月" + spec.daysOfMonth.map { "\($0)日" }.joined(separator: "・")
            }
            guard let weekday = spec.weekdays.first, let week = spec.weekOfMonth else { return "毎月" }
            let ordinal = week == -1 ? "最終" : "第\(week)"
            return "毎月\(ordinal)\(weekdayNames[weekday])曜"
        }
    }
}
