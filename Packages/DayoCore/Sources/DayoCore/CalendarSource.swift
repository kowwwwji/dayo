import EventKit
import Foundation

public enum AccessStatus: Hashable, Sendable {
    case granted
    case denied
    case restricted
    case notDetermined
}

extension AccessStatus {
    /// 予定とリマインダー両方の権限状態を1つにまとめる。表示には両方のフルアクセスが要る。
    public init(events: EKAuthorizationStatus, reminders: EKAuthorizationStatus) {
        let both = [events, reminders]
        if both.contains(.restricted) {
            self = .restricted
        } else if both.contains(.notDetermined) {
            self = .notDetermined
        } else if both.allSatisfy({ $0 == .fullAccess }) {
            self = .granted
        } else {
            self = .denied
        }
    }
}

/// 予定・リマインダーの取得元。画面はこの protocol と TimelineItem だけを扱う。
public protocol CalendarSource {
    /// 予定とリマインダーの権限をまとめて要求し、結果の状態を返す。
    func requestAccess() async throws -> AccessStatus
    /// 期間内の予定・リマインダーと、期日なしリマインダーを返す。
    func items(in range: DateInterval) async throws -> [TimelineItem]
    /// 取得元に変更があったときに値を流す。受け取ったら表示中の期間を再取得する。
    var changes: AsyncStream<Void> { get }
}
