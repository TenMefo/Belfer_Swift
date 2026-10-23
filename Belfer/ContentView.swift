import Foundation
import SwiftUI
import AppKit

enum Destination: String, CaseIterable, Identifiable {
    case today = "Dzisiaj", subjects = "Przedmioty", week = "Tydzień", classes = "Klasy", topics = "Rozkłady", materials = "Materiały", launch = "Uruchamianie", inbox = "Do zrobienia", settings = "Ustawienia"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .subjects: return "books.vertical"
        case .today: return "square.grid.2x2"
        case .week: return "calendar"
        case .classes: return "person.3"
        case .topics: return "list.bullet.rectangle"
        case .materials: return "folder"
        case .launch: return "play.circle"
        case .inbox: return "checklist"
        case .settings: return "gearshape"
        }
    }
}
struct ContentView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var runner: ActionRunner
    @State private var destination: Destination? = .today
    @State private var date = Date()
    @State private var selectedLesson: UUID?
    @State private var editing: EditRequest?
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    Image(systemName: "graduationcap.fill").font(.title).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(.indigo.gradient, in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading) {
                        Text("Belfer").font(.title2.bold())
                        Text("Twoje centrum dowodzenia").font(.caption2).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 18).padding(.top, 24)
                List(Destination.allCases, selection: $destination) { page in
                    Label(page.rawValue, systemImage: page.symbol).padding(.vertical, 7).tag(page)
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 8) {
                    Label("Przestrzeń lokalna", systemImage: "internaldrive").font(.caption.bold())
                    Text("Materiały pod ręką. Spokojniejszy dzień.").font(.caption).foregroundStyle(.secondary)
                }.padding(18)
            }.navigationSplitViewColumnWidth(min: 205, ideal: 225, max: 260)
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Szukaj tematów, klas, materiałów i notatek…  ⌘K", text: $search).textFieldStyle(.plain).focused($searchFocused)
                    if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                    Spacer()
                    Menu {
                        Button("Librus") { store.open(Resource(name: "Librus", kind: .website, location: "https://synergia.librus.pl")) }
                        Button("ChatGPT") { store.open(Resource(name: "ChatGPT", kind: .website, location: "https://chatgpt.com")) }
                        Button("Gemini") { store.open(Resource(name: "Gemini", kind: .website, location: "https://gemini.google.com")) }
                        Button("Poczta") { NSWorkspace.shared.open(URL(string: "mailto:")!) }
                    } label: { Label("Skróty", systemImage: "arrow.up.right.square") }.fixedSize()
                }.padding(20).background(.bar)
                if let notice = store.backupNotice { Label(notice, systemImage: "externaldrive.badge.exclamationmark").font(.caption).foregroundStyle(.orange).padding(12) }
                if store.locked {
                    Label("Dane wymagają przywrócenia kopii w Ustawieniach. Zapis jest zablokowany.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).padding(12)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { searchResults }
                        else {
                            switch destination ?? .today {
                            case .today: dashboard
                            case .subjects: SubjectsView()
                            case .week: WeekView(date: $date, editing: $editing, selectedLesson: $selectedLesson)
                            case .classes: ClassesView(editing: $editing)
                            case .topics: TopicsView(editing: $editing)
                            case .materials: LibraryView()
                            case .launch: LaunchActionsView()
                            case .inbox: TasksView(editing: $editing)
                            case .settings: SettingsView()
                            }
                        }
                    }.padding(28)
                }.background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .sheet(item: $editing) { request in
            switch request {
            case .schoolClass(let item): ClassEditor(item: item)
            case .topic(let item): TopicEditor(item: item)
            case .lesson(let item): LessonEditor(item: item)
            case .task(let item): TaskEditor(item: item)
            case .slot(let item): SlotEditor(item: item)
            }
        }
        .sheet(isPresented: $runner.showingOutput) { ActionOutputView() }
        .alert("Belfer", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in runner.stopAll() }
        .onReceive(NotificationCenter.default.publisher(for: .belferSearch)) { _ in searchFocused = true }
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                PageHeading(eyebrow: "Twój dzień", title: "Dobra lekcja zaczyna się tutaj.", subtitle: date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Locale(identifier: "pl_PL"))))
                Button { newLesson() } label: { Label("Dodaj lekcję", systemImage: "plus") }.buttonStyle(.borderedProminent).disabled(store.data.classes.isEmpty)
            }
            HStack {
                Button("Dzisiaj") { selectDay(Date()) }
                Button("Przygotuj jutro", systemImage: "sun.max") { selectDay(Calendar.current.date(byAdding: .day, value: 1, to: Date())!) }
                Spacer()
                DatePicker("Dzień", selection: $date, displayedComponents: .date).fixedSize()
            }
            if !dashboardActions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Szybkie uruchamianie").font(.headline)
                        Spacer()
                        if runner.busy { ProgressView().controlSize(.small); Text(runner.currentName).font(.caption) }
                        Button("Wynik") { runner.showingOutput = true }
                        Button("Zarządzaj") { destination = .launch }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190))], alignment: .leading, spacing: 10) {
                        ForEach(dashboardActions) { RunActionButton(action: $0) }
                    }
                }.panel()
            }
            let lessons = store.data.lessons(on: date)
            HStack(spacing: 16) {
                metric("LEKCJE", value: "\(lessons.filter { $0.status != .cancelled }.count)", symbol: "calendar", color: .indigo)
                metric("GOTOWE / ZREALIZOWANE", value: "\(lessons.filter { $0.status == .ready || $0.status == .completed }.count)", symbol: "checkmark.seal", color: .green)
                metric("DO DOPRACOWANIA", value: "\(lessons.filter { $0.status == .planned || ($0.status == .ready && !$0.missing.isEmpty) }.count)", symbol: "pencil.and.outline", color: .orange)
            }
            if store.data.classes.isEmpty {
                EmptyPanel(title: "Zacznij od przedmiotu i klasy", message: "Dodaj klasę, utwórz temat i zaplanuj lekcję. Możesz też wczytać przykładowy kokpit.", symbol: "graduationcap")
                HStack {
                    Button(store.data.subjects.isEmpty ? "Dodaj przedmiot" : "Dodaj klasę") { if store.data.subjects.isEmpty { destination = .subjects } else { editing = .schoolClass(SchoolClass()) } }.buttonStyle(.borderedProminent)
                    if store.data == Workspace() { Button("Zobacz przykład") { _ = store.change { $0 = .demo() } } }
                }
            } else if lessons.isEmpty {
                EmptyPanel(title: "W tym dniu nie ma jeszcze zajęć", message: "Dodaj lekcję albo wypełnij tydzień ze stałego planu.", symbol: "calendar.badge.plus")
            } else {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Plan i przygotowanie").font(.title3.bold())
                        ForEach(lessons) { lesson in
                            LessonRow(lesson: lesson, selected: lesson.id == activeLessonID(lessons)) { selectedLesson = lesson.id }
                        }
                    }.frame(width: 340)
                    if let id = activeLessonID(lessons) {
                        LessonDetail(id: id) { editing = .lesson($0) }.frame(maxWidth: .infinity)
                    }
                }
            }
            DisclosureGroup("Przygotowanie najbliższych 7 dni") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.data.lessons.filter { $0.start >= Calendar.current.startOfDay(for: date) && $0.start < date.addingTimeInterval(7 * 86400) && $0.status != .completed && $0.status != .cancelled }.sorted { $0.start < $1.start }) { lesson in
                        Button("\(lesson.start.formatted(date: .abbreviated, time: .shortened)) · \(store.data.className(lesson.classID)) · \(lesson.missing.isEmpty ? "przygotowanie odhaczone" : lesson.missing.joined(separator: ", "))") { self.date = lesson.start; selectedLesson = lesson.id }
                    }
                }.padding(.top, 12)
            }.panel()
            let pending = store.data.tasks.filter { !$0.done && ($0.due.map { Calendar.current.startOfDay(for: $0) <= Calendar.current.startOfDay(for: date) } ?? true) }
            if !pending.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("Pamiętaj też o…").font(.title3.bold()); Spacer(); Button("Wszystkie zadania") { destination = .inbox } }
                    ForEach(pending.prefix(5)) { task in TaskRow(item: task) { editing = .task(task) } }
                }.panel()
            }
        }
    }
    private var dashboardActions: [LaunchAction] {
        let lessons = store.data.lessons(on: date)
        let lesson = lessons.first { $0.id == selectedLesson } ?? lessons.first
        let subject = lesson.flatMap { store.data.subjectID(for: $0) }
        return store.data.actions.filter { $0.pinned && ($0.subjectID == nil || $0.subjectID == subject) }
    }
    private func metric(_ label: String, value: String, symbol: String, color: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 10) {
                Text(label).font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                Text(value).font(.system(size: 30, weight: .bold, design: .rounded))
            }
            Spacer()
            Image(systemName: symbol).font(.title2).foregroundStyle(color).padding(13).background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        }.panel()
    }
    private func activeLessonID(_ lessons: [Lesson]) -> UUID? {
        lessons.first { $0.id == selectedLesson }?.id ?? lessons.first?.id
    }
    private func selectDay(_ day: Date) { date = day; selectedLesson = nil }
    private func newLesson() {
        guard let first = store.data.classes.first else { return }
        editing = .lesson(Lesson(classID: first.id, start: Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: date)!))
    }
    private var searchResults: some View {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let classes = store.data.classes.filter { "\($0.name) \($0.subject) \($0.notes)".localizedStandardContains(query) }
        let topics = store.data.topics.filter { "\($0.title) \($0.subject) \($0.outline) \($0.exercise)".localizedStandardContains(query) }
        let lessons = store.data.lessons.filter { "\(store.data.title($0)) \(store.data.className($0.classID)) \($0.notes) \($0.nextSteps)".localizedStandardContains(query) }.sorted { $0.start < $1.start }
        let tasks = store.data.tasks.filter { "\($0.title) \($0.details)".localizedStandardContains(query) }
        let resources = allResources(store.data).filter { "\($0.name) \($0.location) \($0.instructions)".localizedStandardContains(query) }
        return VStack(alignment: .leading, spacing: 16) {
            PageHeading(eyebrow: "Wyszukiwanie", title: "Wszystko pod ręką", subtitle: "Wyniki dla: \(query)")
            if classes.isEmpty && topics.isEmpty && lessons.isEmpty && tasks.isEmpty && resources.isEmpty {
                EmptyPanel(title: "Brak wyników", message: "Spróbuj nazwy klasy, fragmentu tematu albo nazwy pliku.", symbol: "magnifyingglass")
            }
            ForEach(classes) { item in Button("Klasa: \(item.name) · \(item.subject)") { editing = .schoolClass(item) } }
            ForEach(topics) { item in Button("Temat: \(item.title)") { editing = .topic(item) } }
            ForEach(lessons) { item in
                Button("Lekcja: \(store.data.className(item.classID)) · \(store.data.title(item)) · \(item.start.formatted())") {
                    date = item.start; selectedLesson = item.id; destination = .today; search = ""
                }
            }
            ForEach(tasks) { item in Button("Zadanie: \(item.title)") { editing = .task(item) } }
            ForEach(resources) { item in Button("Materiał: \(item.name)") { store.open(item) } }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

func allResources(_ data: Workspace) -> [Resource] {
    var seen = Set<UUID>()
    return (data.resources + data.topics.flatMap(\.resources) + data.lessons.flatMap(\.resources)).filter { seen.insert($0.id).inserted }
}
