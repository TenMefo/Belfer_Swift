import SwiftUI
import AppKit

struct LessonToolsView: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    var lesson: Lesson
    @State private var targetDate = Date()
    @State private var days = 1
    @State private var checkpoint = ""
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Plan i kontynuacja").font(.title2.bold()); Spacer(); Button("Zamknij") { dismiss() } }
            Form {
                Section("Dalszy ciąg / kopia") {
                    DatePicker("Nowy termin", selection: $targetDate)
                    HStack {
                        Button("Kontynuuj w tym terminie") {
                            do { var data = store.data; try data.continueLesson(lesson.id, at: targetDate); if store.change({ $0 = data }) { dismiss() } }
                            catch { message = error.localizedDescription }
                        }
                        Button("Duplikuj lekcję") { var next = lesson; next.id = UUID(); next.start = targetDate; next.status = .planned; next.nextSteps = ""; if store.change({ $0.lessons.append(next) }) { dismiss() } }
                    }
                    Text("Kontynuacja zachowuje temat, materiały i profil. Notatka „co dalej” staje się punktem startowym nowych zajęć.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Przesuń kolejne terminy tej klasy i przedmiotu") {
                    Stepper("Przesunięcie o \(days) dni", value: $days, in: -60...60)
                    Button("Przesuń od tej lekcji") {
                        store.change { $0.shiftUpcoming(classID: lesson.classID, from: lesson.start, days: days) }
                        message = "Przesunięto niezrealizowane terminy. Kolizje zobaczysz w planie tygodnia."
                    }.disabled(days == 0)
                    Text("Zrealizowane i odwołane zajęcia pozostają bez zmian. Przesunięcie nie uwzględnia automatycznie świąt ani zastępstw.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Postęp w bloku lekcyjnym") {
                    MultilineField(title: "Co udało się zrobić na tej godzinie", text: $checkpoint)
                    Button("Dopisz punkt kontrolny") {
                        store.change { data in
                            if let i = data.lessons.firstIndex(where: { $0.id == lesson.id }) {
                                data.lessons[i].notes += "\n[\(Date().formatted(date: .omitted, time: .shortened))] \(checkpoint)"
                            }
                        }; checkpoint = ""; message = "Zapisano punkt kontrolny."
                    }.disabled(checkpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.formStyle(.grouped)
            if let message { Text(message).foregroundStyle(.secondary) }
        }.padding(24).frame(width: 760, height: 720)
            .onAppear { targetDate = Calendar.current.date(byAdding: .day, value: 7, to: lesson.start) ?? Date() }
    }
}
