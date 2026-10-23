import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct LaunchActionEditor: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State var item: LaunchAction
    @State private var argumentText = ""
    @State private var validationError: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Akcja") {
                    TextField("Nazwa przycisku", text: $item.name)
                    Picker("Rodzaj", selection: $item.kind) {
                        ForEach(LaunchKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.onChange(of: item.kind) { _, kind in
                        item.appBookmark = nil
                        if kind == .application { item.administrator = false }
                    }
                    HStack {
                        TextField(item.kind == .application ? "Ścieżka aplikacji .app" : "Ścieżka programu / skryptu", text: $item.executable)
                            .onChange(of: item.executable) { _, _ in item.appBookmark = nil }
                        Button("Wybierz…") { pickProgram() }
                    }
                    Text(item.kind == .application ? "Np. /Applications/Visual Studio Code.app. Nie jest potrzebne polecenie code w PATH." : "Np. /Applications/XAMPP/xamppfiles/xampp. Nie wpisuj sudo ani całego polecenia w tym polu.")
                        .font(.caption).foregroundStyle(.secondary)
                    MultilineField(title: "Argumenty — każdy w osobnym wierszu", text: $argumentText)
                    Text("Dla XAMPP wpisz np. start albo stop. Dla skryptu użyj np. /bin/zsh i dwóch argumentów: -lc oraz treści polecenia. Spacje w argumentach zostają zachowane.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField(item.kind == .application ? "Folder projektu do otwarcia (opcjonalnie)" : "Folder roboczy (opcjonalnie)", text: $item.folder)
                            .onChange(of: item.folder) { _, _ in item.folderBookmark = nil }
                        Button("Wybierz folder…") { pickFolder() }
                    }
                    if item.kind == .command {
                        Toggle("Proces działający w tle (np. npm run dev)", isOn: Binding(get: { item.managed ?? false }, set: { item.managed = $0; if $0 { item.administrator = false } }))
                        if item.managed == true { TextField("Adres strony serwera", text: Binding(get: { item.serviceURL ?? "" }, set: { item.serviceURL = $0 })) }
                        Toggle("Uruchamiaj z uprawnieniami administratora", isOn: $item.administrator).disabled(item.managed == true)
                        Text("macOS wyświetli własne okno uwierzytelnienia. Belfer nie przechowuje hasła. Polecenie powinno kończyć działanie po wykonaniu zadania; limit oczekiwania wynosi 3 minuty.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Przypięcie") {
                    SubjectPicker(selection: $item.subjectID).onChange(of: item.subjectID) { _, _ in item.topicID = nil; item.lessonID = nil }
                    Text("Bez wybranego przedmiotu akcja jest ogólna. XAMPP przypisz np. do tworzenia stron.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Pokaż przycisk na kokpicie tego przedmiotu", isOn: $item.pinned)
                    Picker("Temat", selection: $item.topicID) {
                        Text("Bez powiązania z tematem").tag(nil as UUID?)
                        ForEach(store.data.topics.filter { item.subjectID == nil || $0.subjectID == item.subjectID }) { Text($0.title).tag(Optional($0.id)) }
                    }
                    Picker("Termin lekcji", selection: $item.lessonID) {
                        Text("Bez powiązania z terminem").tag(nil as UUID?)
                        ForEach(store.data.lessons.filter { item.subjectID == nil || store.data.subjectID(for: $0) == item.subjectID }.sorted { $0.start < $1.start }) { lesson in
                            Text("\(store.data.className(lesson.classID)) · \(lesson.start.formatted(date: .abbreviated, time: .shortened)) · \(store.data.title(lesson))").tag(Optional(lesson.id))
                        }
                    }
                    Toggle("Uruchamiaj razem z otwieraniem materiałów lekcji", isOn: $item.withMaterials)
                    Text("Wykonanie zaczyna się po kliknięciu „Otwórz materiały uczniów”. Akcje wykonują się po kolei; błąd zatrzymuje zestaw. Bez powiązania z tematem lub terminem ta opcja dotyczy wszystkich lekcji. Nic nie uruchamia się samo po otwarciu Belfra.").font(.caption).foregroundStyle(.secondary)
                }
                if let validationError { Text(validationError).foregroundStyle(.red) }
            }.formStyle(.grouped)
            EditorActions(valid: !item.name.isEmpty && !item.executable.isEmpty) { save() }
        }.frame(width: 760, height: 760)
            .onAppear { argumentText = item.arguments.joined(separator: "\n") }
    }
    private func save() {
        item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.arguments = argumentText.components(separatedBy: .newlines).filter { !$0.isEmpty }
        do {
            try item.validate()
            if store.change({ $0.actions.upsert(item) }) { dismiss() }
        } catch { validationError = error.localizedDescription }
    }
    private func pickProgram() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        if item.kind == .application { panel.allowedContentTypes = [.applicationBundle] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        item.executable = url.path
        // Ścieżka jest zawsze widoczna i edytowalna; brak zależności od polecenia w PATH.
    }
    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        item.folder = url.path
    }
}
