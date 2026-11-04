import SwiftUI

/// Edit a saved prompt (work profile).
struct ProfileEditorView: View {
    @Environment(AppModel.self) private var model
    let profileID: UUID

    @State private var showImprove = false
    @State private var showPreview = false
    @State private var confirmDelete = false

    var body: some View {
        @Bindable var library = model.library
        if let i = library.index(of: profileID) {
            let p = $library.profiles[i]
            Form {
                Section {
                    TextField(L("Title"), text: p.title)
                    TextField(L("Aliases (comma separated)"), text: Binding(
                        get: { p.wrappedValue.aliases.joined(separator: ", ") },
                        set: { p.wrappedValue.aliases = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                    ))
                    .help(L("Other names the files may have, so that the prompt is found automatically"))
                    Picker(L("Type"), selection: p.kind) {
                        ForEach(MediaKind.allCases) { k in Text(k.label).tag(k) }
                    }
                    Picker(L("Translates into"), selection: p.targetLanguage) {
                        ForEach(Language.all) { lang in Text(lang.menuName).tag(lang.code) }
                    }
                    .help(L("The prompt is only found automatically when you translate into this language"))
                    TextField(L("Year"), text: p.year)
                } header: {
                    Text(L("Work"))
                }

                Section(L("About the work")) {
                    TextEditor(text: p.synopsis)
                        .frame(minHeight: 60)
                        .font(.body)
                }

                Section {
                    TextEditor(text: p.styleGuide)
                        .frame(minHeight: 160)
                        .font(.body)
                } header: {
                    Text(L("Style guide for the work"))
                } footer: {
                    Text(L("Added on top of the base style from Settings and takes precedence where they conflict."))
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(p.characters) { $c in
                        HStack(alignment: .top) {
                            TextField(L("Name"), text: $c.name).frame(width: 150)
                            TextField(L("Description"), text: $c.description, axis: .vertical)
                            TextField(L("Speaks / is addressed"), text: $c.speech, axis: .vertical).frame(width: 200)
                            Button(role: .destructive) {
                                p.wrappedValue.characters.removeAll { $0.id == c.id }
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                    Button(L("Add character")) {
                        p.wrappedValue.characters.append(CharacterNote(name: "", description: ""))
                    }
                } header: {
                    Text(L("Characters ({0})", p.wrappedValue.characters.count))
                }

                Section {
                    ForEach(p.glossary) { $g in
                        HStack(alignment: .top) {
                            TextField(L("Original"), text: $g.source).frame(width: 170)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            TextField(L("Translation"), text: $g.target).frame(width: 170)
                            TextField(L("Note"), text: $g.note, axis: .vertical)
                            Button(role: .destructive) {
                                p.wrappedValue.glossary.removeAll { $0.id == g.id }
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                    Button(L("Add term")) {
                        p.wrappedValue.glossary.append(GlossaryEntry(source: "", target: ""))
                    }
                } header: {
                    Text(L("Glossary ({0})", p.wrappedValue.glossary.count))
                }

                Section {
                    ForEach(Array(p.wrappedValue.notes.enumerated()), id: \.offset) { idx, _ in
                        HStack(alignment: .top) {
                            TextField(L("Note"), text: Binding(
                                get: { idx < p.wrappedValue.notes.count ? p.wrappedValue.notes[idx] : "" },
                                set: { if idx < p.wrappedValue.notes.count { p.wrappedValue.notes[idx] = $0 } }
                            ), axis: .vertical)
                            Button(role: .destructive) {
                                if idx < p.wrappedValue.notes.count { p.wrappedValue.notes.remove(at: idx) }
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                    Button(L("Add note")) { p.wrappedValue.notes.append("") }
                } header: {
                    Text(L("Notes and saved decisions"))
                }

                if !p.wrappedValue.translatedEpisodes.isEmpty {
                    Section(L("Translated episodes")) {
                        Text(p.wrappedValue.translatedEpisodes.joined(separator: ", "))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Section {
                    DisclosureGroup(L("Preview the whole prompt"), isExpanded: $showPreview) {
                        Text(PromptBuilder.systemPrompt(profile: p.wrappedValue, clarifications: [], settings: model.settings,
                                                        source: model.session.sourceLanguage,
                                                        target: Language.find(p.wrappedValue.targetLanguage) ?? .swedish))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(p.wrappedValue.title)
            .navigationSubtitle(p.wrappedValue.subtitle)
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        model.session.profileID = profileID
                        model.session.profileAutoMatched = false
                        model.selection = .translate
                    } label: { Label(L("Use for the current file"), systemImage: "checkmark.circle") }
                    Button { showImprove = true } label: { Label(L("Improve with Claude"), systemImage: "wand.and.stars") }
                    Button { model.export(profileID) } label: { Label(L("Export"), systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label(L("Delete"), systemImage: "trash") }
                }
            }
            .sheet(isPresented: $showImprove) {
                GenerateProfileSheet(existingID: profileID)
            }
            .confirmationDialog(L("Delete the prompt for “{0}”?", p.wrappedValue.title), isPresented: $confirmDelete) {
                Button(L("Delete"), role: .destructive) {
                    model.selection = .translate
                    if model.session.profileID == profileID { model.session.profileID = nil }
                    model.library.delete(id: profileID)
                }
            }
        } else {
            ContentUnavailableView(L("The prompt no longer exists"), systemImage: "questionmark.folder")
        }
    }
}

/// Let Claude create a new prompt – or improve an existing one.
struct GenerateProfileSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let existingID: UUID?
    var prefillTitle: String? = nil
    /// Prompt for the same work but another target language – Claude uses it as a basis.
    var reference: SeriesProfile? = nil
    var onCreated: ((UUID) -> Void)? = nil

    @State private var title = ""
    @State private var kind: MediaKind = .series
    @State private var year = ""
    @State private var sourceCode = "en"
    @State private var targetCode = "sv"
    @State private var extraInfo = ""
    @State private var includeSample = true
    @State private var webSearch = true
    @State private var isWorking = false
    @State private var error: String?

    private var existing: SeriesProfile? { model.library.profile(id: existingID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars").font(.largeTitle).foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(existing == nil ? L("Create a prompt with Claude") : L("Improve the prompt with Claude"))
                        .font(.headline)
                    Text(L("Claude writes a work-specific style guide, character list and glossary that are saved and used automatically the next time the series or film comes up."))
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Form {
                TextField(L("Title"), text: $title, prompt: Text(L("e.g. All Creatures Great and Small")))
                    .disabled(existing != nil)
                Picker(L("Type"), selection: $kind) {
                    ForEach(MediaKind.allCases) { k in Text(k.label).tag(k) }
                }
                .disabled(existing != nil)
                TextField(L("Year (optional)"), text: $year, prompt: Text(L("e.g. 2020")))
                Picker(L("Language of the subtitles"), selection: $sourceCode) {
                    ForEach(Language.all) { lang in Text(lang.menuName).tag(lang.code) }
                }
                Picker(L("Translate into"), selection: $targetCode) {
                    ForEach(Language.all) { lang in Text(lang.menuName).tag(lang.code) }
                }
                .disabled(existing != nil)
                if let reference {
                    Label(L("Uses the prompt for “{0}” ({1}) as a basis", reference.title, Language.find(reference.targetLanguage)?.displayName ?? reference.targetLanguage),
                          systemImage: "doc.on.doc")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading) {
                    Text(L("Your own wishes or information (optional)"))
                    TextEditor(text: $extraInfo)
                        .frame(height: 80)
                        .font(.body)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                }
                Toggle(L("Use lines from the loaded file as material"), isOn: $includeSample)
                    .disabled(!model.session.hasFile)
                Toggle(L("Let Claude search the web (cast, setting, established names)"), isOn: $webSearch)
                    .disabled(!AnthropicClient.supportsWebSearch(model.settings.model))
            }
            .formStyle(.grouped)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                if isWorking {
                    ProgressView().controlSize(.small)
                    Text(L("Claude is working … this may take a minute.")).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(existing == nil ? L("Create") : L("Improve")) { Task { await generate() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking || title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 620)
        .onAppear {
            sourceCode = model.session.sourceLanguage.code
            targetCode = model.session.targetLanguage.code
            if let existing {
                title = existing.title
                kind = existing.kind
                year = existing.year
                targetCode = existing.targetLanguage
            } else if let prefillTitle {
                title = prefillTitle
                if let reference { kind = reference.kind; year = reference.year }
            }
            includeSample = model.session.hasFile
            webSearch = model.settings.webSearchForProfiles
        }
    }

    private func generate() async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            let client = try model.settings.makeClient()
            let request = ProfileGenerator.Request(
                title: title.trimmingCharacters(in: .whitespaces),
                kind: kind,
                year: year.trimmingCharacters(in: .whitespaces),
                extraInfo: extraInfo,
                sampleLines: includeSample ? model.session.sampleLines() : [],
                webSearch: webSearch,
                existing: existing,
                source: Language.find(sourceCode) ?? .english,
                target: Language.find(targetCode) ?? .swedish,
                reference: existing == nil ? reference : nil
            )
            let profile = try await ProfileGenerator.generate(request, client: client)
            model.library.upsert(profile)
            onCreated?(profile.id)
            if existing == nil, onCreated == nil { model.selection = .profile(profile.id) }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
