import SwiftUI
import AppKit
import QuickLook

struct LibraryView: View {
    @EnvironmentObject var store: WorkspaceStore
    @State private var editing: Resource?
    @State private var preview: URL?
    @State private var kind: ResourceKind?
    @State private var removing: Resource?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                PageHeading(eyebrow: "Biblioteka", title: "Pliki, projekty i dobre rozmowy.", subtitle: "Wszystkie przypięcia w jednym miejscu. Oryginały zostają w Twoich folderach.")
                Menu("Przypnij materiał") {
                    Button("Plik") { if let item = store.pickResource() { store.change { $0.resources.append(item) } } }
                    Button("Folder projektu") { if let item = store.pickResource(project: true) { store.change { $0.resources.append(item) } } }
                    Button("Link / rozmowa / wiadomość") { editing = Resource(kind: .website) }
                }.menuStyle(.borderlessButton).fixedSize()
            }
            Picker("Rodzaj", selection: $kind) {
                Text("Wszystkie").tag(nil as ResourceKind?)
                ForEach(ResourceKind.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
            }.pickerStyle(.segmented)
            let resources = allResources(store.data).filter { kind == nil || $0.kind == kind }
            if resources.isEmpty { EmptyPanel(title: "Tu zbierzesz materiały", message: "Przypnij prezentację, projekt React albo link do rozmowy. Materiały dodane w tematach i lekcjach też pojawią się tutaj.", symbol: "folder.badge.plus") }
            ForEach(resources) { item in
                VStack(alignment: .leading, spacing: 10) {
                    ResourceRow(resource: item) {
                        do { preview = try store.resolvedURL(item) }
                        catch { store.error = error.localizedDescription }
                    }
                    Text(origin(item)).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Edytuj przypięcie") { editing = item }
                        Spacer()
                        Button("Odepnij", role: .destructive) { removing = item }
                    }
                }.panel()
            }
        }
        .quickLookPreview($preview)
        .sheet(item: $editing) { item in ResourceEditor(item: item) { update($0) } }
        .confirmationDialog("Odpiąć materiał ze wszystkich miejsc? Plik na dysku pozostanie bez zmian.", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Odepnij", role: .destructive) {
                if let id = removing?.id {
                    store.change {
                        $0.resources.removeAll { $0.id == id }
                        for index in $0.topics.indices { $0.topics[index].resources.removeAll { $0.id == id } }
                        for index in $0.lessons.indices { $0.lessons[index].resources.removeAll { $0.id == id } }
                    }
                }
                removing = nil
            }
        }
    }
    private func origin(_ item: Resource) -> String {
        var values: [String] = []
        if store.data.resources.contains(where: { $0.id == item.id }) { values.append("Biblioteka ogólna") }
        values += store.data.topics.filter { $0.resources.contains(where: { $0.id == item.id }) }.map { "Temat: \($0.title)" }
        values += store.data.lessons.filter { $0.resources.contains(where: { $0.id == item.id }) }.map { "Lekcja: \(store.data.className($0.classID)) · \($0.start.formatted(date: .abbreviated, time: .omitted))" }
        return values.joined(separator: " · ")
    }
    private func update(_ item: Resource) {
        store.change {
            var found = false
            if let index = $0.resources.firstIndex(where: { $0.id == item.id }) { $0.resources[index] = item; found = true }
            for index in $0.topics.indices {
                if let ri = $0.topics[index].resources.firstIndex(where: { $0.id == item.id }) { $0.topics[index].resources[ri] = item; found = true }
            }
            for index in $0.lessons.indices {
                if let ri = $0.lessons[index].resources.firstIndex(where: { $0.id == item.id }) { $0.lessons[index].resources[ri] = item; found = true }
            }
            if !found { $0.resources.append(item) }
        }
    }
}
struct TaskRow: View {
    @EnvironmentObject var store: WorkspaceStore
    var item: WorkItem
    var edit: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                var updated = item; updated.done.toggle()
                store.change { $0.tasks.upsert(updated) }
            } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(item.done ? Color.green : Color.secondary)
            }.buttonStyle(.plain).accessibilityLabel(item.done ? "Oznacz jako niezrobione" : "Oznacz jako zrobione")
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).strikethrough(item.done).font(.headline)
                if !item.details.isEmpty { Text(item.details).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                HStack {
                    if let id = item.classID { Text(store.data.className(id)) }
                    if let due = item.due { Text("Do \(due.formatted(date: .abbreviated, time: .omitted))").foregroundStyle(!item.done && Calendar.current.startOfDay(for: due) < Calendar.current.startOfDay(for: Date()) ? Color.orange : Color.secondary) }
                }.font(.caption)
            }
            Spacer()
            Button("Edytuj", action: edit)
        }
    }
}
struct TasksView: View {
    @EnvironmentObject var store: WorkspaceStore
    @Binding var editing: EditRequest?
    @State private var showDone = false
    @State private var deleting: WorkItem?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                PageHeading(eyebrow: "Skrzynka pomysłów", title: "Zapisz teraz. Uporządkuj później.", subtitle: "Zadania, pomysły na lekcje i rzeczy do poprawienia.")
                Button("Dodaj", systemImage: "plus") { editing = .task(WorkItem()) }.buttonStyle(.borderedProminent)
            }
            Toggle("Pokaż też zrobione", isOn: $showDone).toggleStyle(.switch)
            let items = store.data.tasks.filter { showDone || !$0.done }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            if items.isEmpty { EmptyPanel(title: "Czysta głowa", message: "Tutaj możesz szybko zapisać pomysł lub zadanie, a później przypisać mu klasę i termin.", symbol: "checkmark.circle") }
            ForEach(items) { item in
                HStack {
                    TaskRow(item: item) { editing = .task(item) }
                    Button(role: .destructive) { deleting = item } label: { Image(systemName: "trash") }
                }.panel()
            }
        }
        .confirmationDialog("Usunąć zadanie?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Usuń", role: .destructive) {
                if let id = deleting?.id { store.change { $0.tasks.removeAll { $0.id == id } } }
                deleting = nil
            }
        }
    }
}
struct SettingsView: View {
    @EnvironmentObject var store: WorkspaceStore
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeading(eyebrow: "Ustawienia", title: "Twoje dane. Twój porządek.", subtitle: "Belfer działa lokalnie i nie wymaga konta.")
            VStack(alignment: .leading, spacing: 14) {
                Label("Kopie zapasowe", systemImage: "externaldrive.badge.timemachine").font(.title3.bold())
                Text("Kopia JSON zawiera plan, tematy, notatki i przypięcia. Nie zawiera samych prezentacji ani folderów projektów. Na innym Macu może być konieczne ponowne przypięcie plików.").foregroundStyle(.secondary)
                HStack {
                    Button("Eksportuj kopię") { store.exportBackup() }
                    Button("Przywróć kopię…") { store.restoreBackup() }
                    Button("Pokaż folder danych") { NSWorkspace.shared.selectFile(store.fileURL.path, inFileViewerRootedAtPath: store.fileURL.deletingLastPathComponent().path) }
                }
                Text(store.fileURL.path).font(.caption.monospaced()).textSelection(.enabled).foregroundStyle(.secondary)
                Text("Przed każdym zapisem zachowywany jest poprzedni poprawny stan: workspace.previous.json. Warto też regularnie eksportować kopię poza ten komputer.").font(.caption).foregroundStyle(.secondary)
            }.panel()
            VStack(alignment: .leading, spacing: 14) {
                Label("Połączenia z narzędziami", systemImage: "point.3.connected.trianglepath.dotted").font(.title3.bold())
                LabeledContent("Librus", value: "Odnośnik + kopiowanie tematu; bez automatycznej synchronizacji")
                LabeledContent("ChatGPT / Gemini", value: "Prywatne odnośniki do konkretnych rozmów")
                LabeledContent("Poczta", value: "Linki mailto: / message: lub przypięte pliki .eml")
                LabeledContent("Excel", value: "Import tematów przez CSV UTF-8")
                Text("Treści rozmów i skrzynki nie są pobierane automatycznie. Aplikacja nie uruchamia poleceń z instrukcji projektów. Pliki otwierają się w domyślnych programach macOS.").font(.caption).foregroundStyle(.secondary)
            }.panel()
            VStack(alignment: .leading, spacing: 14) {
                Label("Pierwsze kroki", systemImage: "sparkles").font(.title3.bold())
                Text("1. Dodaj klasy i przedmioty.\n2. Dodaj tematy lub zaimportuj CSV.\n3. Utwórz stały plan i wypełnij tydzień.\n4. Przypisz tematy i materiały do lekcji.\n5. Wieczorem kliknij „Przygotuj jutro”.\n6. Po zajęciach zapisz, na czym skończyliście.")
                if store.data.classes.isEmpty && store.data.topics.isEmpty && store.data.lessons.isEmpty && store.data.tasks.isEmpty && store.data.resources.isEmpty && store.data.slots.isEmpty && !store.locked {
                    Button("Wczytaj przykładowy kokpit") { store.change { $0 = .demo() } }.buttonStyle(.borderedProminent)
                }
            }.panel()
            Text("Belfer 0.1 · macOS 14+ · SwiftUI · dane lokalne").font(.caption).foregroundStyle(.secondary)
        }
    }
}
