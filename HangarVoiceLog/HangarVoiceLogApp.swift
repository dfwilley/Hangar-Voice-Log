import SwiftUI

@main
struct HangarVoiceLogApp: App {
    @StateObject private var store = EntryStore()

    var body: some Scene {
        WindowGroup {
            EntryListView()
                .environmentObject(store)
        }
    }
}

enum AppSettings {
    static let tailKey = "tailNumber"
    static let defaultTail = "N721NE"
}
