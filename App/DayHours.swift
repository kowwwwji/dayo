import SwiftUI

/// 一日の表示時間帯。この外側に予定が無ければグリッド上で帯に畳む。`@AppStorage` で保存する。
enum DayHours {
    static let startKey = "dayStartHour"
    static let endKey = "dayEndHour"
    static let defaultStart = 7
    /// 24 なら深夜側は畳まない。
    static let defaultEnd = 23

    static func label(_ hour: Int) -> String {
        hour == 24 ? "24:00" : String(format: "%d:00", hour)
    }
}

struct DayHoursPicker: View {
    @Binding var startHour: Int
    @Binding var endHour: Int

    var body: some View {
        Picker("一日の開始", selection: $startHour) {
            ForEach(0...12, id: \.self) { hour in
                Text(DayHours.label(hour)).tag(hour)
            }
        }
        Picker("一日の終わり", selection: $endHour) {
            ForEach(18...24, id: \.self) { hour in
                Text(hour == 24 ? "なし" : DayHours.label(hour)).tag(hour)
            }
        }
    }
}
