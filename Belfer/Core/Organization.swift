import Foundation

struct Subject: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""
    var notes = ""
}
struct Curriculum: Identifiable, Codable, Equatable {
    var id = UUID()
    var subjectID: UUID
    var name = "Rozkład materiału"
}
struct EnvironmentProfile: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""
    var subjectID: UUID
    var actionIDs: [UUID] = []
}
enum ResourceRole: String, Codable, CaseIterable {
    case student = "Materiał ucznia", starter = "Projekt startowy", solution = "Rozwiązanie nauczyciela"
}
extension Resource {
    var isPrivate: Bool { teacherOnly || role == .solution }
}
extension Workspace {
    static func key(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    func subjectID(for group: SchoolClass) -> UUID? { group.subjectID ?? subjects.first { Self.key($0.name) == Self.key(group.subject) }?.id }
    func subjectID(for lesson: Lesson) -> UUID? { classes.first { $0.id == lesson.classID }.flatMap { subjectID(for: $0) } }
    func topics(for subjectID: UUID?, curriculumID: UUID? = nil) -> [Topic] {
        guard let subjectID else { return [] }
        return topics.filter { $0.subjectID == subjectID && (curriculumID == nil || $0.curriculumID == curriculumID) }
            .sorted { ($0.order ?? 0, $0.title) < ($1.order ?? 0, $1.title) }
    }
    func subjectName(_ id: UUID?) -> String { subjects.first { $0.id == id }?.name ?? "Wybierz przedmiot" }
    /// Przenosi stare nazwy tekstowe na trwałe identyfikatory. Identyfikatory istniejących obiektów pozostają.
    func normalized() throws -> Workspace {
        guard schemaVersion == 1 || schemaVersion == 3 else { throw DataError.invalid("Nieobsługiwana wersja kopii danych.") }
        var value = self
        value.schemaVersion = 3
        func ensure(_ name: String) -> UUID {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Bez przedmiotu" : name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let found = value.subjects.first(where: { Self.key($0.name) == Self.key(name) }) { return found.id }
            let item = Subject(name: name); value.subjects.append(item); return item.id
        }
        for i in value.classes.indices {
            if value.classes[i].subjectID == nil { value.classes[i].subjectID = ensure(value.classes[i].subject) }
            value.classes[i].subject = value.subjectName(value.classes[i].subjectID)
        }
        for i in value.topics.indices {
            if value.topics[i].subjectID == nil { value.topics[i].subjectID = ensure(value.topics[i].subject) }
            let subject = value.topics[i].subjectID!
            value.topics[i].subject = value.subjectName(subject)
            if value.topics[i].curriculumID == nil {
                if let existing = value.curricula.first(where: { $0.subjectID == subject }) { value.topics[i].curriculumID = existing.id }
                else { let plan = Curriculum(subjectID: subject); value.curricula.append(plan); value.topics[i].curriculumID = plan.id }
            }
            if value.topics[i].order == nil { value.topics[i].order = i + 1 }
        }
        if schemaVersion == 1 {
            for i in value.lessons.indices {
                guard let topicID = value.lessons[i].topicID, let original = value.topics.first(where: { $0.id == topicID }),
                      let subject = value.subjectID(for: value.lessons[i]), original.subjectID != subject else { continue }
                var copy = original; copy.id = UUID(); copy.subjectID = subject; copy.subject = value.subjectName(subject)
                if let plan = value.curricula.first(where: { $0.subjectID == subject }) { copy.curriculumID = plan.id }
                else { let plan = Curriculum(subjectID: subject); value.curricula.append(plan); copy.curriculumID = plan.id }
                value.topics.append(copy); value.lessons[i].topicID = copy.id
            }
            for i in value.actions.indices where value.actions[i].subjectID == nil {
                if let id = value.actions[i].lessonID, let lesson = value.lessons.first(where: { $0.id == id }) { value.actions[i].subjectID = value.subjectID(for: lesson) }
                else if let id = value.actions[i].topicID { value.actions[i].subjectID = value.topics.first(where: { $0.id == id })?.subjectID }
            }
        }
        return value
    }
    mutating func continueLesson(_ id: UUID, at start: Date) throws {
        guard let old = lessons.first(where: { $0.id == id }) else { throw DataError.invalid("Nie znaleziono lekcji.") }
        guard start > old.start else { throw DataError.invalid("Kontynuacja musi być później niż lekcja źródłowa.") }
        var next = old
        next.id = UUID(); next.start = start; next.status = .planned
        next.notes = old.nextSteps.isEmpty ? "Kontynuacja lekcji z \(old.start.formatted())." : old.nextSteps
        next.nextSteps = ""; next.continuationOf = old.id
        lessons.append(next)
    }
    mutating func shiftUpcoming(classID: UUID, from date: Date, days: Int, calendar: Calendar = .current) {
        for i in lessons.indices where lessons[i].classID == classID && lessons[i].start >= date && lessons[i].status != .completed && lessons[i].status != .cancelled {
            lessons[i].start = calendar.date(byAdding: .day, value: days, to: lessons[i].start) ?? lessons[i].start
        }
    }
    func aiContext(_ lesson: Lesson) -> String {
        let topic = topics.first { $0.id == lesson.topicID }
        let group = classes.first { $0.id == lesson.classID }
        let previous = previousLesson(before: lesson)
        return """
        Przygotuj materiały do lekcji. Używaj prostego języka i przykładów odpowiednich dla tej klasy.
        Przedmiot: \(subjectName(subjectID(for: lesson)))
        Klasa: \(group?.name ?? "") · kwalifikacja: \(group?.qualification ?? "")
        Temat: \(title(lesson))
        Czas: \(lesson.duration) min (\(lesson.blockCount ?? 1) lekcji)
        Uwagi o klasie: \(group?.notes ?? "")
        Poprzednio: \(previous?.nextSteps ?? "brak notatki")
        Scenariusz: \(topic?.outline ?? "")
        Zadanie: \(topic?.exercise ?? "")
        Uwagi nauczyciela: \(lesson.notes)
        Materiały (same nazwy, bez odczytu plików): \(materials(lesson).map(\.name).joined(separator: ", "))
        Wyjaśniaj nowe elementy i przygotuj zadanie samodzielne. Zaznacz brakujące informacje zamiast je zgadywać.
        """
    }
}
