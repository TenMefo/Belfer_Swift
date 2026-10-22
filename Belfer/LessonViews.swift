import Foundation
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
    @EnvironmentObject var runner: ActionRunner
    @State private var editingAction: LaunchAction?
    var id: UUID
    var edit: (Lesson) -> Void
    @State private var finish = false
    @State private var nextSteps = ""
    @State private var delete = false
    @Environment(\.openWindow) private var openWindow
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
                    Button("Otwórz materiały uczniów", systemImage: "arrow.up.right.square") {
                        runner.run(store.data.actions(for: lesson).filter { $0.withMaterials }) { store.openStudentMaterials(materials) }
                    }.disabled(runner.busy || (materials.filter { !$0.teacherOnly }.isEmpty && !store.data.actions(for: lesson).contains { $0.withMaterials }))
                    Button("Tryb lekcji", systemImage: "play.rectangle") { openWindow(id: "teaching", value: lesson.id) }
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Środowisko lekcji").font(.headline)
                        Spacer()
                        Menu("Dodaj akcję") {
                            Button("VS Code i folder projektu…") {
                                var action = LaunchAction.vscode(); action.lessonID = lesson.id; action.withMaterials = true
                                editingAction = action
                            }
                            Button("Start XAMPP…") {
                                var action = LaunchAction.xampp("start"); action.lessonID = lesson.id; action.withMaterials = true
                                editingAction = action
                            }
                            Button("Zatrzymaj XAMPP…") {
                                var action = LaunchAction.xampp("stop"); action.lessonID = lesson.id
                                editingAction = action
                            }
                            Button("Własna akcja…") { var action = LaunchAction(); action.lessonID = lesson.id; editingAction = action }
                        }.fixedSize()
                    }
                    ForEach(store.data.actions(for: lesson)) { action in
                        HStack {
                            RunActionButton(action: action)
                            if action.withMaterials { Text("razem z materiałami").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button("Edytuj") { editingAction = action }
                        }
                    }
                    if runner.busy { ProgressView("\(runner.currentName)…").controlSize(.small) }
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
                .sheet(item: $editingAction) { LaunchActionEditor(item: $0) }
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
                .confirmationDialog("Usunąć ten termin lekcji? Temat i jego materiały zostaną zachowane.", isPresented: $delete) {
                    Button("Usuń lekcję", role: .destructive) { store.change { data in data.lessons.removeAll { $0.id == id }; for i in data.actions.indices where data.actions[i].lessonID == id { data.actions[i].lessonID = nil; data.actions[i].withMaterials = false } } }
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
    var close: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { Label("Lekcja", systemImage: "play.rectangle").foregroundStyle(.indigo); Spacer(); Button("Zamknij") { if let close { close() } else { dismiss() } } }
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

struct TeachingWindow: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismissWindow) private var dismissWindow
    var id: UUID
    var body: some View {
        if let lesson = store.data.lessons.first(where: { $0.id == id }) {
            TeachingView(
                title: store.data.title(lesson),
                exercise: store.data.topics.first(where: { $0.id == lesson.topicID })?.exercise ?? "",
                resources: store.data.materials(lesson).filter { !$0.teacherOnly },
                close: { dismissWindow(id: "teaching", value: id) }
            )
        } else {
            EmptyPanel(title: "Lekcja nie jest już dostępna", message: "Termin został usunięty. Możesz zamknąć to okno.")
        }
    }
}
