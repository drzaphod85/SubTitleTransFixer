import Foundation

/// The languages the user interface is available in.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case swedish = "sv"
    case norwegian = "nb"
    case danish = "da"
    case finnish = "fi"
    case icelandic = "is"

    var id: String { rawValue }

    /// The language's own name, so that it can always be found in the menu.
    var nativeName: String {
        switch self {
        case .system: return L("Same as macOS")
        case .english: return "English"
        case .swedish: return "Svenska"
        case .norwegian: return "Norsk (bokmål)"
        case .danish: return "Dansk"
        case .finnish: return "Suomi"
        case .icelandic: return "Íslenska"
        }
    }
}

/// Simple, table-based localization.
///
/// Every user-facing string is written in English in the code and wrapped in
/// `L("…")`. The English text is the key; the tables in `Strings+<code>.swift`
/// map it to the other languages. Placeholders are written `{0}`, `{1}` … so
/// translations can reorder them freely. Missing translations fall back to
/// English. `scripts/check-localization.py` verifies that every table has
/// every key with the same placeholders.
enum L10n {
    /// The active UI language code ("en", "sv", "nb", "da", "fi", "is").
    static var language = "en"

    static let tables: [String: [String: String]] = [
        "sv": stringsSV,
        "nb": stringsNB,
        "da": stringsDA,
        "fi": stringsFI,
        "is": stringsIS,
    ]

    /// Resolves a setting (a code or "system") to a supported language code.
    static func resolve(_ setting: String) -> String {
        if setting != AppLanguage.system.rawValue, setting == "en" || tables[setting] != nil {
            return setting
        }
        for preferred in Locale.preferredLanguages {
            let code = preferred.lowercased().split(separator: "-").first.map(String.init) ?? ""
            switch code {
            case "en": return "en"
            case "sv", "da", "fi", "is": return code
            case "nb", "nn", "no": return "nb"
            default: continue
            }
        }
        return "en"
    }

    static func apply(_ setting: String) {
        language = resolve(setting)
    }

    /// The English name of the UI language, for instructions to Claude
    /// ("write your questions in Swedish").
    static var languageNameForPrompts: String {
        switch language {
        case "sv": return "Swedish"
        case "nb": return "Norwegian (Bokmål)"
        case "da": return "Danish"
        case "fi": return "Finnish"
        case "is": return "Icelandic"
        default: return "English"
        }
    }

    /// Locale for formatting and for localized language names.
    static var locale: Locale { Locale(identifier: language) }
}

/// Looks up a user-facing string in the active language and fills in
/// `{0}`, `{1}` … with `args`.
func L(_ key: String, _ args: Any...) -> String {
    var text = L10n.tables[L10n.language]?[key] ?? key
    for (i, arg) in args.enumerated() {
        text = text.replacingOccurrences(of: "{\(i)}", with: String(describing: arg))
    }
    return text
}

/// Formats a decimal number in the active language ("17.5" / "17,5").
func formatNumber(_ value: Double, decimals: Int = 1) -> String {
    let f = NumberFormatter()
    f.locale = L10n.locale
    f.minimumFractionDigits = decimals
    f.maximumFractionDigits = decimals
    return f.string(from: NSNumber(value: value)) ?? String(format: "%.\(decimals)f", value)
}
