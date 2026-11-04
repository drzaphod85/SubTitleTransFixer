import AppKit
import SwiftUI

@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    let library: PromptLibrary
    let session: TranslationSession
    let review: ReviewSession
    var selection: SidebarItem? = .translate

    init() {
        // Bring over settings and prompts from the old "Undertextaren" app first.
        LegacyMigration.run()
        let settings = AppSettings()
        let library = PromptLibrary()
        self.settings = settings
        self.library = library
        self.session = TranslationSession(library: library, settings: settings)
        self.review = ReviewSession(settings: settings, library: library)
    }

    // MARK: Import/export of prompts

    var importCandidates: [ImportCandidate] = []
    var importErrors: [String] = []
    var showImport = false
    var libraryMessage: String?

    func importPanel(append: Bool = false) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = PromptImporter.allowedTypes
        panel.allowsMultipleSelection = true
        panel.message = L("Choose prompts to import (.md, .txt or .json exported from the app)")
        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls, append: append)
    }

    func importFiles(_ urls: [URL], append: Bool = false) {
        let result = PromptImporter.candidates(from: urls, library: library, defaultTarget: settings.targetLanguage)
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
        libraryMessage = PromptImporter.exportPanel(library.sorted, suggestedName: "SubTitle TransFixer prompts.json")
    }

    func export(_ id: UUID) {
        guard let p = library.profile(id: id) else { return }
        libraryMessage = PromptImporter.exportPanel([p], suggestedName: "\(p.title).json")
    }
}

enum SidebarItem: Hashable {
    case translate
    case review
    case profile(UUID)
}

@main
struct SubTitleTransFixerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup(AppInfo.name) {
            ContentView()
                .environment(model)
                .frame(minWidth: 1050, minHeight: 650)
                .onAppear { appDelegate.model = model }
                // Rebuild the views when the UI language changes.
                .id(model.settings.appLanguage)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L("Open Subtitles…")) { model.session.openPanel() }
                    .keyboardShortcut("o")
                // ⌘S saves what is being worked on: the reviewed file or the translation.
                Button(model.selection == .review ? L("Save") : L("Save Translation…")) {
                    if model.selection == .review { model.review.save() } else { model.session.savePanel() }
                }
                .keyboardShortcut("s")
                .disabled(model.selection == .review ? !model.review.hasFile : !model.session.hasFile)
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button(L("Import Prompts…")) { model.importPanel() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button(L("Export All Prompts…")) { model.exportAll() }
                    .disabled(model.library.profiles.isEmpty)
            }
            CommandMenu(L("Review")) {
                Button(L("Review Subtitle File…")) {
                    model.selection = .review
                    model.review.openPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .option])
                Button(L("Review Current Translation")) {
                    model.review.load(translation: model.session)
                    model.selection = .review
                }
                .disabled(model.session.translatedCount == 0)
                Button(model.review.isReviewing ? L("Stop Language Review") : L("Review Language with Claude")) {
                    model.review.isReviewing ? model.review.stop() : model.review.startClaudeReview()
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(!model.review.hasFile)
            }
            CommandMenu(L("Translation")) {
                Button(model.session.isRunning ? L("Stop") : L("Start Translation")) {
                    model.session.isRunning ? model.session.stop() : model.session.start()
                }
                .keyboardShortcut("r")
                .disabled(!model.session.hasFile)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .id(model.settings.appLanguage)
        }
    }
}

/// Makes the app behave like a normal app even when started with `swift run`,
/// and asks about unsaved review changes before quitting.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let review = model?.review else { return .terminateNow }
        return review.confirmDiscardChanges() ? .terminateNow : .terminateCancel
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
