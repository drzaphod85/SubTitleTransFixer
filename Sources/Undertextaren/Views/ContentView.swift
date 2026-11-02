import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showNewProfile = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                Section("Arbete") {
                    Label("Översätt", systemImage: "captions.bubble")
                        .tag(SidebarItem.translate)
                    Label("Granska", systemImage: "checkmark.seal")
                        .tag(SidebarItem.review)
                }
                Section("Promptbibliotek") {
                    if model.library.profiles.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Inga sparade prompter än")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                            Button("Importera prompter…") { model.importPanel() }
                                .buttonStyle(.link)
                            Text("eller släpp .md/.txt/.json-filer här")
                                .foregroundStyle(.tertiary)
                                .font(.caption)
                        }
                    }
                    ForEach(model.library.sorted) { p in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(p.title, systemImage: p.kind.symbol)
                            Text(p.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 26)
                        }
                        .tag(SidebarItem.profile(p.id))
                        .contextMenu {
                            Button("Använd för aktuell fil") { model.session.profileID = p.id }
                            Button("Exportera…") { model.export(p.id) }
                            Divider()
                            Button("Radera", role: .destructive) { model.library.delete(id: p.id) }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .dropDestination(for: URL.self) { urls, _ in
                let prompts = urls.filter { ["md", "markdown", "txt", "json"].contains($0.pathExtension.lowercased()) }
                guard !prompts.isEmpty else { return false }
                model.importFiles(prompts)
                return true
            }
            .toolbar {
                ToolbarItem {
                    Button { model.importPanel() } label: {
                        Label("Importera prompter", systemImage: "square.and.arrow.down")
                    }
                    .help("Importera befintliga prompter (.md, .txt, .json) – ⇧⌘I")
                }
                ToolbarItem {
                    Button { showNewProfile = true } label: {
                        Label("Ny prompt med Claude", systemImage: "wand.and.stars")
                    }
                    .help("Låt Claude skapa en prompt för en serie eller film")
                }
            }
        } detail: {
            switch model.selection {
            case .profile(let id) where model.library.profile(id: id) != nil:
                ProfileEditorView(profileID: id)
                    .id(id)
            case .review:
                ReviewView()
            default:
                TranslationView()
            }
        }
        .sheet(isPresented: $showNewProfile) {
            GenerateProfileSheet(existingID: nil)
        }
        .sheet(isPresented: $model.showImport) {
            ImportPromptsSheet()
        }
        .alert("Promptbiblioteket", isPresented: Binding(
            get: { model.libraryMessage != nil },
            set: { if !$0 { model.libraryMessage = nil } }
        )) {
            Button("OK") { model.libraryMessage = nil }
        } message: {
            Text(model.libraryMessage ?? "")
        }
        .onChange(of: model.library.profiles) {
            model.library.save()
        }
    }
}
