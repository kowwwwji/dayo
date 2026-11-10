import Combine
import DayoCore
import SwiftUI

/// 週表示でグリッドの上に固定する見出し。曜日と日付の行、その下に終日の帯。
/// 列幅はグリッドと同じ式（`DayGridView.dayWidth`）で決め、縦の位置を揃える。
struct WeekHeaderView: View {
    let days: [Date]
    let spans: [AllDaySpan]
    let editing: ItemEditing
    let onToggle: (TimelineItem) -> Void

    private let laneHeight: CGFloat = 26
    /// 終日の帯をそのまま見せる段数。超えた分は内部スクロール。
    private let visibleLanes = 4
    @State private var now = Date.now
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var laneCount: Int { (spans.map(\.lane).max() ?? -1) + 1 }

    var body: some View {
        VStack(spacing: 4) {
            dayLabels
            if !spans.isEmpty {
                allDayRow
            }
        }
        .padding(.vertical, 6)
        .onReceive(clock) { now = $0 }
    }

    private var dayLabels: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let isToday = Calendar.autoupdatingCurrent.isDate(day, inSameDayAs: now)
                HStack(spacing: 4) {
                    Text(day.formatted(.dateTime.weekday(.narrow).locale(Locale(identifier: "ja_JP"))))
                        .foregroundStyle(.secondary)
                    Text("\(Calendar.autoupdatingCurrent.component(.day, from: day))")
                        .fontWeight(isToday ? .semibold : .regular)
                        .foregroundStyle(isToday ? .white : .primary)
                        .frame(minWidth: 22, minHeight: 22)
                        .background {
                            if isToday { Circle().fill(.red) }
                        }
                }
                .font(.dayoSmall.monospacedDigit())
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isToday ? .isSelected : [])
            }
        }
        .padding(.leading, DayGridView.labelWidth)
        .padding(.trailing, DayGridView.trailingInset)
    }

    private var allDayRow: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("終日")
                .font(.dayoDetail)
                .foregroundStyle(.secondary)
                .frame(width: DayGridView.labelWidth - 6, alignment: .trailing)
                .padding(.top, 5)
            ScrollView {
                GeometryReader { geometry in
                    // このビューの幅は目盛りの列を除いた分なので、足して同じ式に通す
                    let dayWidth = DayGridView.dayWidth(
                        totalWidth: geometry.size.width + DayGridView.labelWidth, dayCount: days.count
                    )
                    ForEach(spans) { span in
                        AllDayChip(item: span.item, editing: editing, fillsWidth: true) { onToggle(span.item) }
                            .frame(width: max(0, dayWidth * CGFloat(span.columnSpan) - 3), alignment: .leading)
                            .offset(x: 6 + dayWidth * CGFloat(span.firstColumn), y: CGFloat(span.lane) * laneHeight)
                    }
                }
                .frame(height: CGFloat(laneCount) * laneHeight)
            }
            .frame(height: CGFloat(min(laneCount, visibleLanes)) * laneHeight)
        }
    }
}
