import Foundation
import Combine
import Darwin

struct ActionResult: Sendable {
    var exitCode: Int32
    var output: String
    var timedOut = false
    var succeeded: Bool { exitCode == 0 && !timedOut }
}

/// Wykonywanie odbywa się poza głównym wątkiem — okno nie zawiesza się podczas startu serwera.
enum ActionExecutor {
    static func resolved(_ value: LaunchAction) throws -> LaunchAction {
        var action = value
        func path(_ bookmark: Data?, fallback: String) throws -> String {
            guard let bookmark else { return fallback }
            var stale = false
            return try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale).path
        }
        action.executable = try path(action.appBookmark, fallback: action.executable)
        action.folder = try path(action.folderBookmark, fallback: action.folder)
        try action.validate()
        var directory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: action.executable, isDirectory: &directory)
        guard exists else { throw DataError.invalid("Nie znaleziono programu: \(action.executable). W edycji akcji wybierz jego właściwą lokalizację.") }
        if action.kind == .application {
            guard directory.boolValue else { throw DataError.invalid("Wskazana aplikacja nie jest pakietem .app.") }
        } else {
            guard !directory.boolValue, FileManager.default.isExecutableFile(atPath: action.executable) else {
                throw DataError.invalid("Program nie ma uprawnień do wykonywania: \(action.executable)")
            }
        }
        if !action.folder.isEmpty {
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: action.folder, isDirectory: &isFolder), isFolder.boolValue else {
                throw DataError.invalid("Nie znaleziono folderu projektu: \(action.folder)")
            }
        }
        return action
    }
    static func run(_ value: LaunchAction, timeout: TimeInterval = 180) throws -> ActionResult {
        let action = try resolved(value)
        let process = Process()
        if action.kind == .application {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", action.executable] + (action.folder.isEmpty ? [] : [action.folder]) + (action.arguments.isEmpty ? [] : ["--args"] + action.arguments)
        } else if action.administrator {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", action.privilegedScript]
        } else {
            process.executableURL = URL(fileURLWithPath: action.executable)
            process.arguments = action.arguments
            if !action.folder.isEmpty { process.currentDirectoryURL = URL(fileURLWithPath: action.folder) }
        }
        // Zapis do pliku zapobiega zakleszczeniu, gdy program wypisze więcej niż mieści potok.
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("belfer-action-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw DataError.invalid("Nie można utworzyć dziennika polecenia.")
        }
        defer { try? FileManager.default.removeItem(at: log) }
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        let timedOut = process.isRunning
        if timedOut {
            process.terminate()
            let grace = Date().addingTimeInterval(2)
            while process.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        try output.synchronize()
        let reader = try FileHandle(forReadingFrom: log)
        defer { try? reader.close() }
        let bytes = try reader.read(upToCount: 65_536) ?? Data()
        var text = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if bytes.count == 65_536 { text += "\n[Wyświetlono pierwsze 64 KB wyniku.]" }
        if timedOut { text += "\nPrzekroczono limit czasu. Proces uruchamiający został zakończony; sprawdź stan usług przyciskiem Status. Uruchomiona usługa mogła pozostać aktywna." }
        return ActionResult(exitCode: process.terminationStatus, output: text, timedOut: timedOut)
    }
}

@MainActor
final class ActionRunner: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var currentName = ""
    @Published private(set) var results: [UUID: ActionResult] = [:]
    @Published var showingOutput = false
    @Published private(set) var transcript = ""

    func run(_ actions: [LaunchAction], afterSuccess: (() -> Void)? = nil) {
        guard !busy else { return }
        guard !actions.isEmpty else { afterSuccess?(); return }
        busy = true
        transcript = ""
        Task {
            defer { busy = false; currentName = "" }
            for action in actions {
                currentName = action.name
                transcript += "\n▶ \(action.name)\n\(action.displayCommand)\n"
                do {
                    let result = try await Task.detached(priority: .userInitiated) { try ActionExecutor.run(action) }.value
                    results[action.id] = result
                    transcript += (result.output.isEmpty ? (action.kind == .application && result.succeeded ? "Wysłano żądanie otwarcia aplikacji." : "Brak komunikatów programu.") : result.output)
                    transcript += "\nKod zakończenia: \(result.exitCode)\n"
                    if !result.succeeded { showingOutput = true; return }
                } catch {
                    let result = ActionResult(exitCode: -1, output: error.localizedDescription)
                    results[action.id] = result
                    transcript += "Błąd: \(error.localizedDescription)\n"
                    showingOutput = true
                    return
                }
            }
            afterSuccess?()
        }
    }
}
