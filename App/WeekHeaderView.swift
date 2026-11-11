import Combine
import DayoCore
import SwiftUI

/// 曜日と日付の行。今日は赤丸で示す。日表示では 1 日分、3 日・週表示では列の数だけ並べる。
/// 左右の余白をグリッドと同じにして、各日を列の中に置く。
struct DayLabelsRow: View {
    let days: [Date]
    /// 列の中での寄せ方。
    var alignment: Alignment = .center

    @State private var now = Date.now
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
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
                .frame(maxWidth: .infinity, alignment: alignment)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isToday ? .isSelected : [])
            }
        }
        .padding(.leading, DayGridView.labelWidth)
        .padding(.trailing, DayGridView.trailingInset)
        .onReceive(clock) { now = $0 }
    }
}

/// 列が複数の表示（3 日・週）でグリッドの上に固定する見出し。曜日と日付の行、その下に終日の帯。
/// 左右の余白をグリッドと同じにして、列の位置を揃える。
/// 終日の帯は空でも 1 段ぶん出しておく。ダブルクリックでの登録と、時間軸からのドラッグの落とし先になるため。
struct WeekHeaderView: View {
    let days: [Date]
    let spans: [AllDaySpan]
    /// キー操作で選択中の項目
    var selection: TimelineSelection?
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
    /// ダブルクリックで終日の新規登録を開いた日。エディタを閉じるまで、そこに仮のチップを置く
    @State private var newDay: Date?
    /// 新規登録のエディタを開く場所のキー。
    private static let newItemAnchor = "allDay-new"

    private var spanLaneCount: Int { (spans.map(\.lane).max() ?? -1) + 1 }
    private var showsNewChip: Bool { newDay != nil && editing.isOpenForNew(at: Self.newItemAnchor) }
    private var laneCount: Int { max(1, spanLaneCount + (showsNewChip ? 1 : 0)) }

    var body: some View {
        VStack(spacing: 4) {
            DayLabelsRow(days: days)
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
        .onChange(of: days) { _, _ in newDay = nil }
    }

    /// 選択中の帯。終日欄にあるものだけ。
    private var selectedSpan: AllDaySpan? {
        guard let selection, selection.place == .allDay else { return nil }
        return spans.first { $0.item.id == selection.itemID }
    }

    private static let selectionID = "selection"

    private var allDayRow: some View {
        ScrollViewReader { proxy in
            allDayScroll
                // 段が多くて隠れている帯を選んだら、見えるところまで動かす
                .onChange(of: selectedSpan?.id) { _, id in
                    if id != nil { proxy.scrollTo(Self.selectionID) }
                }
        }
    }

    private var allDayScroll: some View {
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
                            isSelected: selectedSpan?.id == span.id,
                            drag: AllDayChipDrag(
                                board: board,
                                dayWidth: dayWidth,
                                dayOffsets: -span.firstColumn...(days.count - 1 - span.firstColumn),
                                onMoveDays: { onMoveDays(span.item, $0) },
                                onMakeTimed: { day, minute in onMakeTimed(span.item, day, minute) }
                            ),
                            onDoubleClick: { x in
                                openNewItem(atColumn: span.firstColumn + Int(x / max(1, dayWidth)))
                            }
                        ) { onToggle(span.item) }
                            .frame(width: max(0, dayWidth * CGFloat(span.columnSpan) - 3), alignment: .leading)
                            .offset(x: dayWidth * CGFloat(span.firstColumn), y: CGFloat(span.lane) * laneHeight)
                    }
                    // 仮のチップは既存の帯の下の段に置く
                    if showsNewChip, let newDay, let index = days.firstIndex(of: newDay) {
                        NewItemChip(editing: editing, anchor: Self.newItemAnchor, width: max(0, dayWidth - 3))
                            .offset(x: dayWidth * CGFloat(index), y: CGFloat(spanLaneCount) * laneHeight)
                    }
                }
            }
            .frame(height: CGFloat(laneCount) * laneHeight)
            // 帯は `offset` で置いていてスクロールの行き先にならないので、選択中の帯の位置に目印を重ねる
            .overlay(alignment: .top) {
                if let selectedSpan {
                    Color.clear
                        .frame(height: laneHeight)
                        .alignmentGuide(.top) { _ in -CGFloat(selectedSpan.lane) * laneHeight }
                        .id(Self.selectionID)
                        .allowsHitTesting(false)
                }
            }
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

    /// 帯の空いているところのダブルクリックを受ける面。チップより下に置く。チップの上のダブルクリックはチップが受けて同じ処理へ回す。
    private func newItemSurface(dayWidth: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture(count: 2).onEnded { value in
                guard dayWidth > 0 else { return }
                openNewItem(atColumn: Int(value.location.x / dayWidth))
            })
    }

    /// その列の日の終日として新規登録を開く。
    private func openNewItem(atColumn index: Int) {
        guard days.indices.contains(index) else { return }
        newDay = days[index]
        editing.openNew(at: days[index], isAllDay: true, anchor: Self.newItemAnchor)
    }
}
