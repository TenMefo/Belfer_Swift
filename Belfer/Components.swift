import SwiftUI

extension View {
    func panel() -> some View {
        self.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.05)))
    }
}
struct PageHeading: View {
    var eyebrow: String
    var title: String
    var subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow.uppercased()).font(.caption.weight(.bold)).tracking(2).foregroundStyle(.indigo)
            Text(title).font(.system(size: 32, weight: .bold, design: .rounded))
            Text(subtitle).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct EmptyPanel: View {
    var title: String
    var message: String
    var symbol = "tray"
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 36)).foregroundStyle(.indigo.opacity(0.6))
            Text(title).font(.title3.bold())
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 480)
        }.frame(maxWidth: .infinity).padding(40).panel()
    }
}
struct StatusPill: View {
    var status: LessonStatus
    var color: Color {
        switch status { case .planned: return .orange; case .ready: return .indigo; case .completed: return .green; case .cancelled: return .secondary }
    }
    var body: some View {
        Text(status.rawValue).font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(color).background(color.opacity(0.1), in: Capsule())
    }
}
struct MultilineField: View {
    var title: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.subheadline.weight(.semibold))
            TextEditor(text: $text).font(.body).frame(minHeight: 90).padding(6)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
struct EditorActions: View {
    var valid = true
    var save: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        HStack {
            Button("Anuluj") { dismiss() }.keyboardShortcut(.cancelAction)
            Spacer()
            Button("Zapisz", action: save).buttonStyle(.borderedProminent).disabled(!valid).keyboardShortcut(.defaultAction)
        }.padding()
    }
}
