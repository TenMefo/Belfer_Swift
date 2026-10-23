import Foundation
import SwiftUI

// Formularze pracują na kopii. Anulowanie nie zmienia zapisanych danych.
enum EditRequest: Identifiable {
    case schoolClass(SchoolClass), topic(Topic), lesson(Lesson), task(WorkItem), slot(WeeklySlot)
    var id: String {
        switch self {
        case .schoolClass(let item): return "class-\(item.id)"
        case .topic(let item): return "topic-\(item.id)"
        case .lesson(let item): return "lesson-\(item.id)"
        case .task(let item): return "task-\(item.id)"
        case .slot(let item): return "slot-\(item.id)"
        }
    }
}
extension Array where Element: Identifiable {
    mutating func upsert(_ item: Element) {
        if let index = firstIndex(where: { $0.id == item.id }) { self[index] = item }
        else { append(item) }
    }
}
struct ClassEditor: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    @State var item: SchoolClass
    var body: some View {
        VStack {
            Form {
                TextField("Klasa / grupa", text: $item.name)
                SubjectPicker(selection: $item.subjectID)
                TextField("Kwalifikacja", text: $item.qualification)
                MultilineField(title: "Notatki o grupie", text: $item.notes)
            }.formStyle(.grouped)
            EditorActions(valid: item.subjectID != nil && !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if store.change({ $0.classes.upsert(item) }) { dismiss() }
            }
        }.frame(width: 600, height: 430).onAppear { if item.subjectID == nil { item.subjectID = store.data.subjects.first?.id } }
    }
}
struct TopicEditor: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    @State var item: Topic
    var body: some View {
        VStack {
            Form {
                TextField("Temat", text: $item.title)
                SubjectPicker(selection: $item.subjectID).onChange(of: item.subjectID) { _, id in item.curriculumID = store.data.curricula.first { $0.subjectID == id }?.id }
                Picker("Rozkład", selection: $item.curriculumID) {
                    Text("Domyślny rozkład").tag(nil as UUID?)
                    ForEach(store.data.curricula.filter { $0.subjectID == item.subjectID }) { Text($0.name).tag(Optional($0.id)) }
                }
                Stepper("Kolejność: \(item.order ?? 1)", value: Binding(get: { item.order ?? 1 }, set: { item.order = $0 }), in: 1...10000)
                Stepper("Liczba godzin: \(item.hours)", value: $item.hours, in: 1...1000)
                MultilineField(title: "Przebieg lekcji", text: $item.outline)
                MultilineField(title: "Polecenie dla uczniów", text: $item.exercise)
                ResourceListEditor(resources: $item.resources)
            }.formStyle(.grouped)
            EditorActions(valid: item.subjectID != nil && !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if store.change({ $0.topics.upsert(item) }) { dismiss() }
            }
        }.frame(width: 760, height: 700).onAppear { if item.subjectID == nil { item.subjectID = store.data.subjects.first?.id } }
    }
}
struct LessonEditor: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    @State var item: Lesson
    @State private var subject: UUID?
    @State private var curriculum: UUID?
    var body: some View {
        VStack {
            Form {
                SubjectPicker(selection: $subject).onChange(of: subject) { _, id in
                    if store.data.subjectID(for: item) != id, let group = store.data.classes.first(where: { $0.subjectID == id }) { item.classID = group.id }
                    if !store.data.topics(for: id).contains(where: { $0.id == item.topicID }) { item.topicID = nil }
                    if !store.data.profiles.contains(where: { $0.id == item.profileID && $0.subjectID == id }) { item.profileID = nil }; curriculum = nil
                }
                Picker("Klasa", selection: $item.classID) {
                    ForEach(store.data.classes.filter { $0.subjectID == subject }) { Text($0.name).tag($0.id) }
                }
                Picker("Rozkład", selection: $curriculum) {
                    Text("Wszystkie rozkłady przedmiotu").tag(nil as UUID?)
                    ForEach(store.data.curricula.filter { $0.subjectID == subject }) { Text($0.name).tag(Optional($0.id)) }
                }.onChange(of: curriculum) { _, id in
                    if !store.data.topics(for: subject, curriculumID: id).contains(where: { $0.id == item.topicID }) { item.topicID = nil }
                }
                Picker("Temat", selection: $item.topicID) {
                    Text("Jeszcze bez tematu").tag(nil as UUID?)
                    ForEach(store.data.topics(for: subject, curriculumID: curriculum)) { Text($0.title).tag(Optional($0.id)) }
                }
                Picker("Profil środowiska", selection: $item.profileID) {
                    Text("Bez profilu").tag(nil as UUID?)
                    ForEach(store.data.profiles.filter { $0.subjectID == subject }) { Text($0.name).tag(Optional($0.id)) }
                }
                Stepper("Blok: \(item.blockCount ?? 1) lekcji", value: Binding(get: { item.blockCount ?? 1 }, set: { item.blockCount = $0; item.duration = $0 * 45 }), in: 1...10)
                DatePicker("Termin", selection: $item.start)
                Stepper("Czas: \(item.duration) min", value: $item.duration, in: 5...480, step: 5)
                TextField("Sala", text: $item.room)
                Picker("Status", selection: $item.status) {
                    ForEach(LessonStatus.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                if store.data.conflicts(with: item) {
                    Label("Termin nakłada się na inną lekcję.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                Section("Przygotowanie — zaznacz także, jeśli element nie jest potrzebny") {
                    Toggle("Prezentacja gotowa / niepotrzebna", isOn: $item.presentationReady)
                    Toggle("Zadanie gotowe / niepotrzebne", isOn: $item.exerciseReady)
                    Toggle("Projekt / materiały gotowe / niepotrzebne", isOn: $item.projectReady)
                }
                MultilineField(title: "Notatki nauczyciela", text: $item.notes)
                MultilineField(title: "Na czym skończyliśmy / co dalej", text: $item.nextSteps)
                ResourceListEditor(resources: $item.resources)
            }.formStyle(.grouped)
            EditorActions(valid: subject != nil && store.data.classes.contains { $0.id == item.classID && $0.subjectID == subject }) {
                if store.change({ $0.lessons.upsert(item) }) { dismiss() }
            }
        }.frame(width: 760, height: 760).onAppear { subject = store.data.subjectID(for: item) }
    }
}
struct TaskEditor: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    @State var item: WorkItem
    @State private var hasDue = false
    @State private var due = Date()
    var body: some View {
        VStack {
            Form {
                TextField("Zadanie / pomysł", text: $item.title)
                Picker("Klasa", selection: $item.classID) {
                    Text("Ogólne").tag(nil as UUID?)
                    ForEach(store.data.classes) { Text("\($0.name) · \($0.subject)").tag(Optional($0.id)) }
                }
                Toggle("Ustal termin", isOn: $hasDue)
                if hasDue { DatePicker("Do kiedy", selection: $due, displayedComponents: .date) }
                HStack {
                    TextField("Folder prac do sprawdzenia", text: Binding(get: { item.workFolder ?? "" }, set: { item.workFolder = $0 }))
                    Button("Wybierz…") { if let resource = store.pickResource(project: true) { item.workFolder = resource.location } }
                }
                MultilineField(title: "Szczegóły, linki i notatki", text: $item.details)
                Toggle("Zrobione", isOn: $item.done)
            }.formStyle(.grouped)
            EditorActions(valid: !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                item.due = hasDue ? due : nil
                if store.change({ $0.tasks.upsert(item) }) { dismiss() }
            }
        }.frame(width: 600, height: 500)
            .onAppear { hasDue = item.due != nil; due = item.due ?? Date() }
    }
}
struct SlotEditor: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    @State var item: WeeklySlot
    let days = [2, 3, 4, 5, 6, 7, 1]
    let labels = [1: "Niedziela", 2: "Poniedziałek", 3: "Wtorek", 4: "Środa", 5: "Czwartek", 6: "Piątek", 7: "Sobota"]
    var body: some View {
        VStack {
            Form {
                Picker("Klasa", selection: $item.classID) {
                    ForEach(store.data.classes) { Text("\($0.name) · \($0.subject)").tag($0.id) }
                }
                Picker("Dzień", selection: $item.weekday) {
                    ForEach(days, id: \.self) { Text(labels[$0] ?? "").tag($0) }
                }
                Stepper("Godzina: \(item.hour)", value: $item.hour, in: 0...23)
                Stepper("Minuta: \(item.minute)", value: $item.minute, in: 0...59)
                Stepper("Czas: \(item.duration) min", value: $item.duration, in: 5...480, step: 5)
                TextField("Sala", text: $item.room)
                Text("Szablon określa stałe godziny. W widoku tygodnia użyj „Wypełnij z szablonu”, żeby utworzyć terminy zajęć.").foregroundStyle(.secondary)
            }.formStyle(.grouped)
            EditorActions { if store.change({ $0.slots.upsert(item) }) { dismiss() } }
        }.frame(width: 600, height: 480)
    }
}
struct ResourceListEditor: View {
    @EnvironmentObject var store: WorkspaceStore
    @Binding var resources: [Resource]
    @State private var editing: Resource?
    var body: some View {
        Section("Materiały i odnośniki") {
            ForEach(resources) { item in
                HStack {
                    Label(item.name, systemImage: item.kind.symbol)
                    if item.isPrivate { Image(systemName: "lock.fill").foregroundStyle(.orange) }
                    Spacer()
                    Button("Edytuj") { editing = item }
                    Button(role: .destructive) { resources.removeAll { $0.id == item.id } } label: { Image(systemName: "trash") }
                }
            }
            HStack {
                Button("Przypnij plik") { if let item = store.pickResource() { resources.append(item) } }
                Button("Przypnij projekt") { if let item = store.pickResource(project: true) { resources.append(item) } }
                Button("Dodaj link") { editing = Resource(kind: .website) }
                Menu("Z biblioteki") {
                    ForEach(allResources(store.data).filter { item in !resources.contains(where: { $0.id == item.id }) }) { item in
                        Button(item.name) { resources.append(item) }
                    }
                }.fixedSize().disabled(allResources(store.data).isEmpty)
            }
        }.sheet(item: $editing) { item in
            ResourceEditor(item: item) { resources.upsert($0) }
        }
    }
}
struct ResourceEditor: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    @State var item: Resource
    var save: (Resource) -> Void
    var body: some View {
        VStack {
            Form {
                TextField("Nazwa", text: $item.name)
                if item.kind == .file || item.kind == .project {
                    LabeledContent("Lokalizacja", value: item.location)
                    Text("Aby zmienić plik, usuń ten wpis i przypnij właściwy plik.").foregroundStyle(.secondary)
                } else {
                    Picker("Rodzaj", selection: $item.kind) {
                        ForEach([ResourceKind.website, .chat, .email], id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Adres", text: $item.location)
                    Text("Wklej zwykły adres rozmowy dostępny po zalogowaniu. Nie musisz jej publicznie udostępniać.").font(.caption).foregroundStyle(.secondary)
                }
                Picker("Rola materiału", selection: Binding(get: { item.role ?? .student }, set: { item.role = $0; if $0 == .solution { item.teacherOnly = true } })) {
                    ForEach(ResourceRole.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Toggle("Tylko dla nauczyciela", isOn: $item.teacherOnly)
                MultilineField(title: "Instrukcja / technologia / sposób uruchomienia", text: $item.instructions)
            }.formStyle(.grouped)
            EditorActions(valid: !item.name.isEmpty && !item.location.isEmpty) {
                do { _ = try store.resolvedURL(item); save(item); dismiss() }
                catch { store.error = error.localizedDescription }
            }
        }.frame(width: 620, height: 480)
    }
}
