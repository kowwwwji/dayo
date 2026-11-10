import DayoCore
import SwiftUI

@main
struct DayoApp: App {
    @State private var model = TodayModel(source: EventKitRepository())

    var body: some Scene {
        WindowGroup {
            TodayDebugView(model: model)
        }
    }
}
