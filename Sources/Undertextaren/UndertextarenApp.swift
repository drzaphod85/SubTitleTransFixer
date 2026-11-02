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
