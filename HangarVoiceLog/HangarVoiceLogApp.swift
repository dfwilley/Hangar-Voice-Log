import SwiftUI

@main
struct HangarVoiceLogApp: App {
    @StateObject private var store = EntryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .tint(Theme.accent)
        }
    }
}
