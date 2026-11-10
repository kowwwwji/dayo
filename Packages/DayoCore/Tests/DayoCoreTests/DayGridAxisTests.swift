import CoreGraphics
import Foundation
import Testing
@testable import DayoCore

private func placement(_ start: Int, _ end: Int) -> GridPlacement {
    let item = TimelineItem(
        id: "\(start)", calendarItemIdentifier: "\(start)", kind: .event, title: "", start: Date(), end: Date(),
        isAllDay: false, isCompleted: false, sourceName: "", accountName: "",
        color: CGColor(gray: 0, alpha: 1), recurrence: nil, isShared: false
    )
    return GridPlacement(item: item, startMinute: start, endMinute: end, column: 0, columnCount: 1)
}

@Suite struct DayGridAxisTests {
    let hour: CGFloat = 60
    let band: CGFloat = 20

    @Test func linearWhenNothingIsCollapsed() {
        let axis = DayGridAxis(hourHeight: hour, collapsedHeight: band, collapsed: [])
        #expect(axis.y(forMinute: 0) == 0)
        #expect(axis.y(forMinute: 90) == 90)
        #expect(axis.totalHeight == CGFloat(24 * 60))
        #expect(axis.visibleHours == Array(0..<24))
    }

    @Test func collapsedEarlyHoursBecomeOneBand() {
        let axis = DayGridAxis(hourHeight: hour, collapsedHeight: band, collapsed: [0..<420])
        // 帯の中は帯の上端、帯の終わりからは線形
        #expect(axis.y(forMinute: 0) == 0)
        #expect(axis.y(forMinute: 200) == 0)
        #expect(axis.y(forMinute: 420) == band)
        #expect(axis.y(forMinute: 480) == band + hour)
        #expect(axis.height(fromMinute: 480, to: 540) == hour)
        #expect(axis.totalHeight == band + 17 * hour)
        #expect(axis.visibleHours.first == 7)
        #expect(axis.bandFrame(for: 0..<420) == (0, band))
    }

    @Test func collapsedLateHoursEndWithBand() {
        let axis = DayGridAxis(hourHeight: hour, collapsedHeight: band, collapsed: [0..<420, 1380..<1440])
        #expect(axis.y(forMinute: 1380) == band + 16 * hour)
        #expect(axis.y(forMinute: 1400) == band + 16 * hour)
        #expect(axis.totalHeight == band + 16 * hour + band)
        #expect(axis.visibleHours == Array(7..<23))
        #expect(axis.isCollapsed(minute: 1400))
        #expect(axis.isCollapsed(minute: 600) == false)
    }

    @Test func collapsesOnlyEmptyEdges() {
        let none = DayGridAxis.collapsedRanges(placements: [], startHour: 7, endHour: 23)
        #expect(none == [0..<420, 1380..<1440])

        let early = DayGridAxis.collapsedRanges(placements: [placement(120, 150)], startHour: 7, endHour: 23)
        #expect(early == [1380..<1440])

        let late = DayGridAxis.collapsedRanges(placements: [placement(1370, 1400)], startHour: 7, endHour: 23)
        #expect(late == [0..<420])

        // 境界ちょうどに収まる項目は畳んでよい
        let boundary = DayGridAxis.collapsedRanges(placements: [placement(420, 480), placement(1320, 1380)], startHour: 7, endHour: 23)
        #expect(boundary == [0..<420, 1380..<1440])
    }

    @Test func yIsMonotonicAndSpansBands() {
        let axis = DayGridAxis(hourHeight: hour, collapsedHeight: band, collapsed: [0..<420, 1380..<1440])
        var previous = axis.y(forMinute: 0)
        for minute in 1...1440 {
            let current = axis.y(forMinute: minute)
            #expect(current >= previous)
            previous = current
        }
        #expect(axis.y(forMinute: 1440) == axis.totalHeight)
        // 帯をまたぐ高さ: 帯の残り（上端まで 0）＋ 20 分
        #expect(axis.height(fromMinute: 400, to: 440) == band + 20)
    }

    @Test func collapsesExactlyAtBoundaries() {
        #expect(DayGridAxis.collapsedRanges(placements: [placement(419, 449)], startHour: 7, endHour: 23) == [1380..<1440])
        #expect(DayGridAxis.collapsedRanges(placements: [placement(420, 450)], startHour: 7, endHour: 23) == [0..<420, 1380..<1440])
        #expect(DayGridAxis.collapsedRanges(placements: [placement(1350, 1381)], startHour: 7, endHour: 23) == [0..<420])
        #expect(DayGridAxis.collapsedRanges(placements: [placement(0, 1440)], startHour: 7, endHour: 23).isEmpty)
    }

    @Test func doesNotCollapseTheEdgeContainingNow() {
        #expect(DayGridAxis.collapsedRanges(placements: [], startHour: 7, endHour: 23, nowMinute: 6 * 60 + 30) == [1380..<1440])
        #expect(DayGridAxis.collapsedRanges(placements: [], startHour: 7, endHour: 23, nowMinute: 23 * 60 + 30) == [0..<420])
        #expect(DayGridAxis.collapsedRanges(placements: [], startHour: 7, endHour: 23, nowMinute: 12 * 60) == [0..<420, 1380..<1440])
    }

    @Test func respectsExpandedEdgesAndSettingsBounds() {
        #expect(DayGridAxis.collapsedRanges(placements: [], startHour: 7, endHour: 23, expanded: [.early]) == [1380..<1440])
        #expect(DayGridAxis.collapsedRanges(placements: [], startHour: 0, endHour: 24).isEmpty)
        #expect(DayGridAxis.collapsedRanges(placements: [], startHour: 7, endHour: 24) == [0..<420])
        #expect(DayGridAxis.collapsedRanges(placements: [], startHour: 10, endHour: 9).isEmpty)
    }
}
