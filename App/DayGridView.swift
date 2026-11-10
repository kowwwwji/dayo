import DayoCore
import SwiftUI

/// 0〜24 時の時間軸に予定とリマインダーを配置する。重なりは列に分けて横に並べる。
/// 設定した表示時間帯の外に何も無ければ、その時間帯は帯に畳む（クリックで開く）。
struct DayGridView: View {
    let placements: [GridPlacement]
    let day: Date
    let isToday: Bool
    /// 表示中の日の内容が読み込み済みか。帯の有無が確定してから初期位置へスクロールする
    let isLoaded: Bool
    let editing: ItemEditing
    let onToggle: (TimelineItem) -> Void

    private let hourHeight: CGFloat = 56
    private let collapsedHeight: CGFloat = 22
    /// 時刻ラベルの列幅。上に固定する「終日」行のラベルも同じ幅にして揃える。
    static let labelWidth: CGFloat = 48
    private var labelWidth: CGFloat { Self.labelWidth }
    static let trailingInset: CGFloat = 12
    private var trailingInset: CGFloat { Self.trailingInset }

    @AppStorage(DayHours.startKey) private var startHour = DayHours.defaultStart
    @AppStorage(DayHours.endKey) private var endHour = DayHours.defaultEnd
    /// ユーザーが開いた側。日を変えたら畳み直す。
    @State private var expanded: Set<DayGridAxis.Edge> = []
    @State private var now = Date.now
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var axis: DayGridAxis {
        DayGridAxis(
            hourHeight: hourHeight,
            collapsedHeight: collapsedHeight,
            collapsed: DayGridAxis.collapsedRanges(
                placements: placements,
                startHour: startHour,
                endHour: endHour,
                expanded: expanded,
                nowMinute: isToday ? nowMinute : nil
            )
        )
    }

    var body: some View {
        let axis = self.axis
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    hourLines(axis)
                    bands(axis)
                    GeometryReader { geometry in
                        items(axis, availableWidth: geometry.size.width)
                    }
                    if isToday {
                        nowIndicator(axis)
                    }
                }
                .frame(height: axis.totalHeight)
                .padding(.vertical, 8)
            }
            .onAppear {
                if isLoaded { scrollToStart(proxy, axis) }
            }
            .onChange(of: day) { _, _ in expanded = [] }
            // 日を変えた直後は前の日の内容で帯が決まっているので、読み込み完了を待ってから位置を合わせる
            .onChange(of: isLoaded) { _, loaded in
                if loaded { scrollToStart(proxy, self.axis) }
            }
            .onReceive(clock) { now = $0 }
        }
    }

    private func hourLines(_ axis: DayGridAxis) -> some View {
        ForEach(axis.visibleHours, id: \.self) { hour in
            HStack(alignment: .center, spacing: 6) {
                Text(DayHours.label(hour))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: labelWidth - 6, alignment: .trailing)
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 1)
            }
            .frame(height: 12)
            .offset(y: axis.y(forMinute: hour * 60) - 6)
            .id(Self.hourID(hour))
        }
    }

    /// 畳んだ時間帯。クリックで開く。
    private func bands(_ axis: DayGridAxis) -> some View {
        ForEach(axis.collapsed, id: \.lowerBound) { range in
            let frame = axis.bandFrame(for: range)
            HStack(spacing: 6) {
                Text("\(DayHours.label(range.lowerBound / 60)) 〜 \(DayHours.label(range.upperBound / 60))")
                    .font(.caption2.monospacedDigit())
                Text("予定なし")
                    .font(.caption2)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: frame.height)
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.5))
            .contentShape(Rectangle())
            .onTapGesture { expanded.insert(range.lowerBound == 0 ? .early : .late) }
            .offset(y: frame.y)
            .id(Self.bandID(range))
        }
    }

    private func items(_ axis: DayGridAxis, availableWidth: CGFloat) -> some View {
        let gridWidth = max(0, availableWidth - labelWidth - trailingInset)
        return ForEach(placements) { placement in
            let columnWidth = gridWidth / CGFloat(max(1, placement.columnCount))
            GridItemView(placement: placement, editing: editing) { onToggle(placement.item) }
                .frame(
                    width: max(0, columnWidth - 2),
                    height: max(18, axis.height(fromMinute: placement.startMinute, to: placement.endMinute) - 1),
                    alignment: .topLeading
                )
                .offset(
                    x: labelWidth + columnWidth * CGFloat(placement.column),
                    y: axis.y(forMinute: placement.startMinute)
                )
        }
    }

    private var nowMinute: Int {
        let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: now)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    /// 現在時刻の赤線。現在時刻を含む側は畳まないので、常に目盛りの上に出る。
    private func nowIndicator(_ axis: DayGridAxis) -> some View {
        let minute = nowMinute
        return HStack(spacing: 0) {
            Circle().fill(.red).frame(width: 7, height: 7)
            Rectangle().fill(.red).frame(height: 1)
        }
        .padding(.leading, labelWidth - 4)
        .offset(y: axis.y(forMinute: minute) - 3.5)
        .allowsHitTesting(false)
    }

    /// 今日は現在時刻の 1 時間前、他の日は一日の開始（畳まれていればその帯）が上端に来るようにする。
    private func scrollToStart(_ proxy: ScrollViewProxy, _ axis: DayGridAxis) {
        let targetHour = isToday
            ? max(0, Calendar.autoupdatingCurrent.component(.hour, from: now) - 1)
            : startHour
        if let band = axis.collapsed.first(where: { $0.contains(targetHour * 60) }) {
            proxy.scrollTo(Self.bandID(band), anchor: .top)
        } else {
            proxy.scrollTo(Self.hourID(targetHour), anchor: .top)
        }
    }

    private static func hourID(_ hour: Int) -> String { "hour-\(hour)" }
    private static func bandID(_ range: Range<Int>) -> String { "band-\(range.lowerBound)" }
}

/// グリッド上の 1 項目。予定はカレンダー色のブロック、リマインダーはチェック付きの行。
private struct GridItemView: View {
    let placement: GridPlacement
    let editing: ItemEditing
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
            .contentShape(Rectangle())
            .onTapGesture { editing.open(item) }
            .itemEditor(for: item, editing)
        case .reminder:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button(action: onToggle) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(color)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isCompleted ? "未完了に戻す" : "完了にする")
                HStack(spacing: 4) {
                    PriorityMark(priority: item.priority)
                        .font(.caption)
                    Text(item.title)
                        .font(.caption)
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture { editing.open(item) }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            .itemEditor(for: item, editing)
        }
    }
}
