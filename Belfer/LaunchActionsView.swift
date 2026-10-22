import SwiftUI
import AppKit

struct LaunchActionsView: View {
    @EnvironmentObject var store: WorkspaceStore
    @EnvironmentObject var runner: ActionRunner
    @State private var editing: LaunchAction?
    @State private var deleting: LaunchAction?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                PageHeading(eyebrow: "Uruchamianie", title: "Środowisko gotowe jednym kliknięciem.", subtitle: "Aplikacje, projekty i obsługa usług — bez przepisywania poleceń.")
                Menu("Dodaj akcję") {
                    Button("Aplikacja…") { editing = LaunchAction() }
                    Button("Visual Studio Code…") { editing = .vscode() }
                    Button("Własne polecenie…") { editing = LaunchAction(kind: .command) }
                    Divider()
                    ForEach(["start", "stop", "restart", "status"], id: \.self) { operation in
                        Button(LaunchAction.xampp(operation).name + "…") { editing = .xampp(operation) }
                    }
                }.fixedSize()
            }
            HStack {
                Button("Dodaj przyciski XAMPP", systemImage: "server.rack") { addXampp() }
                Button("Dodaj VS Code") { editing = .vscode() }
                Spacer()
                Button("Pokaż wynik poleceń", systemImage: "terminal") { runner.showingOutput = true }
            }
            Text("Przypnij akcję do kokpitu lub powiąż ją z tematem / terminem lekcji. Opcja „Razem z materiałami” dołącza ją do otwierania zestawu lekcyjnego. Hasło administratora wpisujesz wyłącznie w systemowym oknie macOS.").foregroundStyle(.secondary).panel()
            if runner.busy { ProgressView("Wykonywanie: \(runner.currentName)…").controlSize(.small) }
            if store.data.actions.isEmpty {
                EmptyPanel(title: "Dodaj pierwszą akcję", message: "Dla XAMPP możesz od razu utworzyć przyciski start, stop, restart i status. Przy VS Code wybierz też folder projektu.", symbol: "play.circle")
            }
            ForEach(store.data.actions) { action in
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: action.symbol).font(.title2).foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(action.name).font(.headline)
                            Text(scope(action)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if action.pinned { Image(systemName: "pin.fill").foregroundStyle(.indigo) }
                        if action.administrator { Label("Administrator", systemImage: "lock.shield").font(.caption).foregroundStyle(.orange) }
                        RunActionButton(action: action)
                        Button("Edytuj") { editing = action }
                        Button(role: .destructive) { deleting = action } label: { Image(systemName: "trash") }
                    }
                    Text(action.displayCommand).font(.caption.monospaced()).textSelection(.enabled).foregroundStyle(.secondary)
                    if let result = runner.results[action.id] {
                        HStack {
                            Label(result.succeeded ? "Polecenie wykonane" : "Sprawdź wynik", systemImage: result.succeeded ? "checkmark.circle" : "exclamationmark.triangle")
                                .foregroundStyle(result.succeeded ? Color.green : Color.orange)
                            Text("kod \(result.exitCode)").foregroundStyle(.secondary)
                        }.font(.caption)
                        if !result.output.isEmpty { Text(result.output).font(.caption.monospaced()).lineLimit(5).textSelection(.enabled) }
                    }
                }.panel()
            }
        }
        .sheet(item: $editing) { LaunchActionEditor(item: $0) }
        .confirmationDialog("Usunąć przypiętą akcję? Nie spowoduje to zatrzymania aplikacji ani usług.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Usuń akcję", role: .destructive) {
                if let id = deleting?.id { store.change { $0.actions.removeAll { $0.id == id } } }
                deleting = nil
            }
        }
    }
    private func scope(_ action: LaunchAction) -> String {
        var labels = [action.kind.rawValue]
        if let id = action.topicID { labels.append(store.data.topics.first { $0.id == id }?.title ?? "Temat") }
        if let id = action.lessonID, let lesson = store.data.lessons.first(where: { $0.id == id }) { labels.append("\(store.data.className(lesson.classID)) · \(lesson.start.formatted(date: .abbreviated, time: .shortened))") }
        if action.withMaterials { labels.append("razem z materiałami") }
        return labels.joined(separator: " · ")
    }
    private func addXampp() {
        store.change { data in
            for operation in ["start", "stop", "restart", "status"] {
                let action = LaunchAction.xampp(operation)
                if !data.actions.contains(where: { $0.kind == .command && $0.executable == action.executable && $0.arguments == action.arguments }) {
                    data.actions.append(action)
                }
            }
        }
    }
}
struct RunActionButton: View {
    @EnvironmentObject var runner: ActionRunner
    var action: LaunchAction
    var body: some View {
        Button { runner.run([action]) } label: {
            Label(action.name, systemImage: action.symbol)
        }.disabled(runner.busy).help(action.displayCommand)
    }
}
struct ActionOutputView: View {
    @EnvironmentObject var runner: ActionRunner
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Wynik uruchamiania").font(.title2.bold())
                Spacer()
                Button("Zamknij") { dismiss() }
            }
            if runner.busy { ProgressView("\(runner.currentName)…") }
            ScrollView {
                Text(runner.transcript.isEmpty ? "Nie uruchamiano jeszcze żadnej akcji w tej sesji." : runner.transcript)
                    .font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }.background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }.padding(24).frame(width: 800, height: 580)
    }
}
