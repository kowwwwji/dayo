import Foundation
import Testing
@testable import DayoCore

private let utc = TimeZone(identifier: "UTC")!

private func days(from first: String, count: Int) -> [Date] {
    let start = ISO8601DateFormatter().date(from: "\(first)T00:00:00Z")!
    return (0..<count).map { start.addingTimeInterval(TimeInterval($0) * 86_400) }
}

@Suite struct TimelineTitleTests {
    @Test(arguments: [
        ("2026-11-10", true, "2026 / 11 / 10 (火) W46"),
        ("2026-11-10", false, "2026 / 11 / 10 (火)"),
        // 年の初めの数日は前の年の最後の週に入る
        ("2027-01-01", true, "2027 / 1 / 1 (金) W53"),
    ])
    func day(first: String, showsWeekNumber: Bool, expected: String) {
        let day = days(from: first, count: 1)[0]
        #expect(TimelineTitle.text(for: day, showsWeekNumber: showsWeekNumber, timeZone: utc) == expected)
    }

    @Test(arguments: [
        // 同じ月の中では、右端は日と曜日だけ
        ("2026-11-11", true, "2026 / 11 / 11 (水) – 13 (金) W46"),
        ("2026-11-11", false, "2026 / 11 / 11 (水) – 13 (金)"),
        // 2 つの週にまたがるときだけ両方の週番号（週は月曜始まり）
        ("2026-11-14", true, "2026 / 11 / 14 (土) – 16 (月) W46–47"),
        ("2026-11-09", true, "2026 / 11 / 9 (月) – 11 (水) W46"),
        ("2026-11-13", true, "2026 / 11 / 13 (金) – 15 (日) W46"),
        // 月が変わるなら右端に月も書く
        ("2026-11-29", true, "2026 / 11 / 29 (日) – 12 / 1 (火) W48–49"),
        ("2026-11-30", true, "2026 / 11 / 30 (月) – 12 / 2 (水) W49"),
        // 年が変わるなら右端に年も書く
        ("2026-12-30", true, "2026 / 12 / 30 (水) – 2027 / 1 / 1 (金) W53"),
        ("2026-12-30", false, "2026 / 12 / 30 (水) – 2027 / 1 / 1 (金)"),
        ("2027-01-02", true, "2027 / 1 / 2 (土) – 4 (月) W53–1"),
    ])
    func threeDays(first: String, showsWeekNumber: Bool, expected: String) {
        let text = TimelineTitle.text(
            forDays: days(from: first, count: 3), showsWeekNumber: showsWeekNumber, timeZone: utc
        )
        #expect(text == expected)
    }

    @Test func aSingleDayRangeReadsLikeTheDay() {
        let text = TimelineTitle.text(forDays: days(from: "2026-11-10", count: 1), showsWeekNumber: true, timeZone: utc)
        #expect(text == "2026 / 11 / 10 (火) W46")
    }

    @Test(arguments: [
        // 年月は週の最初の日のもの。週番号は週の中の木曜で決める（日曜始まりでも月〜土と同じ番号）
        ("2026-11-08", true, "2026 / 11  W46"),
        ("2026-11-09", true, "2026 / 11  W46"),
        ("2026-11-29", true, "2026 / 11  W49"),
        ("2026-11-08", false, "2026 / 11"),
    ])
    func week(first: String, showsWeekNumber: Bool, expected: String) {
        let text = TimelineTitle.text(
            forWeek: days(from: first, count: 7), showsWeekNumber: showsWeekNumber, timeZone: utc
        )
        #expect(text == expected)
    }

    @Test func noDaysGiveAnEmptyTitle() {
        #expect(TimelineTitle.text(forDays: [], showsWeekNumber: true, timeZone: utc) == "")
        #expect(TimelineTitle.text(forWeek: [], showsWeekNumber: true, timeZone: utc) == "")
    }
}
