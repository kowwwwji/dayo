import DayoCore
import SwiftUI

/// 0〜24 時の時間軸に予定とリマインダーを配置する。重なりは列に分けて横に並べる。
struct DayGridView: View {
    let placements: [GridPlacement]
    let isToday: Bool
    let onToggle: (TimelineItem) -> Void

    private let hourHeight: CGFloat = 56
    /// 時刻ラベルの列幅。上に固定する「終日」行のラベルも同じ幅にして揃える。
    static let labelWidth: CGFloat = 48
    private var labelWidth: CGFloat { Self.labelWidth }
    static let trailingInset: CGFloat = 12
    private var trailingInset: CGFloat { Self.trailingInset }

    @State private var now = Date.now
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    hourLines
                    GeometryReader { geometry in
                        items(availableWidth: geometry.size.width)
                    }
                    if isToday {
                        nowIndicator
                    }
                }
                .frame(height: hourHeight * 24)
                .padding(.vertical, 8)
            }
            .onAppear { scrollToStart(proxy) }
            .onChange(of: isToday) { _, _ in scrollToStart(proxy) }
            .onReceive(clock) { now = $0 }
        }
    }

    private var hourLines: some View {
        ForEach(0..<24, id: \.self) { hour in
            HStack(alignment: .center, spacing: 6) {
                Text(String(format: "%d:00", hour))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: labelWidth - 6, alignment: .trailing)
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 1)
            }
            .frame(height: 12)
            .offset(y: CGFloat(hour) * hourHeight - 6)
            .id(hour)
        }
    }

    private func items(availableWidth: CGFloat) -> some View {
        let gridWidth = max(0, availableWidth - labelWidth - trailingInset)
        return ForEach(placements) { placement in
            let columnWidth = gridWidth / CGFloat(max(1, placement.columnCount))
            GridItemView(placement: placement) { onToggle(placement.item) }
                .frame(
                    width: max(0, columnWidth - 2),
                    height: max(18, y(forMinute: placement.durationMinutes) - 1),
                    alignment: .topLeading
                )
                .offset(
                    x: labelWidth + columnWidth * CGFloat(placement.column),
                    y: y(forMinute: placement.startMinute)
                )
        }
    }

    private var nowIndicator: some View {
        let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: now)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        return HStack(spacing: 0) {
            Circle().fill(.red).frame(width: 7, height: 7)
            Rectangle().fill(.red).frame(height: 1)
        }
        .padding(.leading, labelWidth - 4)
        .offset(y: y(forMinute: minute) - 3.5)
        .allowsHitTesting(false)
    }

    private func y(forMinute minute: Int) -> CGFloat {
        CGFloat(minute) / 60 * hourHeight
    }

    /// 今日は現在時刻の 1 時間前、他の日は 8 時が上端に来るようにする。
    private func scrollToStart(_ proxy: ScrollViewProxy) {
        let hour = isToday
            ? max(0, (Calendar.autoupdatingCurrent.component(.hour, from: now)) - 1)
            : 8
        proxy.scrollTo(hour, anchor: .top)
    }
}

/// グリッド上の 1 項目。予定はカレンダー色のブロック、リマインダーはチェック付きの行。
private struct GridItemView: View {
    let placement: GridPlacement
    let onToggle: () -> Void

    private var item: TimelineItem { placement.item }
    private var color: Color { Color(cgColor: item.color) }

    var body: some View {
        switch item.kind {
        case .event:
            HStack(alignment: .top, spacing: 0) {
                Rectangle().fill(color).frame(width: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(placement.durationMinutes >= 60 ? 2 : 1)
                    if placement.durationMinutes >= 45, let start = item.start, let end = item.end {
                        Text("\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        case .reminder:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button(action: onToggle) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(color)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isCompleted ? "未完了に戻す" : "完了にする")
                Text(item.title)
                    .font(.caption)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
        }
    }
}
