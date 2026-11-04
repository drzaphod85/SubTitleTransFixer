import SwiftUI

/// Import existing prompts (.md/.txt/.json) into the prompt library.
struct ImportPromptsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.on.square.fill")
                    .font(.largeTitle).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Import prompts")).font(.headline)
                    Text(L("Check the title – it is used to find the prompt automatically when a subtitle file for the series or film is opened."))
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !model.importErrors.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.importErrors, id: \.self) { e in
                        Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
                .font(.callout)
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach($model.importCandidates) { $c in
                        ImportRow(candidate: $c)
                            .disabled(isWorking)
                    }
                }
            }
            .frame(minHeight: 260)

            HStack {
                Button(L("Add more files…")) { model.importPanel(append: true) }
                    .disabled(isWorking)
                Spacer()
                if isWorking { ProgressView().controlSize(.small) }
                Button(L("Cancel")) {
                    model.importCandidates = []
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isWorking)
                Button(L("Import {0}", pendingCount)) { Task { await runImport() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking || pendingCount == 0)
            }
        }
        .padding(24)
        .frame(width: 720, height: 560)
    }

    private var pendingCount: Int {
        model.importCandidates.filter { $0.status != .done }.count
    }

    private func runImport() async {
        isWorking = true
        defer { isWorking = false }
        var lastID: UUID?
        for i in model.importCandidates.indices where model.importCandidates[i].status != .done {
            model.importCandidates[i].status = .working
            do {
                lastID = try await importOne(model.importCandidates[i])
                model.importCandidates[i].status = .done
            } catch {
                model.importCandidates[i].status = .failed(error.localizedDescription)
            }
        }
        // Close if everything went well, otherwise the errors stay visible.
        if model.importCandidates.allSatisfy({ $0.status == .done }) {
            if let lastID { model.selection = .profile(lastID) }
            model.importCandidates = []
            dismiss()
        }
    }

    private func importOne(_ c: ImportCandidate) async throws -> UUID {
        let library = model.library
        let title = c.title.trimmingCharacters(in: .whitespaces)
        let target = library.profile(id: c.targetID)

        switch c.source {
        case .profile(var p):
            p.title = title.isEmpty ? p.title : title
            p.kind = c.kind
            p.targetLanguage = c.targetLanguage
            if let target {
                p.id = target.id
                p.createdAt = target.createdAt
                p.translatedEpisodes = Array(Set(target.translatedEpisodes + p.translatedEpisodes)).sorted()
            } else if library.profile(id: p.id) != nil {
                p.id = UUID() // clashes with another prompt – import as new
            }
            library.upsert(p)
            return p.id

        case .text(let text):
            if c.structureWithClaude {
                let client = try model.settings.makeClient()
                var p = try await ProfileGenerator.structure(text: text, title: title, kind: c.kind,
                                                             target: Language.find(c.targetLanguage) ?? .swedish,
                                                             into: target, client: client)
                if let target { p.id = target.id }
                library.upsert(p)
                return p.id
            }
            var p = target ?? SeriesProfile(title: title, kind: c.kind)
            if target == nil { p.title = title }
            p.kind = c.kind
            p.targetLanguage = c.targetLanguage
            p.styleGuide = text
            library.upsert(p)
            return p.id
        }
    }
}

private struct ImportRow: View {
    @Environment(AppModel.self) private var model
    @Binding var candidate: ImportCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: candidate.isText ? "doc.plaintext" : "curlybraces")
                    .foregroundStyle(.secondary)
                Text(candidate.fileName).font(.callout.monospaced()).foregroundStyle(.secondary)
                Spacer()
                statusView
            }
            HStack {
                TextField(L("Title"), text: $candidate.title)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $candidate.kind) {
                    ForEach(MediaKind.allCases) { k in Text(k.label).tag(k) }
                }
                .labelsHidden()
                .frame(width: 120)
                Picker(L("To"), selection: $candidate.targetLanguage) {
                    ForEach(Language.all) { lang in Text(lang.displayName).tag(lang.code) }
                }
                .frame(width: 170)
                .help(L("The language the prompt is for translating into"))
            }
            HStack {
                Picker(L("Save as"), selection: $candidate.targetID) {
                    Text(L("New prompt")).tag(UUID?.none)
                    Divider()
                    ForEach(model.library.sorted) { p in
                        Text(L("Replace/update “{0}”", p.title)).tag(Optional(p.id))
                    }
                }
                .frame(maxWidth: 380)
                if candidate.isText {
                    Toggle(L("Let Claude split it into style guide, characters and glossary"), isOn: $candidate.structureWithClaude)
                        .toggleStyle(.checkbox)
                        .disabled(!model.settings.hasAPIKey)
                }
            }
            .font(.callout)
            Text(candidate.preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var statusView: some View {
        switch candidate.status {
        case .pending:
            EmptyView()
        case .working:
            ProgressView().controlSize(.small)
        case .done:
            Label(L("Imported"), systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.caption).lineLimit(2)
        }
    }
}
