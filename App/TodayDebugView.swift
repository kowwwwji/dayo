import DayoCore
import SwiftUI

/// フェーズ1の確認用。権限状態と今日の TimelineItem を素朴に一覧する。
struct TodayDebugView: View {
    let model: TodayModel

    var body: some View {
        List {
            Section {
                LabeledContent("権限", value: accessLabel)
                if let message = model.errorMessage {
                    Text(message).foregroundStyle(.red)
                }
            }
            Section("今日 \(Date.now.formatted(date: .abbreviated, time: .omitted))") {
                if model.items.isEmpty {
                    Text("項目なし").foregroundStyle(.secondary)
                }
                ForEach(model.items) { item in
                    row(item)
                }
            }
        }
        .navigationTitle("Dayo")
        .task { await model.start() }
    }

    private func row(_ item: TimelineItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon(for: item))
                .foregroundStyle(Color(cgColor: item.color))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .strikethrough(item.isCompleted)
                Text("\(timeLabel(item)) · \(item.sourceName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accessLabel: String {
        switch model.access {
        case .granted: "許可"
        case .denied: "拒否（システム設定で許可してください）"
        case .restricted: "制限"
        case .notDetermined: "未確認"
        }
    }

    private func icon(for item: TimelineItem) -> String {
        switch item.kind {
        case .event: "calendar"
        case .reminder: item.isCompleted ? "checkmark.circle.fill" : "circle"
        }
    }

    private func timeLabel(_ item: TimelineItem) -> String {
        guard let start = item.start else { return "期日なし" }
        if item.isAllDay { return "終日" }
        let startText = start.formatted(date: .omitted, time: .shortened)
        guard let end = item.end else { return startText }
        return "\(startText)–\(end.formatted(date: .omitted, time: .shortened))"
    }
}
