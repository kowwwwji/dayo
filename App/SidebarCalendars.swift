import DayoCore
import SwiftUI

/// 画面に出さないカレンダーとリストの保存。起動時にモデルへ渡し、切り替えたら書き戻す。
/// 端末ごとに持つ（同じカレンダーでも、見たい場所は Mac と iPhone で違うため）。
enum CalendarVisibilitySetting {
    static let key = "hiddenCalendarIDs"

    static var stored: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    /// 表示・非表示を切り替えて保存する。
    @MainActor
    static func set(_ id: String, hidden: Bool, on model: TimelineModel) {
        var ids = model.hiddenCalendarIDs
        if hidden {
            ids.insert(id)
        } else {
            ids.remove(id)
        }
        UserDefaults.standard.set(ids.sorted(), forKey: key)
        Task { await model.setCalendar(id, hidden: hidden) }
    }
}

#if os(macOS)
/// サイドバーのカレンダー一覧。アカウントごとに分け、色付きのチェックで表示・非表示を切り替える。
/// 予定のカレンダーは四角、リマインダーのリストは丸で示す。
struct SidebarCalendars: View {
    let model: TimelineModel

    private struct Account {
        let name: String
        var calendars: [CalendarInfo]
    }

    /// アカウントごとにまとめる。並びは取得元の順（予定のカレンダー → リマインダーのリスト）のまま。
    private var accounts: [Account] {
        var result: [Account] = []
        for calendar in model.calendars {
            let name = calendar.accountName.isEmpty ? "その他" : calendar.accountName
            if let index = result.firstIndex(where: { $0.name == name }) {
                result[index].calendars.append(calendar)
            } else {
                result.append(Account(name: name, calendars: [calendar]))
            }
        }
        return result
    }

    var body: some View {
        ForEach(accounts, id: \.name) { account in
            Section(account.name) {
                ForEach(account.calendars) { calendar in
                    row(calendar)
                }
            }
        }
    }

    private func row(_ calendar: CalendarInfo) -> some View {
        let isHidden = model.hiddenCalendarIDs.contains(calendar.id)
        let shape = calendar.kind == .event ? "square" : "circle"
        return Button {
            CalendarVisibilitySetting.set(calendar.id, hidden: !isHidden, on: model)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isHidden ? shape : "checkmark.\(shape).fill")
                    .foregroundStyle(Color(cgColor: calendar.color))
                Text(calendar.name)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            // 名前の右の空きでも押せるようにする
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(calendar.name)
        .accessibilityValue(isHidden ? "非表示" : "表示中")
    }
}
#endif
