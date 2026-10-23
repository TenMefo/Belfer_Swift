import Foundation
import SwiftUI

struct WeekView: View {
    @EnvironmentObject var store: WorkspaceStore
    @Binding var date: Date
    @Binding var editing: EditRequest?
    @Binding var selectedLesson: UUID?
    @State private var showingDetail: Lesson?
    @State private var deletingSlot: WeeklySlot?
    private var days: [Date] {
        var cal = Calendar.current; cal.firstWeekday = 2
        let start = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeading(eyebrow: "Plan tygodnia", title: "Zobacz, co przed Tobą.", subtitle: "Terminy lekcji i stały szablon godzin.")
            HStack {
                Button { moveWeek(-1) } label: { Image(systemName: "chevron.left") }
                Text("\(days.first!.formatted(date: .abbreviated, time: .omitted)) – \(days.last!.formatted(date: .abbreviated, time: .omitted))").font(.headline)
                Button { moveWeek(1) } label: { Image(systemName: "chevron.right") }
                Spacer()
                Button("Bieżący tydzień") { date = Date() }
                Button("Wypełnij z szablonu") { store.change { $0.generateWeek(containing: date) } }.disabled(store.data.slots.isEmpty)
                Button("Dodaj lekcję", systemImage: "plus") {
                    if let first = store.data.classes.first { editing = .lesson(Lesson(classID: first.id, start: date)) }
                }.buttonStyle(.borderedProminent).disabled(store.data.classes.isEmpty)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), alignment: .top)], alignment: .leading, spacing: 18) {
                ForEach(days, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(day.formatted(.dateTime.weekday(.wide).day().month().locale(Locale(identifier: "pl_PL")))).font(.headline)
                            Spacer()
                            if Calendar.current.isDateInToday(day) { Circle().fill(.indigo).frame(width: 8, height: 8) }
                        }
                        let lessons = store.data.lessons(on: day)
                        if lessons.isEmpty { Text("Bez zajęć").font(.caption).foregroundStyle(.secondary).padding(.vertical, 20) }
                        ForEach(lessons) { lesson in LessonRow(lesson: lesson) { showingDetail = lesson } }
                    }.panel()
                }
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Stały plan godzin").font(.title2.bold())
                    Text("Zmiana szablonu nie zmienia utworzonych terminów. Odwołania i zastępstwa edytuj na konkretnej lekcji.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Dodaj godzinę") { if let first = store.data.classes.first { editing = .slot(WeeklySlot(classID: first.id)) } }.disabled(store.data.classes.isEmpty)
            }
            ForEach(store.data.slots.sorted { ($0.weekday == 1 ? 8 : $0.weekday, $0.hour, $0.minute) < ($1.weekday == 1 ? 8 : $1.weekday, $1.hour, $1.minute) }) { slot in
                HStack {
                    Text("\(dayName(slot.weekday)) · \(String(format: "%02d:%02d", slot.hour, slot.minute))").font(.headline).frame(width: 220, alignment: .leading)
                    Text("\(store.data.className(slot.classID)) · sala \(slot.room)")
                    Spacer()
                    Button("Edytuj") { editing = .slot(slot) }
                    Button(role: .destructive) { deletingSlot = slot } label: { Image(systemName: "trash") }
                }.panel()
            }
        }
        .sheet(item: $showingDetail) { item in
            ScrollView { LessonDetail(id: item.id) { lesson in showingDetail = nil; editing = .lesson(lesson) }.padding(24) }.frame(width: 760, height: 760)
        }
        .confirmationDialog("Usunąć godzinę ze stałego planu?", isPresented: Binding(get: { deletingSlot != nil }, set: { if !$0 { deletingSlot = nil } })) {
            Button("Usuń", role: .destructive) {
                if let id = deletingSlot?.id { store.change { $0.slots.removeAll { $0.id == id } } }
                deletingSlot = nil
            }
        }
    }
    private func moveWeek(_ offset: Int) { date = Calendar.current.date(byAdding: .day, value: offset * 7, to: date)! }
    private func dayName(_ day: Int) -> String { [1: "Niedziela", 2: "Poniedziałek", 3: "Wtorek", 4: "Środa", 5: "Czwartek", 6: "Piątek", 7: "Sobota"][day] ?? "" }
}

struct ClassesView: View {
    @EnvironmentObject var store: WorkspaceStore
    @Binding var editing: EditRequest?
    @State private var deleting: SchoolClass?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                PageHeading(eyebrow: "Twoje grupy", title: "Każda klasa ma swój rytm.", subtitle: "Postęp wynika z faktycznie zrealizowanych lekcji.")
                Button("Dodaj klasę", systemImage: "plus") { editing = .schoolClass(SchoolClass()) }.buttonStyle(.borderedProminent)
            }
            if store.data.classes.isEmpty { EmptyPanel(title: "Tu pojawią się Twoje klasy", message: "Dodaj klasę i przedmiot. Tę samą klasę możesz dodać osobno dla różnych przedmiotów.", symbol: "person.3") }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340))], spacing: 18) {
                ForEach(store.data.classes) { item in
                    let lessons = store.data.lessons.filter { $0.classID == item.id }
                    let completed = lessons.filter { $0.status == .completed }
                    let active = lessons.filter { $0.status != .cancelled }
                    let last = completed.max { $0.start < $1.start }
                    let plannedHours = store.data.topics.filter { $0.subject == item.subject }.reduce(0) { $0 + $1.hours }
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(item.name).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.indigo)
                            Spacer()
                            Text(item.qualification).font(.caption.bold()).padding(7).background(.indigo.opacity(0.08), in: Capsule())
                        }
                        Text(item.subject).font(.headline)
                        ProgressView(value: Double(completed.count), total: Double(max(active.count, 1)))
                        Text("Zrealizowane terminy: \(completed.count) / \(active.count)").font(.caption).foregroundStyle(.secondary)
                        Text("Rozkład dla przedmiotu: \(plannedHours) h · zrealizowany czas: \(completed.reduce(0) { $0 + $1.duration }) min").font(.caption).foregroundStyle(.secondary)
                        if let last {
                            Text("Ostatni temat: \(store.data.title(last))").font(.subheadline.bold())
                            if !last.nextSteps.isEmpty { Text(last.nextSteps).foregroundStyle(.secondary) }
                        } else { Text("Pierwsza lekcja jeszcze przed Wami.").foregroundStyle(.secondary) }
                        if !item.notes.isEmpty { Text(item.notes).font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            Button("Edytuj") { editing = .schoolClass(item) }
                            Button("Zaplanuj lekcję") { editing = .lesson(Lesson(classID: item.id)) }
                            Spacer()
                            Button(role: .destructive) { deleting = item } label: { Image(systemName: "trash") }
                        }
                    }.panel()
                }
            }
        }
        .confirmationDialog("Usunięcie klasy usunie też jej terminy i stały plan. Zadania staną się ogólne. Tematy pozostaną.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Usuń klasę i jej terminy", role: .destructive) {
                if let id = deleting?.id {
                    store.change {
                        let removedLessons = Set($0.lessons.filter { $0.classID == id }.map(\.id))
                        for index in $0.actions.indices where $0.actions[index].lessonID.map({ removedLessons.contains($0) }) == true { $0.actions[index].lessonID = nil; $0.actions[index].withMaterials = false }
                        $0.classes.removeAll { $0.id == id }; $0.lessons.removeAll { $0.classID == id }; $0.slots.removeAll { $0.classID == id }
                        for index in $0.tasks.indices where $0.tasks[index].classID == id { $0.tasks[index].classID = nil }
                    }
                }
                deleting = nil
            }
        }
    }
}
