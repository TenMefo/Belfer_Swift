import Foundation

enum LaunchKind: String, Codable, CaseIterable {
    case application = "Aplikacja", command = "Polecenie"
}

/// Program i argumenty są oddzielone, więc nazwa folderu nie staje się fragmentem polecenia.
struct LaunchAction: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""
    var kind = LaunchKind.application
    var executable = ""
    var arguments: [String] = []
    var folder = ""
    var appBookmark: Data?
    var folderBookmark: Data?
    var administrator = false
    var pinned = true
    var withMaterials = false
    var subjectID: UUID?
    var managed: Bool?
    var serviceURL: String?
    var topicID: UUID?
    var lessonID: UUID?

    var symbol: String { kind == .application ? "app.badge" : "terminal" }
    var displayCommand: String {
        let command: String
        if kind == .application {
            command = (["/usr/bin/open", "-a", executable] + (folder.isEmpty ? [] : [folder]) + (arguments.isEmpty ? [] : ["--args"] + arguments)).map(Self.shellQuote).joined(separator: " ")
        } else {
            command = ([executable] + arguments).map(Self.shellQuote).joined(separator: " ")
        }
        return folder.isEmpty || kind == .application ? command : "cd \(Self.shellQuote(folder)) && \(command)"
    }
    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              executable.hasPrefix("/"), !executable.contains("\0"),
              arguments.allSatisfy({ !$0.contains("\0") }), !folder.contains("\0"),
              folder.isEmpty || folder.hasPrefix("/")
        else { throw DataError.invalid("Podaj nazwę akcji i pełną ścieżkę programu (od /). Folder także musi mieć pełną ścieżkę.") }
        if managed == true && (kind != .command || administrator) { throw DataError.invalid("Proces w tle musi być poleceniem bez uprawnień administratora.") }
        if kind == .application {
            guard executable.lowercased().hasSuffix(".app"), !administrator else {
                throw DataError.invalid("Wybierz pakiet .app. Uprawnienia administratora dotyczą poleceń, nie aplikacji.")
            }
        }
    }
    static func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
    static func appleScriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r") + "\""
    }
    /// Nie dodajemy sudo: macOS sam wyświetli systemowe okno uwierzytelnienia.
    var privilegedScript: String {
        "do shell script " + Self.appleScriptString(displayCommand + " 2>&1") + " with administrator privileges"
    }
    static func vscode() -> LaunchAction {
        LaunchAction(name: "Visual Studio Code", executable: "/Applications/Visual Studio Code.app")
    }
    static func xampp(_ operation: String) -> LaunchAction {
        let titles = ["start": "Uruchom XAMPP", "stop": "Zatrzymaj XAMPP", "restart": "Restartuj XAMPP", "status": "Status XAMPP"]
        return LaunchAction(name: titles[operation] ?? "XAMPP", kind: .command,
                            executable: "/Applications/XAMPP/xamppfiles/xampp", arguments: [operation],
                            administrator: operation != "status")
    }
}
