import DayoCore
import SwiftUI

/// 1 日分の予定と Todo を 1 本の時間軸で見せる。
/// 上部に終日・期限切れ、中央に時刻付き（グリッドかリスト）、下部に期日なし。
struct DayTimelineView: View {
    let model: DayTimelineModel
    @AppStorage(TimelineStyle.storageKey) private var style: TimelineStyle = .grid
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let message = model.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                Divider()
            }
            content
        }
        .task { await model.activate() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.activate() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            Task { await model.handleDayChanged() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { Task { await model.showPreviousDay() } } label: {
                Image(systemName: "chevron.left")
            }
            Text(model.day.formatted(.dateTime.month().day().weekday(.wide)))
                .font(.title3.weight(.semibold))
                .frame(minWidth: 160)
            Button { Task { await model.showNextDay() } } label: {
                Image(systemName: "chevron.right")
            }
            Button("今日") { Task { await model.showToday() } }
                .disabled(model.isToday)
            Spacer()
            TimelineStylePicker(style: $style)
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 100)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch model.access {
        case .granted:
            sections
        case .denied, .restricted:
            ContentUnavailableView(
                "カレンダーとリマインダーへのアクセスが必要です",
                systemImage: "lock",
                description: Text("システム設定のプライバシーで Dayo にフルアクセスを許可してください。")
            )
        case .notDetermined:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sections: some View {
        VStack(spacing: 0) {
            let pinned = model.timeline.allDay + model.timeline.overdue
            if !pinned.isEmpty {
                PinnedSection(title: "終日・期限切れ") {
                    ForEach(model.timeline.allDay) { row($0) }
                    ForEach(model.timeline.overdue) { row($0, isOverdue: true) }
                }
                Divider()
            }
            timed
            if !model.timeline.undated.isEmpty {
                Divider()
                PinnedSection(title: "期日なし") {
                    ForEach(model.timeline.undated) { row($0) }
                }
            }
        }
        .overlay {
            if model.hasLoaded, model.timeline.isEmpty {
                ContentUnavailableView("予定も Todo もありません", systemImage: "checkmark.circle")
            }
        }
    }

    @ViewBuilder
    private var timed: some View {
        switch style {
        case .grid:
            DayGridView(placements: model.placements, isToday: model.isToday) { item in
                Task { await model.toggleCompleted(item) }
            }
        case .list:
            List(model.timeline.timed) { row($0) }
                .listStyle(.plain)
        }
    }

    private func row(_ item: TimelineItem, isOverdue: Bool = false) -> some View {
        TimelineRow(item: item, isOverdue: isOverdue) {
            Task { await model.toggleCompleted(item) }
        }
    }
}

/// グリッドの上下に固定する小さなセクション。行数が多いときだけ内部でスクロールする。
private struct PinnedSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    content
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: 140)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
