import SwiftUI

// MARK: - App
@main
struct FlexpsApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var player = PlayerManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(player)
        }
    }
}
