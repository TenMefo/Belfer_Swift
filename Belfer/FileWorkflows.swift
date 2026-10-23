import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Kopiowanie do nowego folderu: pomijamy dowiązania i typowe katalogi techniczne.
enum StudentFiles {
    static func copy(_ source: URL, to target: URL) throws {
        let values = try source.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        if values.isSymbolicLink == true { return }
        let name = source.lastPathComponent
        if [".git", "node_modules", ".DS_Store", ".build"].contains(name) || name.hasPrefix(".env") { return }
        if values.isDirectory == true {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            for child in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey]) {
                try copy(child, to: target.appendingPathComponent(child.lastPathComponent))
            }
        } else { try FileManager.default.copyItem(at: source, to: target) }
    }
    static func archive(resources: [(Resource, URL?)], exercise: String, to destination: URL) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Belfer-pakiet-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try exercise.write(to: root.appendingPathComponent("Polecenie.txt"), atomically: true, encoding: .utf8)
        var links = ""
        for (index, pair) in resources.enumerated() where !pair.0.isPrivate {
            let (resource, url) = pair
            if let url, resource.kind == .file || resource.kind == .project {
                let name = "\(index + 1)-" + url.lastPathComponent
                try copy(url, to: root.appendingPathComponent(name))
            } else { links += "\(resource.name)\n\(resource.location)\n\n" }
        }
        if !links.isEmpty { try links.write(to: root.appendingPathComponent("Odnosniki.txt"), atomically: true, encoding: .utf8) }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", root.path, destination.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw DataError.invalid("Nie utworzono archiwum ZIP.") }
    }
}
struct StudentPackView: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    var lesson: Lesson
    @State private var selected = Set<UUID>()
    @State private var busy = false
    @State private var error: String?
    private var resources: [Resource] { store.data.materials(lesson).filter { !$0.isPrivate } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Pakiet dla uczniów").font(.title2.bold())
            Text("Wybierz materiały. Rozwiązania nauczyciela są wykluczone. ZIP zawiera też polecenie i odnośniki; foldery projektów są kopiowane bez node_modules, .git, .env i dowiązań.").foregroundStyle(.secondary)
            ScrollView { VStack(alignment: .leading) { ForEach(resources) { item in Toggle(item.name, isOn: Binding(get: { selected.contains(item.id) }, set: { if $0 { selected.insert(item.id) } else { selected.remove(item.id) } })) } } }
            if busy { ProgressView("Tworzenie pakietu…") }
            if let error { Text(error).foregroundStyle(.red) }
            HStack { Button("Zamknij") { dismiss() }; Spacer(); Button("Zapisz ZIP…") { export() }.disabled(busy).buttonStyle(.borderedProminent) }
        }.padding(24).frame(width: 700, height: 500).onAppear { selected = Set(resources.map(\.id)) }
    }
    private func export() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.zip]; panel.nameFieldStringValue = "Materialy-\(store.data.className(lesson.classID)).zip"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            let items = try resources.filter { selected.contains($0.id) }.map { resource in (resource, (resource.kind == .file || resource.kind == .project) ? try store.resolvedURL(resource) : nil) }
            let text = store.data.topics.first { $0.id == lesson.topicID }?.exercise ?? ""
            busy = true
            Task {
                defer { busy = false }
                do { try await Task.detached { try StudentFiles.archive(resources: items, exercise: text, to: destination) }.value; dismiss() }
                catch { self.error = error.localizedDescription }
            }
        } catch { self.error = error.localizedDescription }
    }
}
extension WorkspaceStore {
    func copyStarter(_ resource: Resource) {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.prompt = "Utwórz kopię tutaj"
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        do {
            let source = try resolvedURL(resource)
            let destination = parent.appendingPathComponent("\(source.lastPathComponent)-lekcja-\(UUID().uuidString.prefix(6))")
            // Chroni przed kopiowaniem projektu do jego własnego podfolderu.
            let from = source.resolvingSymlinksInPath().standardizedFileURL.path
            let to = destination.resolvingSymlinksInPath().standardizedFileURL.path
            guard !to.hasPrefix(from + "/") else { throw DataError.invalid("Wybierz folder poza projektem źródłowym.") }
            Task {
                do { try await Task.detached { try StudentFiles.copy(source, to: destination) }.value; NSWorkspace.shared.open(destination) }
                catch { self.error = error.localizedDescription }
            }
        } catch { self.error = error.localizedDescription }
    }
    func addDroppedURLs(_ urls: [URL], to lessonID: UUID) {
        do {
            var additions: [Resource] = []
            for url in urls {
                if url.isFileURL {
                    var directory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else { continue }
                    additions.append(Resource(name: url.lastPathComponent, kind: directory.boolValue ? .project : .file, location: url.path, bookmark: try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)))
                } else {
                    let resource = Resource(name: url.host ?? "Odnośnik", kind: .website, location: url.absoluteString)
                    _ = try resolvedURL(resource); additions.append(resource)
                }
            }
            change { data in if let i = data.lessons.firstIndex(where: { $0.id == lessonID }) { data.lessons[i].resources += additions } }
        } catch { self.error = error.localizedDescription }
    }
    func pasteLink(to lessonID: UUID) {
        guard let string = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), let url = URL(string: string), !url.isFileURL else { error = "Skopiuj adres strony lub rozmowy."; return }
        addDroppedURLs([url], to: lessonID)
    }
}

@MainActor
enum AutomaticBackup {
    private static let key = "BelferAutomaticBackupFolder"
    static var folder: URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
    }
    static func choose() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url, let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        UserDefaults.standard.set(bookmark, forKey: key)
    }
    static func disable() { UserDefaults.standard.removeObject(forKey: key) }
    static func save(_ data: Data) throws {
        guard let folder else { return }
        let name = "Belfer-auto-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString).json"
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        let copies = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])
            .filter { $0.lastPathComponent.hasPrefix("Belfer-auto-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in copies.dropFirst(30) { try? FileManager.default.removeItem(at: old) }
    }
}
