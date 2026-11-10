import Combine
import DayoCore
import SwiftUI

/// 週表示でグリッドの上に固定する見出し。曜日と日付の行、その下に終日の帯。
/// 左右の余白をグリッドと同じにして、列の位置を揃える。
/// 終日の帯は空でも 1 段ぶん出しておく。ダブルクリックでの登録と、時間軸からのドラッグの落とし先になるため。
struct WeekHeaderView: View {
    let days: [Date]
    let spans: [AllDaySpan]
    let editing: ItemEditing
    let board: TimelineDragBoard
    let onToggle: (TimelineItem) -> Void
    /// 終日の項目を日数ぶん動かした
    let onMoveDays: (TimelineItem, Int) -> Void
    /// 終日の項目を時間軸へ落とした。日と開始分
    let onMakeTimed: (TimelineItem, Date, Int) -> Void

    private let laneHeight: CGFloat = 26
    /// 終日の帯をそのまま見せる段数。超えた分は内部スクロール。
    private let visibleLanes = 4
    @State private var now = Date.now
    /// ダブルクリックで終日の新規登録を開いた日。エディタを閉じるまで、そこに仮のチップを置く
    @State private var newDay: Date?
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// 新規登録のエディタを開く場所のキー。
    private static let newItemAnchor = "allDay-new"

    private var spanLaneCount: Int { (spans.map(\.lane).max() ?? -1) + 1 }
    private var showsNewChip: Bool { newDay != nil && editing.isOpenForNew(at: Self.newItemAnchor) }
    /// 仮のチップは既存の帯の下の段に置く。
    private var laneCount: Int { max(1, spanLaneCount + (showsNewChip ? 1 : 0)) }

    var body: some View {
        VStack(spacing: 4) {
            dayLabels
            allDayRow
        }
        .padding(.vertical, 6)
        // 日の列が並ぶ範囲を届ける。時間軸からここへ落とした項目を終日にする
        .background {
            Color.clear
                .onFrameChange { board.allDayFrame = $0 }
                .padding(.leading, DayGridView.labelWidth)
                .padding(.trailing, DayGridView.trailingInset)
        }
        .onDisappear { board.allDayFrame = nil }
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
        ScrollView {
            GeometryReader { geometry in
                // 余白を曜日の行・グリッドと同じにしてあるので、残りの幅を日数で割れば列幅が揃う
                let dayWidth = geometry.size.width / CGFloat(max(1, days.count))
                ZStack(alignment: .topLeading) {
                    #if os(macOS)
                    newItemSurface(dayWidth: dayWidth)
                    #endif
                    ForEach(spans) { span in
                        AllDayChip(
                            item: span.item,
                            editing: editing,
                            fillsWidth: true,
                            drag: AllDayChipDrag(
                                board: board,
                                dayWidth: dayWidth,
                                dayOffsets: -span.firstColumn...(days.count - 1 - span.firstColumn),
                                onMoveDays: { onMoveDays(span.item, $0) },
                                onMakeTimed: { day, minute in onMakeTimed(span.item, day, minute) }
                            )
                        ) { onToggle(span.item) }
                            .frame(width: max(0, dayWidth * CGFloat(span.columnSpan) - 3), alignment: .leading)
                            .offset(x: dayWidth * CGFloat(span.firstColumn), y: CGFloat(span.lane) * laneHeight)
                    }
                    newItemChip(dayWidth: dayWidth)
                }
            }
            .frame(height: CGFloat(laneCount) * laneHeight)
        }
        .frame(height: CGFloat(min(laneCount, visibleLanes)) * laneHeight)
        .padding(.leading, DayGridView.labelWidth)
        .padding(.trailing, DayGridView.trailingInset)
        .overlay(alignment: .topLeading) {
            Text("終日")
                .font(.dayoDetail)
                .foregroundStyle(.secondary)
                .frame(width: DayGridView.labelWidth - 6, alignment: .trailing)
                .padding(.top, 5)
        }
    }

    /// 帯の空いているところのダブルクリックを受ける面。チップより下に置くので、チップの上では反応しない。
    private func newItemSurface(dayWidth: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture(count: 2).onEnded { value in
                guard dayWidth > 0 else { return }
                let index = Int(value.location.x / dayWidth)
                guard days.indices.contains(index) else { return }
                newDay = days[index]
                editing.openNew(at: days[index], isAllDay: true, anchor: Self.newItemAnchor)
            })
    }

    /// 新規登録中の仮のチップ。エディタはここから出す。入力中のタイトルと種別を映す。
    @ViewBuilder
    private func newItemChip(dayWidth: CGFloat) -> some View {
        if showsNewChip, let newDay, let index = days.firstIndex(of: newDay) {
            let editor = editing.editor
            let title = editor?.title ?? ""
            Text(title.isEmpty ? (editor?.kind == .reminder ? "新規リマインダー" : "新規予定") : title)
                .font(.dayoTitle.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .frame(width: max(0, dayWidth - 3), alignment: .leading)
                .background(.tint.opacity(0.25), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.tint, lineWidth: 1))
                .newItemEditor(editing, at: Self.newItemAnchor)
                .offset(x: dayWidth * CGFloat(index), y: CGFloat(spanLaneCount) * laneHeight)
        }
    }
}
