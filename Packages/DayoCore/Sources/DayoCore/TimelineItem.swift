import CoreGraphics
import EventKit
import Foundation

public enum ItemKind: Hashable, Sendable {
    case event
    case reminder
}

/// 予定とリマインダーを画面向けに統一した表現。永続化はしない（正は EventKit 側）。
public struct TimelineItem: Identifiable, Equatable {
    /// 画面上の一意キー。繰り返し予定は回ごとに異なる値になる。
    public let id: String
    /// EventKit から元のオブジェクトを引き直すためのキー（繰り返し予定では全回で共通）。
    public let calendarItemIdentifier: String
    public let kind: ItemKind
    public var title: String
    /// event: startDate / reminder: dueDate。期日なしリマインダーは nil。
    public var start: Date?
    /// event のみ。
    public var end: Date?
    public var isAllDay: Bool
    /// reminder のみ。event は常に false。
    public var isCompleted: Bool
    /// リスト名 or カレンダー名。
    public var sourceName: String
    /// アカウント名（iCloud / Google など）。同名カレンダーの区別と接続確認に使う。
    public var accountName: String
    public var color: CGColor
    public var recurrence: EKRecurrenceRule?
    /// 共有リストか。
    public var isShared: Bool

    public init(
        id: String,
        calendarItemIdentifier: String,
        kind: ItemKind,
        title: String,
        start: Date?,
        end: Date?,
        isAllDay: Bool,
        isCompleted: Bool,
        sourceName: String,
        accountName: String,
        color: CGColor,
        recurrence: EKRecurrenceRule?,
        isShared: Bool
    ) {
        self.id = id
        self.calendarItemIdentifier = calendarItemIdentifier
        self.kind = kind
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isCompleted = isCompleted
        self.sourceName = sourceName
        self.accountName = accountName
        self.color = color
        self.recurrence = recurrence
        self.isShared = isShared
    }

    /// 期間の日に表示すべきか。期日で判定し、期日なしのリマインダーは時間軸に載せない。
    /// `range.end`（翌日 0:00）は含めない。
    public func falls(in range: DateInterval) -> Bool {
        guard let start else { return false }
        return start >= range.start && start < range.end
    }
}
