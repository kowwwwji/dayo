import Foundation

/// リマインダーの優先度。純正アプリの「なし・低・中・高」に対応する。
/// rawValue は EventKit の `priority`（1 が最高、9 が最低、0 はなし）。
public enum ReminderPriority: Int, CaseIterable, Hashable, Sendable {
    case none = 0
    case high = 1
    case medium = 5
    case low = 9

    /// EventKit の 0〜9 を 4 段階に丸める。1〜4 は高、5 は中、6〜9 は低。
    public init(ekPriority: Int) {
        switch ekPriority {
        case 1...4: self = .high
        case 5: self = .medium
        case 6...9: self = .low
        default: self = .none
        }
    }

    public var label: String {
        switch self {
        case .none: "なし"
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }

    /// 純正アプリと同じ「!」の数。
    public var marker: String {
        switch self {
        case .none: ""
        case .low: "!"
        case .medium: "!!"
        case .high: "!!!"
        }
    }
}
