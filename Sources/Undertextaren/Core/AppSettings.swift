import Foundation
import Observation
import Security

enum QuestionMode: String, CaseIterable, Identifiable {
    case pause    // pausa och fråga direkt
    case collect  // samla frågorna i sidopanelen, fortsätt översätta
    case off      // fråga aldrig
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pause: return "Pausa och fråga direkt"
        case .collect: return "Samla frågor, fortsätt översätta"
        case .off: return "Fråga aldrig"
        }
    }
}

@Observable
final class AppSettings {
    @ObservationIgnored private let defaults = UserDefaults.standard

    var model: String { didSet { defaults.set(model, forKey: "model") } }
    /// "auto" eller en språkkod (ISO 639-1)
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
    /// Grundstilen (motsvarar DEFAULT_STYLE / STYLE_FILE i skriptet).
    var baseStyle: String { didSet { defaults.set(baseStyle, forKey: "baseStyle") } }

    var apiKey: String {
        didSet {
            let status = Keychain.save(apiKey)
            keychainProblem = status == errSecSuccess ? nil : Keychain.accessHelp(status)
        }
    }
    /// Satt om nyckeln inte kunde läsas från eller sparas i nyckelringen.
    var keychainProblem: String?
    /// Var nyckeln kom ifrån vid start.
    var apiKeySource = ""

    struct Choice: Identifiable, Hashable {
        let id: String
        let label: String
    }

    static let modelChoices: [Choice] = [
        Choice(id: "claude-opus-5-5", label: "Claude Opus 5.5 – bäst kvalitet"),
        Choice(id: "claude-sonnet-5-5", label: "Claude Sonnet 5.5 – snabb och billigare"),
        Choice(id: "claude-haiku-5-5", label: "Claude Haiku 5.5 – billigast"),
        Choice(id: "claude-fable-5-1", label: "Claude Fable 5.1 – mest kapabel, dyrast"),
    ]
    static let effortChoices: [Choice] = [
        Choice(id: "", label: "Modellens standard"),
        Choice(id: "low", label: "Låg"),
        Choice(id: "medium", label: "Medel"),
        Choice(id: "high", label: "Hög"),
        Choice(id: "xhigh", label: "Mycket hög"),
    ]

    init() {
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
        // Byt automatiskt ut den gamla svenska grundstilen om den inte har ändrats.
        let storedStyle = defaults.string(forKey: "baseStyle")
        if storedStyle == nil || storedStyle == PromptBuilder.legacyDefaultStyle {
            baseStyle = PromptBuilder.defaultStyle
        } else {
            baseStyle = storedStyle!
        }
        let stored = Keychain.read()
        if let value = stored.value {
            apiKey = value
            apiKeySource = "nyckelringen"
        } else if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !env.isEmpty {
            apiKey = env
            apiKeySource = "miljövariabeln ANTHROPIC_API_KEY"
        } else {
            apiKey = ""
        }
        if stored.status != errSecSuccess && stored.status != errSecItemNotFound {
            keychainProblem = Keychain.accessHelp(stored.status)
        }
    }

    var target: Language { Language.find(targetLanguage) ?? .swedish }

    var hasAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    func makeClient() throws -> AnthropicClient {
        guard hasAPIKey else {
            throw AnthropicClient.APIError(message: "Ingen API-nyckel. Lägg in din Anthropic-nyckel under Inställningar (⌘,).")
        }
        return AnthropicClient(
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model,
            effort: effort,
            useFallbacks: useFallbacks
        )
    }
}

/// Sparar API-nyckeln i macOS-nyckelringen (posten "Undertextaren" i
/// Nyckelhanteraren). Nyckeln läses därifrån vid varje start.
enum Keychain {
    private static let service = "Undertextaren"
    private static let account = "anthropic-api-key"

    private static var base: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Läser nyckeln. status är errSecSuccess, errSecItemNotFound eller ett fel
    /// (t.ex. om nyckelringen nekade appen åtkomst).
    static func read() -> (value: String?, status: OSStatus) {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return (nil, status) }
        return (value, status)
    }

    /// Sparar (eller tar bort, om value är tomt). Uppdaterar en befintlig post
    /// i stället för att radera den, så att eventuella åtkomstregler behålls.
    @discardableResult
    static func save(_ value: String) -> OSStatus {
        if value.isEmpty {
            let status = SecItemDelete(base as CFDictionary)
            return status == errSecItemNotFound ? errSecSuccess : status
        }
        let data = Data(value.utf8)
        var status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "Undertextaren – Anthropic API-nyckel"
            status = SecItemAdd(add as CFDictionary, nil)
        }
        return status
    }

    static func describe(_ status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "felkod \(status)"
    }

    /// Förklaring till användaren när nyckelringen inte släpper fram nyckeln.
    static func accessHelp(_ status: OSStatus) -> String {
        "Nyckelringen nekade åtkomst (\(describe(status))). Det händer när appen har byggts om "
            + "med ad hoc-signering. Bygg med ett utvecklarcertifikat (se README) och lägg in nyckeln en "
            + "gång till. Hjälper inte det: ta bort posten ”Undertextaren” i Nyckelhanteraren och spara igen."
    }
}
