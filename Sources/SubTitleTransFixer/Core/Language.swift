import Foundation
import NaturalLanguage

/// A language that subtitles can be translated from or to.
struct Language: Identifiable, Hashable {
    /// ISO 639-1 code ("en", "sv"). Used in file names and settings.
    let code: String
    /// English name, used in prompts to Claude ("Swedish", "German").
    let englishName: String
    /// The language's own name ("Deutsch").
    let native: String
    /// Other codes and names found in file names and in NaturalLanguage.
    let aliases: [String]
    /// Rules that only apply when translating INTO this language.
    let targetRules: String

    var id: String { code }

    /// Name in the current UI language ("Tyska" in Swedish, "German" in English).
    var displayName: String {
        let lookup = code == "no" ? "nb" : code
        guard let name = L10n.locale.localizedString(forLanguageCode: lookup) else { return englishName }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Name for use inside a sentence, with the UI language's own capitalization
    /// ("svenska" in Swedish, "Swedish" in English).
    var inlineName: String {
        let lookup = code == "no" ? "nb" : code
        return L10n.locale.localizedString(forLanguageCode: lookup) ?? englishName
    }

    /// "German (Deutsch)"
    var menuName: String {
        displayName.lowercased() == native.lowercased() ? displayName : "\(displayName) (\(native))"
    }

    /// Every string that can identify the language in a file name.
    var fileTokens: Set<String> {
        Set(([code] + aliases).map { $0.lowercased() })
    }
}

extension Language {
    static let auto = "auto"

    static let all: [Language] = [
        Language(code: "sv", englishName: "Swedish", native: "Svenska", aliases: ["swe", "swedish", "svenska", "sve"],
                 targetRules: """
                 - Use informal "du" by default unless the context clearly calls for "ni"/"Ni"
                   (formal or historical address).
                 - Form the genitive of names without an apostrophe (Annas, Davids, Sarahs).
                 """),
        Language(code: "en", englishName: "English", native: "English", aliases: ["eng", "english"],
                 targetRules: """
                 - Write natural spoken English. Keep one spelling variant (British or
                   American) consistently; follow the work profile if it specifies one.
                 """),
        Language(code: "no", englishName: "Norwegian", native: "Norsk", aliases: ["nb", "nn", "nor", "nob", "nno", "norwegian", "norsk"],
                 targetRules: """
                 - Write Bokmål unless told otherwise. Use "du" by default; "De"/"Dem" only
                   in explicitly formal or historical contexts.
                 - Genitive -s without an apostrophe (Annas, Davids).
                 """),
        Language(code: "da", englishName: "Danish", native: "Dansk", aliases: ["dan", "danish", "dansk"],
                 targetRules: """
                 - Use "du" by default; "De" only in explicitly formal or historical contexts.
                 - Genitive -s without an apostrophe (Annas, Davids).
                 """),
        Language(code: "fi", englishName: "Finnish", native: "Suomi", aliases: ["fin", "finnish", "suomi"],
                 targetRules: """
                 - Use "sinuttelu" by default; "teitittely" in formal or historical contexts.
                 - Finnish subtitles tend to get longer – condense rather than exceed the CPS limit.
                 """),
        Language(code: "is", englishName: "Icelandic", native: "Íslenska", aliases: ["isl", "ice", "icelandic"],
                 targetRules: "- Follow Icelandic norms for declension of names and forms of address."),
        Language(code: "de", englishName: "German", native: "Deutsch", aliases: ["ger", "deu", "german", "deutsch"],
                 targetRules: """
                 - Choose "du" or "Sie" by relationship and context, and keep the choice
                   consistent between the same people throughout the work.
                 - Use German quotation marks („…“) when quotation marks are needed.
                 """),
        Language(code: "nl", englishName: "Dutch", native: "Nederlands", aliases: ["dut", "nld", "dutch", "nederlands"],
                 targetRules: "- Choose \"je/jij\" or \"u\" by relationship and keep the choice consistent."),
        Language(code: "fr", englishName: "French", native: "Français", aliases: ["fre", "fra", "french", "francais"],
                 targetRules: """
                 - Choose "tu" or "vous" by relationship and keep the choice consistent.
                 - French typography: non-breaking space before ! ? : ; and quotation marks « … ».
                 """),
        Language(code: "es", englishName: "Spanish", native: "Español", aliases: ["spa", "spanish", "espanol", "castellano"],
                 targetRules: """
                 - Choose "tú" or "usted" by relationship and keep the choice consistent.
                 - Use opening ¿ and ¡.
                 """),
        Language(code: "pt", englishName: "Portuguese", native: "Português", aliases: ["por", "portuguese", "pt-br", "pob"],
                 targetRules: "- Use Brazilian Portuguese unless the profile says European. Keep forms of address (você/tu/o senhor) consistent."),
        Language(code: "it", englishName: "Italian", native: "Italiano", aliases: ["ita", "italian", "italiano"],
                 targetRules: "- Choose \"tu\" or \"Lei\" by relationship and keep the choice consistent."),
        Language(code: "pl", englishName: "Polish", native: "Polski", aliases: ["pol", "polish", "polski"],
                 targetRules: "- Use \"ty\" or \"pan/pani\" by relationship and keep the choice consistent."),
        Language(code: "cs", englishName: "Czech", native: "Čeština", aliases: ["cze", "ces", "czech"],
                 targetRules: "- Choose \"tykání\" or \"vykání\" by relationship and keep the choice consistent."),
        Language(code: "et", englishName: "Estonian", native: "Eesti", aliases: ["est", "estonian"], targetRules: ""),
        Language(code: "lv", englishName: "Latvian", native: "Latviešu", aliases: ["lav", "latvian"], targetRules: ""),
        Language(code: "lt", englishName: "Lithuanian", native: "Lietuvių", aliases: ["lit", "lithuanian"], targetRules: ""),
        Language(code: "hu", englishName: "Hungarian", native: "Magyar", aliases: ["hun", "hungarian"], targetRules: ""),
        Language(code: "ro", englishName: "Romanian", native: "Română", aliases: ["rum", "ron", "romanian"], targetRules: ""),
        Language(code: "el", englishName: "Greek", native: "Ελληνικά", aliases: ["gre", "ell", "greek"], targetRules: ""),
        Language(code: "tr", englishName: "Turkish", native: "Türkçe", aliases: ["tur", "turkish"],
                 targetRules: "- Choose \"sen\" or \"siz\" by relationship and keep the choice consistent."),
        Language(code: "ru", englishName: "Russian", native: "Русский", aliases: ["rus", "russian"],
                 targetRules: "- Choose \"ты\" or \"вы\" by relationship and keep the choice consistent."),
        Language(code: "uk", englishName: "Ukrainian", native: "Українська", aliases: ["ukr", "ukrainian"],
                 targetRules: "- Choose \"ти\" or \"ви\" by relationship and keep the choice consistent."),
        Language(code: "ar", englishName: "Arabic", native: "العربية", aliases: ["ara", "arabic"], targetRules: ""),
        Language(code: "he", englishName: "Hebrew", native: "עברית", aliases: ["heb", "hebrew", "iw"], targetRules: ""),
        Language(code: "fa", englishName: "Persian", native: "فارسی", aliases: ["per", "fas", "persian", "farsi"], targetRules: ""),
        Language(code: "hi", englishName: "Hindi", native: "हिन्दी", aliases: ["hin", "hindi"], targetRules: ""),
        Language(code: "th", englishName: "Thai", native: "ไทย", aliases: ["tha", "thai"], targetRules: ""),
        Language(code: "vi", englishName: "Vietnamese", native: "Tiếng Việt", aliases: ["vie", "vietnamese"], targetRules: ""),
        Language(code: "id", englishName: "Indonesian", native: "Bahasa Indonesia", aliases: ["ind", "indonesian"], targetRules: ""),
        Language(code: "zh", englishName: "Chinese", native: "中文", aliases: ["chi", "zho", "chinese", "zh-hans", "zh-hant", "chs", "cht"],
                 targetRules: "- Use Simplified Chinese unless the profile says Traditional."),
        Language(code: "ja", englishName: "Japanese", native: "日本語", aliases: ["jpn", "japanese"],
                 targetRules: "- Adapt the politeness level (keigo) to the relationship and keep it consistent."),
        Language(code: "ko", englishName: "Korean", native: "한국어", aliases: ["kor", "korean"],
                 targetRules: "- Adapt the speech level to the relationship and keep it consistent."),
    ]

    static func find(_ code: String?) -> Language? {
        guard let c = code?.lowercased(), !c.isEmpty, c != auto else { return nil }
        return all.first { $0.code == c } ?? all.first { $0.fileTokens.contains(c) }
    }

    static let english = find("en")!
    static let swedish = find("sv")!

    /// Rules for a target language that has no rules of its own.
    static let genericTargetRules = """
    - Follow the target language's conventions for forms of address (formal/informal),
      declension of names and punctuation in subtitles, and keep the choices consistent.
    """
}

// MARK: - Language detection

struct LanguageDetection: Hashable {
    var language: Language
    /// 0…1
    var confidence: Double
    /// What the detection was based on.
    var basis: Basis

    enum Basis: Hashable {
        case text, fileName, textAndFileName

        var label: String {
            switch self {
            case .text: return L("the text")
            case .fileName: return L("the file name")
            case .textAndFileName: return L("the text and the file name")
            }
        }
    }

    var summary: String {
        L("{0} ({1} % certain, based on {2})", language.displayName, Int((confidence * 100).rounded()), basis.label)
    }
}

enum LanguageDetector {
    /// Hint from the file name, e.g. "Show.S01E01.ger.srt" → German.
    static func hint(fromFileName fileName: String) -> Language? {
        let base = (fileName as NSString).deletingPathExtension.lowercased()
        let tokens = base
            .replacingOccurrences(of: "_", with: ".")
            .replacingOccurrences(of: "-", with: ".")
            .replacingOccurrences(of: " ", with: ".")
            .split(separator: ".")
            .map(String.init)
        // Search from the end – the language code is nearly always last ("….en.forced.srt").
        let ignore: Set<String> = ["forced", "sdh", "hi", "cc", "full", "default"]
        for token in tokens.reversed().prefix(4) where !ignore.contains(token) {
            if let lang = Language.all.first(where: { $0.fileTokens.contains(token) }) { return lang }
        }
        return nil
    }

    /// Detects the language of the subtitle text with macOS NaturalLanguage.
    static func detect(texts: [String], fileName: String) -> LanguageDetection? {
        let sample = texts.prefix(400)
            .map(stripMarkup)
            .joined(separator: "\n")
        let fileHint = hint(fromFileName: fileName)

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
            .compactMap { pair -> (Language, Double)? in
                guard let lang = Language.find(pair.key.rawValue) else { return nil }
                return (lang, pair.value)
            }
            .sorted { $0.1 > $1.1 }

        if let top = hypotheses.first, top.1 >= 0.6 {
            let agrees = fileHint == top.0
            return LanguageDetection(language: top.0, confidence: top.1, basis: agrees ? .textAndFileName : .text)
        }
        if let fileHint {
            // Uncertain text – trust the file name, especially if the text points the same way.
            let p = hypotheses.first { $0.0 == fileHint }?.1 ?? 0
            return LanguageDetection(language: fileHint, confidence: max(p, 0.6), basis: .fileName)
        }
        if let top = hypotheses.first {
            return LanguageDetection(language: top.0, confidence: top.1, basis: .text)
        }
        return nil
    }

    private static func stripMarkup(_ s: String) -> String {
        var t = s
        for pattern in [#"<[^>]+>"#, #"\{[^}]*\}"#, #"\[[^\]]*\]"#, #"♪"#] {
            t = t.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return t
    }
}
