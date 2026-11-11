import Foundation
import Testing
@testable import DayoCore

private let tokyo: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    calendar.locale = Locale(identifier: "ja_JP")
    return calendar
}()

/// 2026-11-10（火）10:00 JST。
private let reference = tokyo.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 10))!

private func day(_ year: Int, _ month: Int, _ day: Int) -> Date? {
    tokyo.date(from: DateComponents(year: year, month: month, day: day))
}

@Suite struct DateJumpTests {
    @Test(arguments: [
        // クイック入力と同じ読み方
        ("11/20", day(2026, 11, 20)),
        ("来週水曜", day(2026, 11, 18)),
        ("20日", day(2026, 11, 20)),
        ("3日後", day(2026, 11, 13)),
        ("明日", day(2026, 11, 11)),
        ("今日", day(2026, 11, 10)),
        (" 11/20 ", day(2026, 11, 20)),
        // 年なしの過ぎた日付は、クイック入力と同じく次の年に読む
        ("11/5", day(2027, 11, 5)),
        // 年付き。過去へも行ける
        ("2026/11/1", day(2026, 11, 1)),
        ("2025/3/5", day(2025, 3, 5)),
        ("2027-01-02", day(2027, 1, 2)),
        ("2027年1月2日", day(2027, 1, 2)),
        ("２０２６／１２／２５", day(2026, 12, 25)),
        // 日付として読めないもの
        ("", nil),
        ("あいうえお", nil),
        ("2026/2/30", nil),
        ("2026/13/1", nil),
        // 日付のほかに何か書いてあれば、行き先とは読まない
        ("11/20 会議", nil),
        ("15時", nil),
        ("毎週月曜", nil),
    ] as [(String, Date?)])
    func readsTheDayToJumpTo(text: String, expected: Date?) {
        #expect(DateJump.day(from: text, reference: reference, calendar: tokyo) == expected)
    }
}
