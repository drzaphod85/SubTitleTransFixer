import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showNewProfile = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                Section(L("Workspace")) {
                    Label(L("Translate"), systemImage: "captions.bubble")
                        .tag(SidebarItem.translate)
                    Label(L("Review"), systemImage: "checkmark.seal")
                        .tag(SidebarItem.review)
                }
                Section(L("Prompt library")) {
                    if model.library.profiles.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("No saved prompts yet"))
                                .foregroundStyle(.secondary)
                                .font(.callout)
                            Button(L("Import prompts…")) { model.importPanel() }
                                .buttonStyle(.link)
                            Text(L("or drop .md/.txt/.json files here"))
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
                            Button(L("Use for the current file")) { model.session.profileID = p.id }
                            Button(L("Export…")) { model.export(p.id) }
                            Divider()
                            Button(L("Delete"), role: .destructive) { model.library.delete(id: p.id) }
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
                        Label(L("Import prompts"), systemImage: "square.and.arrow.down")
                    }
                    .help(L("Import existing prompts (.md, .txt, .json) – ⇧⌘I"))
                }
                ToolbarItem {
                    Button { showNewProfile = true } label: {
                        Label(L("New prompt with Claude"), systemImage: "wand.and.stars")
                    }
                    .help(L("Let Claude create a prompt for a series or film"))
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
        .alert(L("Prompt library"), isPresented: Binding(
            get: { model.libraryMessage != nil },
            set: { if !$0 { model.libraryMessage = nil } }
        )) {
            Button(L("OK")) { model.libraryMessage = nil }
        } message: {
            Text(model.libraryMessage ?? "")
        }
        .onChange(of: model.library.profiles) {
            model.library.save()
        }
    }
}
