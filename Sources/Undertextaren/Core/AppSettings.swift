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
        didSet { Keychain.save(apiKey) }
    }

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
        effort = defaults.string(forKey: "effort") ?? "medium"
        batchSize = defaults.object(forKey: "batchSize") as? Int ?? 20
        contextSize = defaults.object(forKey: "contextSize") as? Int ?? 4
        maxCPS = defaults.object(forKey: "maxCPS") as? Double ?? 17
        maxLineLength = defaults.object(forKey: "maxLineLength") as? Int ?? 42
        questionMode = QuestionMode(rawValue: defaults.string(forKey: "questionMode") ?? "") ?? .pause
        useFallbacks = defaults.object(forKey: "useFallbacks") as? Bool ?? true
        webSearchForProfiles = defaults.object(forKey: "webSearchForProfiles") as? Bool ?? true
        suggestProfileUpdates = defaults.object(forKey: "suggestProfileUpdates") as? Bool ?? true
        baseStyle = defaults.string(forKey: "baseStyle") ?? PromptBuilder.defaultStyle
        apiKey = Keychain.read()
            ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
            ?? ""
    }

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

/// Sparar API-nyckeln i macOS-nyckelringen.
enum Keychain {
    private static let service = "Undertextaren"
    private static let account = "anthropic-api-key"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return nil }
        return value
    }

    static func save(_ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
