import Foundation
import SwiftUI

@main
struct BelferApp: App {
    @StateObject private var store = WorkspaceStore()
    @StateObject private var runner = ActionRunner()
    var body: some Scene {
        WindowGroup("Belfer") {
            ContentView().environmentObject(store).environmentObject(runner)
                .frame(minWidth: 1060, minHeight: 700)
                .tint(.indigo)
        }
        .defaultSize(width: 1360, height: 880)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Szukaj w kokpicie") { NotificationCenter.default.post(name: .belferSearch, object: nil) }.keyboardShortcut("k")
            }
        }
        WindowGroup("Lekcja", id: "teaching", for: UUID.self) { $lessonID in
            if let lessonID { TeachingWindow(id: lessonID).environmentObject(store).tint(.indigo) }
        }
        .defaultSize(width: 1000, height: 720)
    }
}
extension Notification.Name { static let belferSearch = Notification.Name("belfer.search") }
