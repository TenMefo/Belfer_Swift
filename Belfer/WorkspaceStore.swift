import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var data = Workspace()
    @Published var error: String?
    @Published private(set) var locked = false
    let fileURL: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Belfer", isDirectory: true)
        fileURL = base.appendingPathComponent("workspace.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do { data = try Self.decode(Data(contentsOf: fileURL)) }
        catch { locked = true; self.error = "Nie udało się odczytać danych. Oryginalny plik pozostaje bez zmian. Przywróć poprawną kopię w Ustawieniach.\n\(error.localizedDescription)" }
    }
    static func decode(_ bytes: Data) throws -> Workspace {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Workspace.self, from: bytes).validated()
    }
    static func encode(_ value: Workspace) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
    @discardableResult
    func change(_ edit: (inout Workspace) -> Void) -> Bool {
        guard !locked else { error = "Zapis zablokowany po błędzie odczytu. Przywróć kopię w Ustawieniach."; return false }
        var updated = data
        edit(&updated)
        return write(updated)
    }
    @discardableResult
    private func write(_ value: Workspace) -> Bool {
        do {
            _ = try value.validated()
            let bytes = try Self.encode(value)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Zachowujemy poprzedni poprawny stan przed atomowym zapisem nowego.
            if FileManager.default.fileExists(atPath: fileURL.path) && !locked {
                let old = try Data(contentsOf: fileURL)
                _ = try Self.decode(old)
                try old.write(to: fileURL.deletingPathExtension().appendingPathExtension("previous.json"), options: .atomic)
            }
            try bytes.write(to: fileURL, options: .atomic)
            data = value
            locked = false
            return true
        } catch { self.error = "Nie zapisano zmian: \(error.localizedDescription)"; return false }
    }
    func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Belfer-kopia.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Self.encode(data).write(to: url, options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
    func restoreBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let restored = try Self.decode(Data(contentsOf: url))
            let alert = NSAlert()
            alert.messageText = "Zastąpić bieżący kokpit?"
            alert.informativeText = "Kopia zawiera \(restored.classes.count) klas i \(restored.lessons.count) lekcji. Przed zastąpieniem aplikacja zachowa bieżący plik. Powiązane pliki materiałów nie są częścią kopii."
            alert.addButton(withTitle: "Przywróć")
            alert.addButton(withTitle: "Anuluj")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let name = "przed-przywroceniem-\(UUID().uuidString).json"
                try FileManager.default.copyItem(at: fileURL, to: fileURL.deletingLastPathComponent().appendingPathComponent(name))
            }
            _ = write(restored)
        } catch { self.error = "Nie przywrócono kopii: \(error.localizedDescription)" }
    }
    func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try CSVImporter.topics(String(contentsOf: url, encoding: .utf8))
            let existing = Set(data.topics.map { $0.title.lowercased() + "\u{1F}" + $0.subject.lowercased() })
            var seen = existing
            let additions = imported.filter { seen.insert($0.title.lowercased() + "\u{1F}" + $0.subject.lowercased()).inserted }
            let alert = NSAlert()
            alert.messageText = "Import rozkładu materiału"
            alert.informativeText = "Nowe tematy: \(additions.count). Pominięte duplikaty: \(imported.count - additions.count).\n\n" + additions.prefix(8).map { "• \($0.title) (\($0.hours) h)" }.joined(separator: "\n") + "\n\nIstniejące tematy pozostaną bez zmian."
            alert.addButton(withTitle: "Dodaj tematy")
            alert.addButton(withTitle: "Anuluj")
            if alert.runModal() == .alertFirstButtonReturn { change { $0.topics.append(contentsOf: additions) } }
        } catch { self.error = error.localizedDescription }
    }
    func pickResource(project: Bool = false) -> Resource? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !project
        panel.canChooseDirectories = project
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            return Resource(name: url.lastPathComponent, kind: project ? .project : .file, location: url.path, bookmark: bookmark)
        } catch { self.error = error.localizedDescription; return nil }
    }
    func resolvedURL(_ resource: Resource) throws -> URL {
        if resource.kind == .file || resource.kind == .project {
            if let bookmark = resource.bookmark {
                var stale = false
                let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
                guard FileManager.default.fileExists(atPath: url.path) else { throw DataError.invalid("Nie znaleziono pliku. Przypnij go ponownie: \(resource.name)") }
                return url
            }
            let url = URL(fileURLWithPath: resource.location)
            guard FileManager.default.fileExists(atPath: url.path) else { throw DataError.invalid("Nie znaleziono pliku: \(resource.name)") }
            return url
        }
        guard let url = URL(string: resource.location), let scheme = url.scheme?.lowercased(),
              ["https", "http", "mailto", "message"].contains(scheme),
              !["http", "https"].contains(scheme) || (url.host?.isEmpty == false)
        else { throw DataError.invalid("Dozwolone są adresy https://, http://, mailto: i message:.") }
        return url
    }
    func open(_ resource: Resource) {
        do { if !NSWorkspace.shared.open(try resolvedURL(resource)) { error = "Nie można otworzyć: \(resource.name)" } }
        catch { self.error = error.localizedDescription }
    }
    func openStudentMaterials(_ resources: [Resource]) {
        for resource in resources where !resource.teacherOnly { open(resource) }
    }
}
