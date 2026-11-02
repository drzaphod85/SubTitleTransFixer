import SwiftUI

/// Redigera en sparad prompt (verksprofil).
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
                    TextField("Titel", text: p.title)
                    TextField("Alias (kommaseparerade)", text: Binding(
                        get: { p.wrappedValue.aliases.joined(separator: ", ") },
                        set: { p.wrappedValue.aliases = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                    ))
                    .help("Andra namn som filerna kan ha, så att prompten hittas automatiskt")
                    Picker("Typ", selection: p.kind) {
                        ForEach(MediaKind.allCases) { k in Text(k.label).tag(k) }
                    }
                    TextField("År", text: p.year)
                } header: {
                    Text("Verk")
                }

                Section("Om verket") {
                    TextEditor(text: p.synopsis)
                        .frame(minHeight: 60)
                        .font(.body)
                }

                Section {
                    TextEditor(text: p.styleGuide)
                        .frame(minHeight: 160)
                        .font(.body)
                } header: {
                    Text("Stilguide för verket")
                } footer: {
                    Text("Läggs ovanpå grundstilen från Inställningar och går före den vid konflikt.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(p.characters) { $c in
                        HStack(alignment: .top) {
                            TextField("Namn", text: $c.name).frame(width: 150)
                            TextField("Beskrivning", text: $c.description, axis: .vertical)
                            TextField("Talar / tilltalas", text: $c.speech, axis: .vertical).frame(width: 200)
                            Button(role: .destructive) {
                                p.wrappedValue.characters.removeAll { $0.id == c.id }
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                    Button("Lägg till karaktär") {
                        p.wrappedValue.characters.append(CharacterNote(name: "", description: ""))
                    }
                } header: {
                    Text("Karaktärer (\(p.wrappedValue.characters.count))")
                }

                Section {
                    ForEach(p.glossary) { $g in
                        HStack(alignment: .top) {
                            TextField("Engelska", text: $g.source).frame(width: 170)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            TextField("Svenska", text: $g.target).frame(width: 170)
                            TextField("Anteckning", text: $g.note, axis: .vertical)
                            Button(role: .destructive) {
                                p.wrappedValue.glossary.removeAll { $0.id == g.id }
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                    Button("Lägg till term") {
                        p.wrappedValue.glossary.append(GlossaryEntry(source: "", target: ""))
                    }
                } header: {
                    Text("Ordlista (\(p.wrappedValue.glossary.count))")
                }

                Section {
                    ForEach(Array(p.wrappedValue.notes.enumerated()), id: \.offset) { idx, _ in
                        HStack(alignment: .top) {
                            TextField("Anteckning", text: Binding(
                                get: { idx < p.wrappedValue.notes.count ? p.wrappedValue.notes[idx] : "" },
                                set: { if idx < p.wrappedValue.notes.count { p.wrappedValue.notes[idx] = $0 } }
                            ), axis: .vertical)
                            Button(role: .destructive) {
                                if idx < p.wrappedValue.notes.count { p.wrappedValue.notes.remove(at: idx) }
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                    Button("Lägg till anteckning") { p.wrappedValue.notes.append("") }
                } header: {
                    Text("Anteckningar och sparade beslut")
                }

                if !p.wrappedValue.translatedEpisodes.isEmpty {
                    Section("Översatta avsnitt") {
                        Text(p.wrappedValue.translatedEpisodes.joined(separator: ", "))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Section {
                    DisclosureGroup("Förhandsvisa hela prompten", isExpanded: $showPreview) {
                        Text(PromptBuilder.systemPrompt(profile: p.wrappedValue, clarifications: [], settings: model.settings))
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
                    } label: { Label("Använd för aktuell fil", systemImage: "checkmark.circle") }
                    Button { showImprove = true } label: { Label("Förbättra med Claude", systemImage: "wand.and.stars") }
                    Button { model.export(profileID) } label: { Label("Exportera", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Radera", systemImage: "trash") }
                }
            }
            .sheet(isPresented: $showImprove) {
                GenerateProfileSheet(existingID: profileID)
            }
            .confirmationDialog("Radera prompten för ”\(p.wrappedValue.title)”?", isPresented: $confirmDelete) {
                Button("Radera", role: .destructive) {
                    model.selection = .translate
                    if model.session.profileID == profileID { model.session.profileID = nil }
                    model.library.delete(id: profileID)
                }
            }
        } else {
            ContentUnavailableView("Prompten finns inte längre", systemImage: "questionmark.folder")
        }
    }
}

/// Låt Claude skapa en ny prompt – eller förbättra en befintlig.
struct GenerateProfileSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let existingID: UUID?
    var prefillTitle: String? = nil
    var onCreated: ((UUID) -> Void)? = nil

    @State private var title = ""
    @State private var kind: MediaKind = .series
    @State private var year = ""
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
                    Text(existing == nil ? "Skapa prompt med Claude" : "Förbättra prompten med Claude")
                        .font(.headline)
                    Text("Claude skriver en verksspecifik stilguide, karaktärslista och ordlista som sparas och används automatiskt nästa gång serien eller filmen dyker upp.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Form {
                TextField("Titel", text: $title, prompt: Text("t.ex. All Creatures Great and Small"))
                    .disabled(existing != nil)
                Picker("Typ", selection: $kind) {
                    ForEach(MediaKind.allCases) { k in Text(k.label).tag(k) }
                }
                .disabled(existing != nil)
                TextField("År (valfritt)", text: $year, prompt: Text("t.ex. 2020"))
                VStack(alignment: .leading) {
                    Text("Egna önskemål eller information (valfritt)")
                    TextEditor(text: $extraInfo)
                        .frame(height: 80)
                        .font(.body)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                }
                Toggle("Använd repliker ur den inlästa filen som underlag", isOn: $includeSample)
                    .disabled(!model.session.hasFile)
                Toggle("Låt Claude söka på webben (rollista, miljö, svenska namn)", isOn: $webSearch)
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
                    Text("Claude arbetar … det kan ta en minut.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Avbryt") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(existing == nil ? "Skapa" : "Förbättra") { Task { await generate() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking || title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 620)
        .onAppear {
            if let existing {
                title = existing.title
                kind = existing.kind
                year = existing.year
            } else if let prefillTitle {
                title = prefillTitle
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
                existing: existing
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
