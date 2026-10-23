import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SpreadsheetImportView: View {
    @EnvironmentObject var store: WorkspaceStore
    @Environment(\.dismiss) var dismiss
    var subjectID: UUID
    @State var curriculumID: UUID?
    @State private var sheets: [WorkbookSheet] = []
    @State private var selected = ""
    @State private var header = 1
    @State private var titleColumn = 0
    @State private var hoursColumn = -1
    @State private var preview: [TopicImportChange] = []
    @State private var error: String?
    @State private var loading = false
    @State private var planName = "Importowany rozkład"
    @State private var proposedPlan: Curriculum?
    var sheet: WorkbookSheet? { sheets.first { $0.id == selected } }
    var columns: [String] {
        guard let rows = sheet?.rows, rows.indices.contains(header - 1) else { return [] }
        return rows[header - 1].enumerated().map { "\($0.offset + 1): \($0.element.isEmpty ? "kolumna" : $0.element)" }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Excel / CSV").font(.title2.bold())
            Text(store.data.subjectName(subjectID)).foregroundStyle(.secondary)
            HStack { Button("Wybierz .xlsx lub CSV…") { choose() }; if loading { ProgressView().controlSize(.small) }; Spacer(); Button("Anuluj") { dismiss() } }
            if !sheets.isEmpty {
                Form {
                    Picker("Arkusz", selection: $selected) { ForEach(sheets) { Text($0.name).tag($0.id) } }.onChange(of: selected) { _, _ in preview = []; header = 1; titleColumn = 0; hoursColumn = -1 }
                    Stepper("Wiersz nagłówków: \(header)", value: $header, in: 1...max(sheet?.rows.count ?? 1, 1)).onChange(of: header) { _, _ in preview = [] }
                    Picker("Kolumna z tematem", selection: $titleColumn) { ForEach(columns.indices, id: \.self) { Text(columns[$0]).tag($0) } }
                    Picker("Liczba godzin", selection: $hoursColumn) { Text("Domyślnie 1").tag(-1); ForEach(columns.indices, id: \.self) { Text(columns[$0]).tag($0) } }
                    Picker("Rozkład docelowy", selection: $curriculumID) {
                        Text("Utwórz nowy").tag(nil as UUID?)
                        ForEach(store.data.curricula.filter { $0.subjectID == subjectID }) { Text($0.name).tag(Optional($0.id)) }
                    }
                    if curriculumID == nil { TextField("Nazwa nowego rozkładu", text: $planName) }
                }.formStyle(.grouped).frame(height: 280)
                Button("Porównaj z rozkładem") { compare() }.buttonStyle(.borderedProminent)
                if let sheet {
                    Text("Podgląd danych").font(.headline)
                    ScrollView(.horizontal) { VStack(alignment: .leading) { ForEach(Array(sheet.rows.dropFirst(header).prefix(3).enumerated()), id: \.offset) { Text($0.element.joined(separator: "  |  ")).font(.caption.monospaced()) } } }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(preview) { change in Text("\(change.description) · \(change.topic.title) · \(change.topic.hours) h").font(.callout) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("Aktualizujemy tematy o tej samej nazwie w wybranym rozkładzie. Zachowujemy materiały i identyfikatory. Tematy pominięte w pliku pozostają; zmiana nazwy jest traktowana jako nowy temat.").font(.caption).foregroundStyle(.secondary)
                Button("Zastosuj \(preview.count) zmian") { apply() }.disabled(preview.isEmpty).buttonStyle(.borderedProminent)
            }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            Spacer(minLength: 0)
        }.padding(24).frame(width: 820, height: 780)
            .onChange(of: titleColumn) { _, _ in preview = [] }.onChange(of: hoursColumn) { _, _ in preview = [] }
            .onChange(of: curriculumID) { _, _ in preview = [] }.onChange(of: planName) { _, _ in preview = [] }
    }
    private func choose() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.spreadsheet, .commaSeparatedText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loading = true; error = nil; preview = []
        Task {
            defer { loading = false }
            do { sheets = try await Task.detached { try SpreadsheetReader.read(url) }.value; selected = sheets.first?.id ?? "" }
            catch { self.error = error.localizedDescription }
        }
    }
    private func compare() {
        do {
            guard let sheet, let subject = store.data.subjects.first(where: { $0.id == subjectID }), !planName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let plan = store.data.curricula.first { $0.id == curriculumID } ?? Curriculum(subjectID: subjectID, name: planName)
            proposedPlan = plan
            preview = try TopicImport.changes(rows: sheet.rows, header: header - 1, titleColumn: titleColumn, hoursColumn: hoursColumn < 0 ? nil : hoursColumn, subject: subject, curriculum: plan, existing: store.data.topics)
            error = preview.isEmpty ? "Brak zmian do zastosowania." : nil
        } catch { self.error = error.localizedDescription; preview = [] }
    }
    private func apply() {
        guard let plan = proposedPlan else { return }
        if store.change({ data in data.curricula.upsert(plan); for change in preview { data.topics.upsert(change.topic) } }) { dismiss() }
    }
}
