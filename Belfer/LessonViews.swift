import SwiftUI
import AppKit
import QuickLook

struct LessonRow: View {
    @EnvironmentObject var store: WorkspaceStore
    var lesson: Lesson
    var selected = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(lesson.start.formatted(date: .omitted, time: .shortened)).font(.headline.monospacedDigit())
                    Text("– \(lesson.end.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
                    Spacer()
                    Text(store.data.className(lesson.classID)).font(.headline).foregroundStyle(.indigo)
                }
                Text(store.data.title(lesson)).font(.headline).multilineTextAlignment(.leading)
                HStack {
                    Label(lesson.room.isEmpty ? "Bez sali" : lesson.room, systemImage: "door.left.hand.open").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    StatusPill(status: lesson.status)
                }
                if lesson.status == .planned || (lesson.status == .ready && !lesson.missing.isEmpty) {
                    Text(lesson.missing.isEmpty ? "Lista przygotowania uzupełniona" : "Sprawdź: \(lesson.missing.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.orange)
                }
                if store.data.conflicts(with: lesson) { Label("Konflikt godzin", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red) }
            }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Color.indigo.opacity(0.07) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(selected ? Color.indigo.opacity(0.5) : Color.primary.opacity(0.06)))
        }.buttonStyle(.plain)
    }
}
struct LessonDetail: View {
    @EnvironmentObject var store: WorkspaceStore
    var id: UUID
    var edit: (Lesson) -> Void
    @State private var finish = false
    @State private var nextSteps = ""
    @State private var delete = false
    @State private var teaching = false
    @State private var preview: URL?

    var body: some View {
        if let lesson = store.data.lessons.first(where: { $0.id == id }) {
            let topic = store.data.topics.first { $0.id == lesson.topicID }
            let materials = store.data.materials(lesson)
            VStack(alignment: .leading, spacing: 20) {
                HStack { Label("Karta lekcji", systemImage: "book.closed").font(.headline); Spacer(); Button("Edytuj") { edit(lesson) } }
                Text(store.data.title(lesson)).font(.system(size: 25, weight: .bold, design: .rounded))
                Text("\(store.data.className(lesson.classID)) · \(lesson.duration) minut · sala \(lesson.room.isEmpty ? "—" : lesson.room)").foregroundStyle(.secondary)
                HStack {
                    StatusPill(status: lesson.status)
                    Spacer()
                    Button("Kopiuj temat") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.data.title(lesson), forType: .string) }.disabled(topic == nil)
                }
                if let previous = store.data.previousLesson(before: lesson), !previous.nextSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Ostatnio z tą klasą", systemImage: "arrow.uturn.backward").font(.subheadline.bold())
                        Text(previous.nextSteps).textSelection(.enabled)
                        Text(previous.start.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                }
                if let topic, !topic.outline.isEmpty { detailSection("Przebieg lekcji", text: topic.outline) }
                if let topic, !topic.exercise.isEmpty {
                    detailSection("Zadanie dla uczniów", text: topic.exercise)
                    Button("Kopiuj polecenie") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(topic.exercise, forType: .string) }
                }
                Divider()
                Text("Materiały i projekty").font(.headline)
                if materials.isEmpty { Text("Przypnij pliki, folder projektu albo rozmowę w edycji lekcji lub tematu.").foregroundStyle(.secondary) }
                ForEach(materials) { resource in
                    ResourceRow(resource: resource) {
                        do { preview = try store.resolvedURL(resource) }
                        catch { store.error = error.localizedDescription }
                    }
                }
                HStack {
                    Button("Otwórz materiały uczniów", systemImage: "arrow.up.right.square") { store.openStudentMaterials(materials) }.disabled(materials.filter { !$0.teacherOnly }.isEmpty)
                    Button("Tryb lekcji", systemImage: "play.rectangle") { teaching = true }
                }
                if !lesson.notes.isEmpty { detailSection("Notatki nauczyciela", text: lesson.notes) }
                if !lesson.nextSteps.isEmpty { detailSection("Co dalej", text: lesson.nextSteps) }
                Divider()
                HStack {
                    if lesson.status != .completed && lesson.status != .cancelled {
                        Button("Zakończ lekcję", systemImage: "checkmark.circle") { nextSteps = lesson.nextSteps; finish = true }.buttonStyle(.borderedProminent)
                    }
                    if lesson.status == .planned {
                        Button("Oznacz jako gotową") { var value = lesson; value.status = .ready; store.change { $0.lessons.upsert(value) } }
                    }
                    Spacer()
                    Button(role: .destructive) { delete = true } label: { Image(systemName: "trash") }.help("Usuń ten termin lekcji")
                }
            }.panel()
                .quickLookPreview($preview)
                .sheet(isPresented: $finish) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Na czym skończyliście?").font(.title2.bold())
                        Text("Ta notatka pojawi się przy następnej lekcji tej klasy.").foregroundStyle(.secondary)
                        MultilineField(title: "Dalszy ciąg", text: $nextSteps)
                        HStack {
                            Button("Anuluj") { finish = false }
                            Spacer()
                            Button("Zapisz i zakończ") {
                                var value = lesson; value.status = .completed; value.nextSteps = nextSteps
                                if store.change({ $0.lessons.upsert(value) }) { finish = false }
                            }.buttonStyle(.borderedProminent)
                        }
                    }.padding(28).frame(width: 580, height: 340)
                }
                .sheet(isPresented: $teaching) {
                    TeachingView(title: store.data.title(lesson), exercise: topic?.exercise ?? "", resources: materials.filter { !$0.teacherOnly })
                }
                .confirmationDialog("Usunąć ten termin lekcji? Temat i jego materiały zostaną zachowane.", isPresented: $delete) {
                    Button("Usuń lekcję", role: .destructive) { store.change { $0.lessons.removeAll { $0.id == id } } }
                }
        }
    }
    private func detailSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(.headline); Text(text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
    }
}
struct ResourceRow: View {
    @EnvironmentObject var store: WorkspaceStore
    var resource: Resource
    var preview: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: resource.kind.symbol).foregroundStyle(.indigo).frame(width: 22)
                VStack(alignment: .leading) {
                    Text(resource.name).font(.subheadline.bold())
                    Text(resource.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                }
                if resource.teacherOnly { Image(systemName: "lock.fill").foregroundStyle(.orange).help("Tylko dla nauczyciela") }
                Spacer()
                if resource.kind == .file, let preview { Button("Podgląd", action: preview) }
                Button("Otwórz") { store.open(resource) }
            }
            if !resource.instructions.isEmpty { Text(resource.instructions).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }.padding(12).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
    }
}
struct TeachingView: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    var title: String
    var exercise: String
    var resources: [Resource]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { Label("Lekcja", systemImage: "play.rectangle").foregroundStyle(.indigo); Spacer(); Button("Zamknij") { dismiss() } }
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(title).font(.system(size: 38, weight: .bold, design: .rounded))
                    Text(exercise.isEmpty ? "Zadanie zostanie omówione przez nauczyciela." : exercise).font(.title2).textSelection(.enabled)
                    ForEach(resources) { resource in
                        HStack { Label(resource.name, systemImage: resource.kind.symbol); Spacer(); Button("Otwórz") { store.open(resource) } }.padding().panel()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(36).frame(minWidth: 850, minHeight: 620)
    }
}
