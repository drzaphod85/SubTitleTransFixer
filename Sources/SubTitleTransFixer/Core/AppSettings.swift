import CryptoKit
import Foundation
import Observation
import Security

enum QuestionMode: String, CaseIterable, Identifiable {
    case pause    // pause and ask right away
    case collect  // collect questions in the side panel, keep translating
    case off      // never ask
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pause: return L("Pause and ask right away")
        case .collect: return L("Collect questions, keep translating")
        case .off: return L("Never ask")
        }
    }
}

@Observable
final class AppSettings {
    @ObservationIgnored private let defaults = UserDefaults.standard

    /// "system" or a UI language code ("en", "sv", "nb", "da", "fi", "is").
    var appLanguage: String {
        didSet {
            defaults.set(appLanguage, forKey: "appLanguage")
            L10n.apply(appLanguage)
        }
    }
    var model: String { didSet { defaults.set(model, forKey: "model") } }
    /// "auto" or a language code (ISO 639-1)
    var sourceLanguage: String { didSet { defaults.set(sourceLanguage, forKey: "sourceLanguage") } }
    var targetLanguage: String { didSet { defaults.set(targetLanguage, forKey: "targetLanguage") } }
    var effort: String { didSet { defaults.set(effort, forKey: "effort") } }
    var batchSize: Int { didSet { defaults.set(batchSize, forKey: "batchSize") } }
    var contextSize: Int { didSet { defaults.set(contextSize, forKey: "contextSize") } }
    var maxCPS: Double { didSet { defaults.set(maxCPS, forKey: "maxCPS") } }
    var maxLineLength: Int { didSet { defaults.set(maxLineLength, forKey: "maxLineLength") } }
    var questionMode: QuestionMode { didSet { defaults.set(questionMode.rawValue, forKey: "questionMode") } }
    var useFallbacks: Bool { didSet { defaults.set(useFallbacks, forKey: "useFallbacks") } }
    var webSearchForProfiles: Bool { didSet { defaults.set(webSearchForProfiles, forKey: "webSearchForProfiles") } }
    var suggestProfileUpdates: Bool { didSet { defaults.set(suggestProfileUpdates, forKey: "suggestProfileUpdates") } }
    /// The base style (corresponds to DEFAULT_STYLE / STYLE_FILE in the original script).
    var baseStyle: String { didSet { defaults.set(baseStyle, forKey: "baseStyle") } }

    var apiKey: String {
        didSet {
            let status = Keychain.save(apiKey)
            keychainProblem = status == errSecSuccess ? nil : Keychain.accessHelp(status)
        }
    }
    /// Set when the key could not be read from or saved to the keychain.
    var keychainProblem: String?
    /// Where the key came from at launch.
    var apiKeySource: KeySource = .unset

    enum KeySource {
        case unset, keychain, environment
        var label: String {
            switch self {
            case .unset: return ""
            case .keychain: return L("the keychain")
            case .environment: return L("the ANTHROPIC_API_KEY environment variable")
            }
        }
    }

    struct Choice: Identifiable, Hashable {
        let id: String
        /// English label; shown through `L()`.
        let key: String
        var label: String { L(key) }
    }

    static let modelChoices: [Choice] = [
        Choice(id: "claude-opus-5-5", key: "Claude Opus 5.5 – best quality"),
        Choice(id: "claude-sonnet-5-5", key: "Claude Sonnet 5.5 – fast and cheaper"),
        Choice(id: "claude-haiku-5-5", key: "Claude Haiku 5.5 – cheapest"),
        Choice(id: "claude-fable-5-1", key: "Claude Fable 5.1 – most capable, most expensive"),
    ]
    static let effortChoices: [Choice] = [
        Choice(id: "", key: "Model default"),
        Choice(id: "low", key: "Low"),
        Choice(id: "medium", key: "Medium"),
        Choice(id: "high", key: "High"),
        Choice(id: "xhigh", key: "Very high"),
    ]

    /// SHA-256 of the default base styles of earlier versions (written in Swedish).
    /// A stored base style that matches one of them was never edited by the
    /// user and is replaced with the current default.
    private static let previousDefaultStyleHashes: Set<String> = [
        "28d176860b1c16f28bdcc21c5852423aae6b4d7d4e94a6e0fd905a93af7b3cd3", // 1.0 (Swedish only)
        "547c3d49bc0a1257acee439c0e9a8ba7593d3717938bebe5ce85673aced4e509", // 1.1 (language neutral, Swedish)
    ]

    init() {
        let language = defaults.string(forKey: "appLanguage") ?? AppLanguage.system.rawValue
        appLanguage = language
        L10n.apply(language)
        model = defaults.string(forKey: "model") ?? "claude-opus-5-5"
        sourceLanguage = defaults.string(forKey: "sourceLanguage") ?? Language.auto
        targetLanguage = defaults.string(forKey: "targetLanguage") ?? "sv"
        effort = defaults.string(forKey: "effort") ?? "medium"
        batchSize = defaults.object(forKey: "batchSize") as? Int ?? 20
        contextSize = defaults.object(forKey: "contextSize") as? Int ?? 4
        maxCPS = defaults.object(forKey: "maxCPS") as? Double ?? 17
        maxLineLength = defaults.object(forKey: "maxLineLength") as? Int ?? 42
        questionMode = QuestionMode(rawValue: defaults.string(forKey: "questionMode") ?? "") ?? .pause
        useFallbacks = defaults.object(forKey: "useFallbacks") as? Bool ?? true
        webSearchForProfiles = defaults.object(forKey: "webSearchForProfiles") as? Bool ?? true
        suggestProfileUpdates = defaults.object(forKey: "suggestProfileUpdates") as? Bool ?? true

        if let stored = defaults.string(forKey: "baseStyle"),
           !Self.previousDefaultStyleHashes.contains(Self.sha256(stored)) {
            baseStyle = stored
        } else {
            baseStyle = PromptBuilder.defaultStyle
        }

        let stored = Keychain.read()
        if let value = stored.value {
            apiKey = value
            apiKeySource = .keychain
        } else if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !env.isEmpty {
            apiKey = env
            apiKeySource = .environment
        } else {
            apiKey = ""
        }
        if stored.status != errSecSuccess && stored.status != errSecItemNotFound {
            keychainProblem = Keychain.accessHelp(stored.status)
        }
    }

    private static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    var target: Language { Language.find(targetLanguage) ?? .swedish }

    var hasAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    func makeClient() throws -> AnthropicClient {
        guard hasAPIKey else {
            throw AnthropicClient.APIError(message: L("No API key. Add your Anthropic key in Settings (⌘,)."))
        }
        return AnthropicClient(
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model,
            effort: effort,
            useFallbacks: useFallbacks
        )
    }
}

/// Stores the API key in the macOS keychain (the "SubTitle TransFixer" item in
/// Keychain Access). The key is read from there at every launch.
enum Keychain {
    private static let account = "anthropic-api-key"

    private static func query(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Reads the key. status is errSecSuccess, errSecItemNotFound or an error
    /// (e.g. when the keychain denied the app access). A key saved by the old
    /// app ("Undertextaren") is copied to the new item the first time.
    static func read() -> (value: String?, status: OSStatus) {
        let current = read(service: AppInfo.keychainService)
        guard current.status == errSecItemNotFound else { return current }
        let legacy = read(service: AppInfo.Legacy.keychainService)
        if let value = legacy.value {
            save(value)
            return (value, errSecSuccess)
        }
        return current
    }

    private static func read(service: String) -> (value: String?, status: OSStatus) {
        var q = query(service: service)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return (nil, status) }
        return (value, status)
    }

    /// Saves (or deletes, if value is empty). Updates an existing item instead
    /// of deleting it, so that any access rules are kept.
    @discardableResult
    static func save(_ value: String) -> OSStatus {
        let base = query(service: AppInfo.keychainService)
        if value.isEmpty {
            let status = SecItemDelete(base as CFDictionary)
            return status == errSecItemNotFound ? errSecSuccess : status
        }
        let data = Data(value.utf8)
        var status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "\(AppInfo.name) – Anthropic API key"
            status = SecItemAdd(add as CFDictionary, nil)
        }
        return status
    }

    static func describe(_ status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? L("error code {0}", status)
    }

    /// Explanation for the user when the keychain does not release the key.
    static func accessHelp(_ status: OSStatus) -> String {
        L("The keychain denied access ({0}). This happens when the app has been rebuilt with ad hoc signing. Build with a developer certificate (see README) and enter the key once more. If that does not help, delete the “{1}” item in Keychain Access and save again.",
          describe(status), AppInfo.keychainService)
    }
}
