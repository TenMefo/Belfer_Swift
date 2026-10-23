import SwiftUI

struct SubjectPicker: View {
    @EnvironmentObject var store: WorkspaceStore
    @Binding var selection: UUID?
    var body: some View {
        Picker("Przedmiot", selection: $selection) {
            Text("Wybierz przedmiot").tag(nil as UUID?)
            ForEach(store.data.subjects) { Text($0.name).tag(Optional($0.id)) }
        }
    }
}
struct SubjectsView: View {
    @EnvironmentObject var store: WorkspaceStore
    @State private var editing: Subject?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                PageHeading(eyebrow: "Organizacja", title: "Najpierw przedmiot.", subtitle: "Każdy przedmiot ma własne rozkłady, tematy, klasy i skróty.")
                Button("Dodaj przedmiot", systemImage: "plus") { editing = Subject() }.buttonStyle(.borderedProminent)
            }
            if store.data.subjects.isEmpty { EmptyPanel(title: "Dodaj pierwszy przedmiot", message: "Następnie przypisz do niego klasy, rozkład i środowisko pracy.", symbol: "books.vertical") }
            ForEach(store.data.subjects) { subject in
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(subject.name).font(.title3.bold()); Spacer(); Button("Edytuj") { editing = subject } }
                    Text("Klasy: \(store.data.classes.filter { $0.subjectID == subject.id }.map(\.name).joined(separator: ", "))")
                    Text("\(store.data.curricula.filter { $0.subjectID == subject.id }.count) rozkładów · \(store.data.topics(for: subject.id).count) tematów · \(store.data.actions.filter { $0.subjectID == subject.id }.count) skrótów").foregroundStyle(.secondary)
                    if !subject.notes.isEmpty { Text(subject.notes).foregroundStyle(.secondary) }
                }.panel()
            }
        }.sheet(item: $editing) { SubjectEditor(item: $0) }
    }
}
struct SubjectEditor: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    @State var item: Subject
    @State private var error: String?
    var body: some View {
        VStack {
            Form {
                TextField("Nazwa przedmiotu", text: $item.name)
                MultilineField(title: "Uwagi", text: $item.notes)
                if let error { Text(error).foregroundStyle(.red) }
            }.formStyle(.grouped)
            EditorActions(valid: !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !store.data.subjects.contains(where: { $0.id != item.id && Workspace.key($0.name) == Workspace.key(item.name) }) else { error = "Przedmiot o takiej nazwie już istnieje."; return }
                if store.change({ $0.subjects.upsert(item) }) { dismiss() }
            }
        }.frame(width: 620, height: 380)
    }
}
struct TopicsView: View {
    @EnvironmentObject var store: WorkspaceStore
    @Binding var editing: EditRequest?
    @State private var subject: UUID?
    @State private var curriculum: UUID?
    @State private var importSheet = false
    @State private var planName = ""
    @State private var showPlan = false
    @State private var deleting: Topic?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                PageHeading(eyebrow: "Rozkłady materiału", title: "Przedmiot → rozkład → temat", subtitle: "Tematy wybierasz z rozkładu przypisanego do przedmiotu.")
                Button("Import Excel / CSV") { importSheet = true }.disabled(subject == nil)
                Button("Dodaj temat", systemImage: "plus") { editing = .topic(Topic(subject: store.data.subjectName(subject), subjectID: subject, curriculumID: curriculum)) }.disabled(subject == nil).buttonStyle(.borderedProminent)
            }
            SubjectPicker(selection: $subject).onChange(of: subject) { _, id in curriculum = store.data.curricula.first { $0.subjectID == id }?.id }
            if let subject {
                HStack {
                    Picker("Rozkład", selection: $curriculum) {
                        Text("Wszystkie rozkłady przedmiotu").tag(nil as UUID?)
                        ForEach(store.data.curricula.filter { $0.subjectID == subject }) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Button("Nowy rozkład") { planName = "Rozkład 2026/2027"; showPlan = true }
                }
                let topics = store.data.topics(for: subject, curriculumID: curriculum)
                if topics.isEmpty { EmptyPanel(title: "Rozkład czeka na tematy", message: "Dodaj tematy ręcznie lub wczytaj swój arkusz Excel.", symbol: "list.bullet.rectangle") }
                ForEach(topics) { topic in
                    HStack(alignment: .top, spacing: 16) {
                        Text("\(topic.order ?? 0).\n\(topic.hours) h").font(.headline).foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 6) { Text(topic.title).font(.headline); Text(topic.outline).lineLimit(2).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button("Edytuj") { editing = .topic(topic) }
                        Menu("Zaplanuj dla…") {
                            ForEach(store.data.classes.filter { $0.subjectID == subject }) { group in
                                Button(group.name) { editing = .lesson(Lesson(classID: group.id, topicID: topic.id)) }
                            }
                        }.fixedSize()
                        Button(role: .destructive) { deleting = topic } label: { Image(systemName: "trash") }
                    }.panel()
                }
            } else { EmptyPanel(title: "Wybierz przedmiot", message: "Zobaczysz wyłącznie jego rozkłady i tematy.", symbol: "books.vertical") }
        }
        .onAppear { if subject == nil { subject = store.data.subjects.first?.id; curriculum = store.data.curricula.first { $0.subjectID == subject }?.id } }
        .sheet(isPresented: $importSheet) { if let subject { SpreadsheetImportView(subjectID: subject, curriculumID: curriculum) } }
        .alert("Nowy rozkład", isPresented: $showPlan) {
            TextField("Nazwa rozkładu", text: $planName)
            Button("Dodaj") { if let subject, !planName.isEmpty { let plan = Curriculum(subjectID: subject, name: planName); if store.change({ $0.curricula.append(plan) }) { curriculum = plan.id } } }
            Button("Anuluj", role: .cancel) { }
        }
        .confirmationDialog("Usunąć temat? Terminy pozostaną bez tematu.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Usuń", role: .destructive) {
                guard let id = deleting?.id else { return }
                store.change { data in
                    data.topics.removeAll { $0.id == id }
                    for i in data.lessons.indices where data.lessons[i].topicID == id { data.lessons[i].topicID = nil }
                    for i in data.actions.indices where data.actions[i].topicID == id { data.actions[i].topicID = nil; data.actions[i].withMaterials = false }
                }; deleting = nil
            }
        }
    }
}
