import Foundation

/// 早期リマインダー（期日の何分前に通知するか）の選択肢。
/// EventKit では期日より前に鳴る相対アラーム（負の `relativeOffset`）になり、通知は純正アプリが出す。
public enum EarlyReminder: Hashable, Sendable {
    case none
    case minutes(Int)

    /// 設定画面とエディタに並べる選択肢。
    public static let presets: [EarlyReminder] = [
        .none, .minutes(5), .minutes(10), .minutes(15), .minutes(30), .minutes(60), .minutes(120), .minutes(24 * 60),
    ]

    /// 0 以下は「なし」。
    public init(minutes: Int?) {
        if let minutes, minutes > 0 {
            self = .minutes(minutes)
        } else {
            self = .none
        }
    }

    /// `ItemDraft` / `TimelineItem` に入れる値。なしは nil。
    public var minutes: Int? {
        switch self {
        case .none: nil
        case .minutes(let value): value
        }
    }

    public var label: String {
        switch self {
        case .none:
            return "なし"
        case .minutes(let value):
            if value % (24 * 60) == 0 { return "\(value / (24 * 60))日前" }
            if value % 60 == 0 { return "\(value / 60)時間前" }
            return "\(value)分前"
        }
    }
}
