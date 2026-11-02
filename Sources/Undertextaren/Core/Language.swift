import Foundation
import NaturalLanguage

/// Ett språk som kan översättas från eller till.
struct Language: Identifiable, Hashable {
    /// ISO 639-1 (t.ex. "en", "sv"). Används i filnamn och inställningar.
    let code: String
    /// Svenskt namn i gemener, för prompter ("engelska", "tyska").
    let name: String
    /// Språkets eget namn ("Deutsch").
    let native: String
    /// Andra koder/namn som förekommer i filnamn och hos NaturalLanguage.
    let aliases: [String]
    /// Regler som bara gäller när man översätter TILL det här språket.
    let targetRules: String

    var id: String { code }
    /// "Engelska"
    var displayName: String { name.prefix(1).uppercased() + name.dropFirst() }
    /// "Tyska (Deutsch)"
    var menuName: String { native.lowercased() == name ? displayName : "\(displayName) (\(native))" }

    /// Alla strängar som kan identifiera språket i ett filnamn.
    var fileTokens: Set<String> {
        Set(([code] + aliases).map { $0.lowercased() })
    }
}

extension Language {
    static let auto = "auto"

    static let all: [Language] = [
        Language(code: "sv", name: "svenska", native: "Svenska", aliases: ["swe", "swedish", "svenska", "sve"],
                 targetRules: """
                 - Du-tilltal som grundregel, om inte sammanhanget tydligt kräver ni/Ni
                   (t.ex. formellt eller historiskt tilltal).
                 - Böj namn med svensk genitiv utan apostrof (Annas, Davids, Sarahs).
                 """),
        Language(code: "en", name: "engelska", native: "English", aliases: ["eng", "english"],
                 targetRules: """
                 - Write natural spoken English. Keep one spelling variant (British or
                   American) consistently; follow the work profile if it specifies one.
                 """),
        Language(code: "no", name: "norska", native: "Norsk", aliases: ["nb", "nn", "nor", "nob", "nno", "norwegian", "norsk"],
                 targetRules: """
                 - Skriv bokmål om inget annat anges. Du-tilltal som grundregel; De/Dem
                   bara i uttalat formella eller historiska sammanhang.
                 - Genitiv-s utan apostrof (Annas, Davids).
                 """),
        Language(code: "da", name: "danska", native: "Dansk", aliases: ["dan", "danish", "dansk"],
                 targetRules: """
                 - Du-tilltal som grundregel; De bara i uttalat formella eller historiska sammanhang.
                 - Genitiv-s utan apostrof (Annas, Davids).
                 """),
        Language(code: "fi", name: "finska", native: "Suomi", aliases: ["fin", "finnish", "suomi"],
                 targetRules: """
                 - Sinuttelu som grundregel; teitittely i formella eller historiska sammanhang.
                 - Undertexter på finska blir ofta längre – förtäta hellre än att överskrida CPS.
                 """),
        Language(code: "is", name: "isländska", native: "Íslenska", aliases: ["isl", "ice", "icelandic"],
                 targetRules: "- Följ isländska normer för böjning av namn och tilltal."),
        Language(code: "de", name: "tyska", native: "Deutsch", aliases: ["ger", "deu", "german", "deutsch"],
                 targetRules: """
                 - Välj du eller Sie efter relation och sammanhang, och håll valet
                   konsekvent mellan samma personer genom hela verket.
                 - Använd tyska citattecken („…“) om citattecken behövs.
                 """),
        Language(code: "nl", name: "nederländska", native: "Nederlands", aliases: ["dut", "nld", "dutch", "nederlands"],
                 targetRules: "- Välj je/jij eller u efter relation och håll valet konsekvent."),
        Language(code: "fr", name: "franska", native: "Français", aliases: ["fre", "fra", "french", "francais"],
                 targetRules: """
                 - Välj tu eller vous efter relation och håll valet konsekvent.
                 - Fransk typografi: hårt mellanslag före ! ? : ; och citattecken « … ».
                 """),
        Language(code: "es", name: "spanska", native: "Español", aliases: ["spa", "spanish", "espanol", "castellano"],
                 targetRules: """
                 - Välj tú eller usted efter relation och håll valet konsekvent.
                 - Använd inledande ¿ och ¡.
                 """),
        Language(code: "pt", name: "portugisiska", native: "Português", aliases: ["por", "portuguese", "pt-br", "pob"],
                 targetRules: "- Använd brasiliansk portugisiska om profilen inte anger europeisk. Håll tilltalet (você/tu/o senhor) konsekvent."),
        Language(code: "it", name: "italienska", native: "Italiano", aliases: ["ita", "italian", "italiano"],
                 targetRules: "- Välj tu eller Lei efter relation och håll valet konsekvent."),
        Language(code: "pl", name: "polska", native: "Polski", aliases: ["pol", "polish", "polski"],
                 targetRules: "- Använd ty eller pan/pani efter relation och håll valet konsekvent."),
        Language(code: "cs", name: "tjeckiska", native: "Čeština", aliases: ["cze", "ces", "czech"],
                 targetRules: "- Välj tykání eller vykání efter relation och håll valet konsekvent."),
        Language(code: "et", name: "estniska", native: "Eesti", aliases: ["est", "estonian"], targetRules: ""),
        Language(code: "lv", name: "lettiska", native: "Latviešu", aliases: ["lav", "latvian"], targetRules: ""),
        Language(code: "lt", name: "litauiska", native: "Lietuvių", aliases: ["lit", "lithuanian"], targetRules: ""),
        Language(code: "hu", name: "ungerska", native: "Magyar", aliases: ["hun", "hungarian"], targetRules: ""),
        Language(code: "ro", name: "rumänska", native: "Română", aliases: ["rum", "ron", "romanian"], targetRules: ""),
        Language(code: "el", name: "grekiska", native: "Ελληνικά", aliases: ["gre", "ell", "greek"], targetRules: ""),
        Language(code: "tr", name: "turkiska", native: "Türkçe", aliases: ["tur", "turkish"],
                 targetRules: "- Välj sen eller siz efter relation och håll valet konsekvent."),
        Language(code: "ru", name: "ryska", native: "Русский", aliases: ["rus", "russian"],
                 targetRules: "- Välj ty eller vy efter relation och håll valet konsekvent."),
        Language(code: "uk", name: "ukrainska", native: "Українська", aliases: ["ukr", "ukrainian"],
                 targetRules: "- Välj ty eller vy efter relation och håll valet konsekvent."),
        Language(code: "ar", name: "arabiska", native: "العربية", aliases: ["ara", "arabic"], targetRules: ""),
        Language(code: "he", name: "hebreiska", native: "עברית", aliases: ["heb", "hebrew", "iw"], targetRules: ""),
        Language(code: "fa", name: "persiska", native: "فارسی", aliases: ["per", "fas", "persian", "farsi"], targetRules: ""),
        Language(code: "hi", name: "hindi", native: "हिन्दी", aliases: ["hin", "hindi"], targetRules: ""),
        Language(code: "th", name: "thailändska", native: "ไทย", aliases: ["tha", "thai"], targetRules: ""),
        Language(code: "vi", name: "vietnamesiska", native: "Tiếng Việt", aliases: ["vie", "vietnamese"], targetRules: ""),
        Language(code: "id", name: "indonesiska", native: "Bahasa Indonesia", aliases: ["ind", "indonesian"], targetRules: ""),
        Language(code: "zh", name: "kinesiska", native: "中文", aliases: ["chi", "zho", "chinese", "zh-hans", "zh-hant", "chs", "cht"],
                 targetRules: "- Använd förenklad kinesiska om profilen inte anger traditionell."),
        Language(code: "ja", name: "japanska", native: "日本語", aliases: ["jpn", "japanese"],
                 targetRules: "- Anpassa artighetsnivån (keigo) efter relation och håll den konsekvent."),
        Language(code: "ko", name: "koreanska", native: "한국어", aliases: ["kor", "korean"],
                 targetRules: "- Anpassa artighetsnivån efter relation och håll den konsekvent."),
    ]

    static func find(_ code: String?) -> Language? {
        guard let c = code?.lowercased(), !c.isEmpty, c != auto else { return nil }
        return all.first { $0.code == c } ?? all.first { $0.fileTokens.contains(c) }
    }

    static let english = find("en")!
    static let swedish = find("sv")!

    /// Regler för ett målspråk som saknar egna.
    static let genericTargetRules = """
    - Följ målspråkets konventioner för tilltal (formellt/informellt), böjning av
      namn och interpunktion i undertexter, och håll valen konsekventa.
    """
}

// MARK: - Språkigenkänning

struct LanguageDetection: Hashable {
    var language: Language
    /// 0…1
    var confidence: Double
    /// "text", "filnamn" eller "text + filnamn"
    var basis: String

    var summary: String {
        "\(language.displayName) (\(Int((confidence * 100).rounded())) % säkert, utifrån \(basis))"
    }
}

enum LanguageDetector {
    /// Ledtråd ur filnamnet, t.ex. "Show.S01E01.ger.srt" → tyska.
    static func hint(fromFileName fileName: String) -> Language? {
        let base = (fileName as NSString).deletingPathExtension.lowercased()
        let tokens = base
            .replacingOccurrences(of: "_", with: ".")
            .replacingOccurrences(of: "-", with: ".")
            .replacingOccurrences(of: " ", with: ".")
            .split(separator: ".")
            .map(String.init)
        // Leta bakifrån – språkkoden står nästan alltid sist ("…​.en.forced.srt")
        let ignore: Set<String> = ["forced", "sdh", "hi", "cc", "full", "default"]
        for token in tokens.reversed().prefix(4) where !ignore.contains(token) {
            if let lang = Language.all.first(where: { $0.fileTokens.contains(token) }) { return lang }
        }
        return nil
    }

    /// Känner igen språket ur undertexternas text med macOS NaturalLanguage.
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
            return LanguageDetection(language: top.0, confidence: top.1, basis: agrees ? "text + filnamn" : "text")
        }
        if let fileHint {
            // Osäker text – lita på filnamnet, särskilt om texten pekar åt samma håll.
            let p = hypotheses.first { $0.0 == fileHint }?.1 ?? 0
            return LanguageDetection(language: fileHint, confidence: max(p, 0.6), basis: "filnamn")
        }
        if let top = hypotheses.first {
            return LanguageDetection(language: top.0, confidence: top.1, basis: "text")
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
