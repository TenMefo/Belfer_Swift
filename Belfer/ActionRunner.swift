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
    @Published var running: Set<UUID> = []
    var services: [UUID: Process] = [:]
    var serviceLogs: [UUID: URL] = [:]
    var serviceHandles: [UUID: FileHandle] = [:]
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
                    if action.managed == true {
                        try startService(action)
                        transcript += "Uruchomiono proces w tle. Log i zatrzymanie dostępne przy przycisku.\n"
                        continue
                    }
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

extension ActionRunner {
    func startService(_ action: LaunchAction) throws {
        if services[action.id]?.isRunning == true { return }
        let action = try ActionExecutor.resolved(action)
        try? serviceHandles[action.id]?.close()
        if let old = serviceLogs[action.id] { try? FileManager.default.removeItem(at: old) }
        guard action.kind == .command && !action.administrator else { throw DataError.invalid("Serwer musi być poleceniem bez administratora.") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: action.executable)
        process.arguments = action.arguments
        if !action.folder.isEmpty { process.currentDirectoryURL = URL(fileURLWithPath: action.folder) }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        process.environment = environment
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("belfer-service-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: url)
        process.standardOutput = handle; process.standardError = handle; process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            let code = process.terminationStatus
            Task { @MainActor in
                guard let self else { return }
                self.running.remove(action.id)
                self.results[action.id] = ActionResult(exitCode: code, output: self.serviceOutput(action.id))
            }
        }
        do { try process.run(); services[action.id] = process; serviceLogs[action.id] = url; serviceHandles[action.id] = handle; running.insert(action.id) }
        catch { try? handle.close(); try? FileManager.default.removeItem(at: url); throw error }
    }
    func serviceOutput(_ id: UUID) -> String {
        guard let url = serviceLogs[id], let handle = try? FileHandle(forReadingFrom: url) else { return "Brak logu procesu." }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 65_536 ? size - 65_536 : 0)
        return String(decoding: (try? handle.read(upToCount: 65_536)) ?? Data(), as: UTF8.self)
    }
    func showServiceLog(_ action: LaunchAction) {
        transcript = "\(action.name)\n\(serviceOutput(action.id))"; showingOutput = true
    }
    func stopService(_ id: UUID) {
        guard let process = services[id], process.isRunning else { running.remove(id); return }
        // Zatrzymujemy także potomków npm, żeby proces node nie pozostawał na porcie.
        let descendants = Self.childProcesses(process.processIdentifier)
        for pid in descendants.reversed() { kill(pid, SIGTERM) }
        process.terminate()
        running.remove(id)
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            for pid in descendants where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
    func stopAll() { for id in Array(services.keys) { stopService(id) } }
    private static func childProcesses(_ parent: Int32) -> [Int32] {
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps"); process.arguments = ["-axo", "pid=,ppid="]; process.standardOutput = pipe
        guard (try? process.run()) != nil else { return [] }
        let output = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        let pairs = String(decoding: output, as: UTF8.self).split(separator: "\n").compactMap { line -> (Int32, Int32)? in
            let values = line.split(whereSeparator: { $0.isWhitespace }).compactMap { Int32($0) }; return values.count == 2 ? (values[0], values[1]) : nil
        }
        var result: [Int32] = [], queue = [parent]
        while let pid = queue.first { queue.removeFirst(); let children = pairs.filter { $0.1 == pid && !result.contains($0.0) }.map { $0.0 }; result += children; queue += children }
        return result
    }
}
