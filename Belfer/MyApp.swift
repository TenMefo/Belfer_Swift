import SwiftUI

@main
struct BelferApp: App {
    @StateObject private var store = WorkspaceStore()
    var body: some Scene {
        WindowGroup("Belfer") {
            ContentView().environmentObject(store)
                .frame(minWidth: 1060, minHeight: 700)
                .tint(.indigo)
        }
        .defaultSize(width: 1360, height: 880)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Szukaj w kokpicie") { NotificationCenter.default.post(name: .belferSearch, object: nil) }.keyboardShortcut("k")
            }
        }
    }
}
extension Notification.Name { static let belferSearch = Notification.Name("belfer.search") }
