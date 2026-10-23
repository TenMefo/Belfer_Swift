import Foundation

struct SchoolClass: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""
    var subject = ""
    var subjectID: UUID?
    var qualification = ""
    var notes = ""
}

struct Topic: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var subject = ""
    var subjectID: UUID?
    var curriculumID: UUID?
    var order: Int?
    var hours = 1
    var outline = ""
    var exercise = ""
    var resources: [Resource] = []
}

enum LessonStatus: String, Codable, CaseIterable {
    case planned = "Do przygotowania", ready = "Gotowa", completed = "Zrealizowana", cancelled = "Odwołana"
}

struct Lesson: Identifiable, Codable, Equatable {
    var id = UUID()
    var classID: UUID
    var topicID: UUID?
    var start = Date()
    var blockCount: Int?
    var continuationOf: UUID?
    var profileID: UUID?
    var duration = 45
    var room = ""
    var status = LessonStatus.planned
    var notes = ""
    var nextSteps = ""
    var resources: [Resource] = []
    var presentationReady = false
    var exerciseReady = false
    var projectReady = false
    var end: Date { start.addingTimeInterval(Double(duration) * 60) }
    var missing: [String] {
        var result: [String] = []
        if topicID == nil { result.append("temat") }
        if !presentationReady { result.append("prezentacja") }
        if !exerciseReady { result.append("zadanie") }
        if !projectReady { result.append("projekt / materiały") }
        return result
    }
}

enum ResourceKind: String, Codable, CaseIterable {
    case file = "Plik", project = "Projekt", chat = "Rozmowa AI", website = "Strona", email = "Wiadomość"
    var symbol: String {
        switch self {
        case .file: return "doc.richtext"
        case .project: return "folder.badge.gearshape"
        case .chat: return "bubble.left.and.bubble.right"
        case .website: return "link"
        case .email: return "envelope"
        }
    }
}

struct Resource: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""
    var kind = ResourceKind.file
    var location = ""
    var bookmark: Data?
    var role: ResourceRole?
    var teacherOnly = false
    var instructions = ""
}

struct WorkItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var workFolder: String?
    var details = ""
    var classID: UUID?
    var due: Date?
    var done = false
}

struct WeeklySlot: Identifiable, Codable, Equatable {
    var id = UUID()
    var classID: UUID
    var weekday = 2 // Calendar: niedziela = 1, poniedziałek = 2.
    var hour = 8
    var minute = 0
    var duration = 45
    var room = ""
}

struct Workspace: Codable, Equatable {
    var schemaVersion = 3
    var subjectCatalog: [Subject]?
    var curriculumCatalog: [Curriculum]?
    var environmentProfiles: [EnvironmentProfile]?
    var subjects: [Subject] { get { subjectCatalog ?? [] } set { subjectCatalog = newValue } }
    var curricula: [Curriculum] { get { curriculumCatalog ?? [] } set { curriculumCatalog = newValue } }
    var profiles: [EnvironmentProfile] { get { environmentProfiles ?? [] } set { environmentProfiles = newValue } }
    var classes: [SchoolClass] = []
    var topics: [Topic] = []
    var lessons: [Lesson] = []
    var tasks: [WorkItem] = []
    var slots: [WeeklySlot] = []
    var resources: [Resource] = []
    // Pole opcjonalne pozwala odczytać również kopie z wersji 0.1.
    var launchActions: [LaunchAction]?
    var actions: [LaunchAction] {
        get { launchActions ?? [] }
        set { launchActions = newValue }
    }

    func className(_ id: UUID) -> String { classes.first { $0.id == id }?.name ?? "Usunięta klasa" }
    func title(_ lesson: Lesson) -> String { topics.first { $0.id == lesson.topicID }?.title ?? "Wybierz temat" }
    func materials(_ lesson: Lesson) -> [Resource] {
        var seen = Set<UUID>()
        return ((topics.first { $0.id == lesson.topicID }?.resources ?? []) + lesson.resources).filter { seen.insert($0.id).inserted }
    }
    func previousLesson(before lesson: Lesson) -> Lesson? {
        lessons.filter { $0.classID == lesson.classID && $0.start < lesson.start && $0.status == .completed }
            .max { $0.start < $1.start }
    }
    func lessons(on date: Date, calendar: Calendar = .current) -> [Lesson] {
        lessons.filter { calendar.isDate($0.start, inSameDayAs: date) }.sorted { $0.start < $1.start }
    }
    func conflicts(with lesson: Lesson) -> Bool {
        lessons.contains { $0.id != lesson.id && $0.status != .cancelled && lesson.status != .cancelled && $0.start < lesson.end && lesson.start < $0.end }
    }
    mutating func generateWeek(containing date: Date, calendar: Calendar = .current) {
        var calendar = calendar
        calendar.firstWeekday = 2
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return }
        for day in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: day, to: interval.start) else { continue }
            for slot in slots where slot.weekday == calendar.component(.weekday, from: date) {
                guard let start = calendar.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: date) else { continue }
                // Powtórne kliknięcie nie tworzy kolejnego egzemplarza tej samej lekcji.
                if !lessons.contains(where: { $0.classID == slot.classID && $0.start == start }) {
                    lessons.append(Lesson(classID: slot.classID, start: start, duration: slot.duration, room: slot.room))
                }
            }
        }
    }
    func validated() throws -> Workspace {
        guard schemaVersion == 1 || schemaVersion == 3 else { throw DataError.invalid("Nieobsługiwana wersja kopii danych.") }
        func unique<T: Identifiable>(_ items: [T]) -> Bool where T.ID: Hashable {
            Set(items.map(\.id)).count == items.count
        }
        let classIDs = Set(classes.map(\.id)), topicIDs = Set(topics.map(\.id))
        guard unique(classes), unique(topics), unique(lessons), unique(tasks), unique(slots), unique(resources),
              classes.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              topics.allSatisfy({ !$0.title.isEmpty && (1...1000).contains($0.hours) }),
              lessons.allSatisfy({ classIDs.contains($0.classID) && ($0.topicID == nil || topicIDs.contains($0.topicID!)) && (5...480).contains($0.duration) }),
              slots.allSatisfy({ classIDs.contains($0.classID) && (1...7).contains($0.weekday) && (0...23).contains($0.hour) && (0...59).contains($0.minute) && (5...480).contains($0.duration) }),
              tasks.allSatisfy({ $0.classID == nil || classIDs.contains($0.classID!) })
        else { throw DataError.invalid("Nieprawidłowe dane lub brakujące powiązania w kopii.") }
        guard unique(actions), actions.allSatisfy({ action in
            (action.topicID == nil || topicIDs.contains(action.topicID!)) &&
            (action.lessonID == nil || lessons.contains(where: { $0.id == action.lessonID }))
        }) else { throw DataError.invalid("Nieprawidłowe powiązania akcji uruchamiania.") }
        for action in actions { try action.validate() }
        guard unique(subjects), unique(curricula), unique(profiles), Set(subjects.map { Self.key($0.name) }).count == subjects.count else { throw DataError.invalid("Powtórzone przedmioty lub identyfikatory.") }
        let subjectIDs = Set(subjects.map(\.id))
        guard subjects.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              curricula.allSatisfy({ subjectIDs.contains($0.subjectID) }),
              classes.allSatisfy({ $0.subjectID == nil || subjectIDs.contains($0.subjectID!) }),
              topics.allSatisfy({ topic in
                  (topic.subjectID == nil || subjectIDs.contains(topic.subjectID!)) &&
                  (topic.curriculumID == nil || curricula.contains { $0.id == topic.curriculumID && $0.subjectID == topic.subjectID })
              }),
              lessons.allSatisfy({ lesson in
                  (lesson.topicID == nil || topics.contains { $0.id == lesson.topicID && ($0.subjectID == nil || $0.subjectID == subjectID(for: lesson)) }) &&
                  (lesson.profileID == nil || profiles.contains { $0.id == lesson.profileID && $0.subjectID == subjectID(for: lesson) })
              }),
              profiles.allSatisfy({ profile in subjectIDs.contains(profile.subjectID) && profile.actionIDs.allSatisfy { id in actions.contains { $0.id == id && ($0.subjectID == nil || $0.subjectID == profile.subjectID) } } }),
              actions.allSatisfy({ action in
                  (action.subjectID == nil || subjectIDs.contains(action.subjectID!)) &&
                  (action.subjectID == nil || action.topicID == nil || topics.contains { $0.id == action.topicID && $0.subjectID == action.subjectID }) &&
                  (action.subjectID == nil || action.lessonID == nil || lessons.contains { $0.id == action.lessonID && subjectID(for: $0) == action.subjectID })
              })
        else { throw DataError.invalid("Przedmiot, temat, profil lub skrót nie pasują do siebie.") }
        return self
    }
    func actions(for lesson: Lesson) -> [LaunchAction] {
        let subject = subjectID(for: lesson)
        let profileIDs = profiles.first { $0.id == lesson.profileID }?.actionIDs ?? []
        return actions.filter { action in
            guard action.subjectID == nil || action.subjectID == subject else { return false }
            if profileIDs.contains(action.id) { return true }
            if let id = action.lessonID { return id == lesson.id }
            if let id = action.topicID { return id == lesson.topicID }
            return action.subjectID != nil || action.withMaterials
        }
    }
    static func demo(now: Date = Date()) -> Workspace {
        let web = SchoolClass(name: "4TI", subject: "Tworzenie stron i aplikacji internetowych", qualification: "INF.03")
        let react = SchoolClass(name: "3TP", subject: "Tworzenie aplikacji webowych", qualification: "INF.04")
        let pizza = Topic(title: "Checkbox, radio, select i onchange", subject: web.subject, outline: "5 min — powtórzenie value\n15 min — wspólny formularz zamówienia pizzy\n20 min — zadanie samodzielne\n5 min — podsumowanie", exercise: "Zbuduj konfigurator pizzy: rozmiar, dodatki i wybór sosu. Aktualizuj podsumowanie po zmianie formularza.")
        let jsx = Topic(title: "JSX i komponenty", subject: react.subject, outline: "Karta postaci: znaczniki, className i komponent stopki.", exercise: "Utwórz biogram wybranej postaci oraz stopkę w osobnym komponencie.")
        let cal = Calendar.current
        let first = cal.date(bySettingHour: 8, minute: 0, second: 0, of: now)!
        let second = cal.date(bySettingHour: 9, minute: 0, second: 0, of: now)!
        let value = Workspace(classes: [web, react], topics: [pizza, jsx], lessons: [
            Lesson(classID: web.id, topicID: pizza.id, start: first, room: "204", presentationReady: true),
            Lesson(classID: react.id, topicID: jsx.id, start: second, room: "205")
        ], tasks: [WorkItem(title: "Przygotować pliki startowe do konfiguratora pizzy", classID: web.id)], resources: [Resource(name: "Librus", kind: .website, location: "https://synergia.librus.pl")])
        return (try? value.normalized()) ?? value
    }
}

enum DataError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}
