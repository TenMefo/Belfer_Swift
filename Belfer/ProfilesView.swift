import SwiftUI

struct ProfilesView: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    @State var subjectID: UUID?
    @State private var name = ""
    @State private var selected: Set<UUID> = []
    @State private var editingID: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Profile środowiska").font(.title2.bold()); Spacer(); Button("Zamknij") { dismiss() } }
            SubjectPicker(selection: $subjectID).onChange(of: subjectID) { _, _ in selected = []; editingID = nil; name = "" }
            TextField("Nazwa, np. PHP — VS Code + XAMPP", text: $name)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(store.data.actions.filter { $0.subjectID == nil || $0.subjectID == subjectID }) { action in
                        Toggle(action.name, isOn: Binding(get: { selected.contains(action.id) }, set: { if $0 { selected.insert(action.id) } else { selected.remove(action.id) } }))
                    }
                    Button(editingID == nil ? "Zapisz nowy profil" : "Zapisz profil") {
                        guard let subjectID else { return }
                        var profile = EnvironmentProfile(name: name, subjectID: subjectID, actionIDs: store.data.actions.filter { selected.contains($0.id) }.map(\.id))
                        if let editingID { profile.id = editingID }
                        if store.change({ $0.profiles.upsert(profile) }) { name = ""; selected = []; editingID = nil }
                    }.disabled(subjectID == nil || name.isEmpty || selected.isEmpty).buttonStyle(.borderedProminent)
                    Divider()
                    ForEach(store.data.profiles.filter { $0.subjectID == subjectID }) { profile in
                        HStack {
                            Text(profile.name); Spacer()
                            Button("Edytuj") { editingID = profile.id; name = profile.name; selected = Set(profile.actionIDs) }
                            Button("Usuń", role: .destructive) {
                                store.change { data in data.profiles.removeAll { $0.id == profile.id }; for i in data.lessons.indices where data.lessons[i].profileID == profile.id { data.lessons[i].profileID = nil } }
                            }
                        }
                    }
                }
            }
            Text("Wybierz profil w edycji lekcji. Jego akcje uruchomisz przyciskiem środowiska lub razem z materiałami. Kolejność jest zgodna z listą akcji.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 720, height: 620)
    }
}
