import AppKit
import SwiftUI

@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    let library: PromptLibrary
    let session: TranslationSession
    var selection: SidebarItem? = .translate

    init() {
        let settings = AppSettings()
        let library = PromptLibrary()
        self.settings = settings
        self.library = library
        self.session = TranslationSession(library: library, settings: settings)
    }

    // MARK: Import/export av prompter

    var importCandidates: [ImportCandidate] = []
    var importErrors: [String] = []
    var showImport = false
    var libraryMessage: String?

    func importPanel(append: Bool = false) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = PromptImporter.allowedTypes
        panel.allowsMultipleSelection = true
        panel.message = "Välj prompter att importera (.md, .txt eller .json från Undertextaren)"
        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls, append: append)
    }

    func importFiles(_ urls: [URL], append: Bool = false) {
        let result = PromptImporter.candidates(from: urls, library: library)
        if append {
            importCandidates += result.items
            importErrors += result.errors
        } else {
            importCandidates = result.items
            importErrors = result.errors
        }
        if !importCandidates.isEmpty || !importErrors.isEmpty { showImport = true }
    }

    func exportAll() {
        libraryMessage = PromptImporter.exportPanel(library.sorted, suggestedName: "Undertextaren-prompter.json")
    }

    func export(_ id: UUID) {
        guard let p = library.profile(id: id) else { return }
        libraryMessage = PromptImporter.exportPanel([p], suggestedName: "\(p.title).json")
    }
}

enum SidebarItem: Hashable {
    case translate
    case profile(UUID)
}

@main
struct UndertextarenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Undertextaren") {
            ContentView()
                .environment(model)
                .frame(minWidth: 1050, minHeight: 650)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Öppna undertext…") { model.session.openPanel() }
                    .keyboardShortcut("o")
                Button("Spara svensk undertext…") { model.session.savePanel() }
                    .keyboardShortcut("s")
                    .disabled(!model.session.hasFile)
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Importera prompter…") { model.importPanel() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Exportera alla prompter…") { model.exportAll() }
                    .disabled(model.library.profiles.isEmpty)
            }
            CommandMenu("Översättning") {
                Button(model.session.isRunning ? "Stoppa" : "Starta översättning") {
                    model.session.isRunning ? model.session.stop() : model.session.start()
                }
                .keyboardShortcut("r")
                .disabled(!model.session.hasFile)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// Gör att appen beter sig som en vanlig app även när den startas med `swift run`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
