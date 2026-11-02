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
                }
                Section("Promptbibliotek") {
                    if model.library.profiles.isEmpty {
                        Text("Inga sparade prompter än")
                            .foregroundStyle(.secondary)
                            .font(.callout)
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
                            Divider()
                            Button("Radera", role: .destructive) { model.library.delete(id: p.id) }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .toolbar {
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
            default:
                TranslationView()
            }
        }
        .sheet(isPresented: $showNewProfile) {
            GenerateProfileSheet(existingID: nil)
        }
        .onChange(of: model.library.profiles) {
            model.library.save()
        }
    }
}
