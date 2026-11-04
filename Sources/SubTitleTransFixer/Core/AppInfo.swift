import Foundation

/// Names and identifiers used across the app.
enum AppInfo {
    static let name = "SubTitle TransFixer"
    static let bundleIdentifier = "se.subtitletransfixer.app"
    /// Folder in ~/Library/Application Support.
    static let supportFolderName = "SubTitle TransFixer"
    /// Service name of the API key item in the keychain.
    static let keychainService = "SubTitle TransFixer"

    /// The app was previously called "Undertextaren".
    enum Legacy {
        static let supportFolderName = "Undertextaren"
        static let keychainService = "Undertextaren"
        /// Preference domains: the old .app bundle and `swift run`.
        static let defaultsDomains = ["se.undertextaren.app", "Undertextaren"]
    }
}

/// One-time migration of settings and prompts from "Undertextaren".
/// Copies (never moves) so that the old app keeps working.
enum LegacyMigration {
    private static let doneKey = "migratedFromUndertextaren"

    /// Settings that are copied from the old preference domain.
    private static let settingKeys = [
        "model", "effort", "batchSize", "contextSize", "maxCPS", "maxLineLength",
        "questionMode", "useFallbacks", "webSearchForProfiles", "suggestProfileUpdates",
        "baseStyle", "sourceLanguage", "targetLanguage",
    ]

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        migrateDefaults(defaults)
        migratePromptLibrary()
        defaults.set(true, forKey: doneKey)
    }

    private static func migrateDefaults(_ defaults: UserDefaults) {
        for domain in AppInfo.Legacy.defaultsDomains {
            guard let old = defaults.persistentDomain(forName: domain) else { continue }
            for key in settingKeys where defaults.object(forKey: key) == nil {
                if let value = old[key] { defaults.set(value, forKey: key) }
            }
        }
    }

    private static func migratePromptLibrary() {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let oldFile = base.appendingPathComponent(AppInfo.Legacy.supportFolderName).appendingPathComponent("profiles.json")
        let newDir = base.appendingPathComponent(AppInfo.supportFolderName, isDirectory: true)
        let newFile = newDir.appendingPathComponent("profiles.json")
        guard fm.fileExists(atPath: oldFile.path), !fm.fileExists(atPath: newFile.path) else { return }
        try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)
        try? fm.copyItem(at: oldFile, to: newFile)
    }
}
