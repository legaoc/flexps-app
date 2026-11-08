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
                // Abrir con / Compartir desde Archivos (y otras apps):
                // iOS copia el audio a Documents/Inbox y entrega su URL;
                // se importa igual que desde el selector interno.
                .onOpenURL { url in
                    Task { await store.importFiles([url]) }
                }
        }
    }
}
