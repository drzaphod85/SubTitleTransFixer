import Foundation

// MARK: - Cues

enum CueStatus: String, Hashable {
    case pending      // not translated yet
    case translating  // sent to Claude
    case done         // translated
    case question     // translated, but Claude has an open question
    case edited       // edited by hand
    case failed       // the request failed
}

struct Cue: Identifiable, Hashable {
    /// Position in the file (1, 2, 3 …). Used as the id towards the API so that
    /// duplicate or broken numbering in the source file does no harm.
    let seq: Int
    /// The number written in the .srt file. Written back unchanged.
    let number: String
    let timecode: String
    let original: String
    var translation: String = ""
    var status: CueStatus = .pending

    var id: Int { seq }

    var duration: Double? { SRT.duration(of: timecode) }

    var startTime: String {
        let start = timecode.components(separatedBy: "-->").first ?? timecode
        return start.trimmingCharacters(in: .whitespaces)
    }

    func cps(of text: String) -> Double? {
        guard let d = duration, !text.isEmpty else { return nil }
        return Double(text.replacingOccurrences(of: "\n", with: "").count) / d
    }

    var translationCPS: Double? { cps(of: translation) }

    func longestLine(of text: String) -> Int {
        text.components(separatedBy: "\n").map { $0.count }.max() ?? 0
    }
}

// MARK: - Prompt profiles (one per TV series / film)

enum MediaKind: String, Codable, CaseIterable, Identifiable {
    case series, film
    var id: String { rawValue }
    var label: String { self == .series ? L("TV series") : L("Film") }
    var symbol: String { self == .series ? "tv" : "film" }
}

struct CharacterNote: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var description: String
    /// How the person speaks / is addressed (formal/informal, dialect, jargon …)
    var speech: String = ""

    init(id: UUID = UUID(), name: String, description: String, speech: String = "") {
        self.id = id; self.name = name; self.description = description; self.speech = speech
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        speech = try c.decodeIfPresent(String.self, forKey: .speech) ?? ""
    }
}

struct GlossaryEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var source: String
    var target: String
    var note: String = ""

    init(id: UUID = UUID(), source: String, target: String, note: String = "") {
        self.id = id; self.source = source; self.target = target; self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        target = try c.decodeIfPresent(String.self, forKey: .target) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

struct SeriesProfile: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    /// Other names files may use, e.g. "ACGAS", "All Creatures".
    var aliases: [String] = []
    var kind: MediaKind = .series
    /// The language the prompt is written for translating INTO (ISO 639-1).
    var targetLanguage: String = "sv"
    var year: String = ""
    var synopsis: String = ""
    /// Work-specific style guide – added on top of the base style.
    var styleGuide: String = ""
    var characters: [CharacterNote] = []
    var glossary: [GlossaryEntry] = []
    var notes: [String] = []
    var translatedEpisodes: [String] = []
    var createdAt = Date()
    var updatedAt = Date()

    init(title: String, kind: MediaKind = .series, targetLanguage: String = "sv") {
        self.title = title
        self.kind = kind
        self.targetLanguage = targetLanguage
    }

    // Lenient decoding so that older saved files keep working
    // when new fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? L("Untitled")
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        kind = try c.decodeIfPresent(MediaKind.self, forKey: .kind) ?? .series
        targetLanguage = try c.decodeIfPresent(String.self, forKey: .targetLanguage) ?? "sv"
        year = try c.decodeIfPresent(String.self, forKey: .year) ?? ""
        synopsis = try c.decodeIfPresent(String.self, forKey: .synopsis) ?? ""
        styleGuide = try c.decodeIfPresent(String.self, forKey: .styleGuide) ?? ""
        characters = try c.decodeIfPresent([CharacterNote].self, forKey: .characters) ?? []
        glossary = try c.decodeIfPresent([GlossaryEntry].self, forKey: .glossary) ?? []
        notes = try c.decodeIfPresent([String].self, forKey: .notes) ?? []
        translatedEpisodes = try c.decodeIfPresent([String].self, forKey: .translatedEpisodes) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    var subtitle: String {
        var parts = [kind.label]
        if let lang = Language.find(targetLanguage) { parts.append("→ \(lang.displayName)") }
        if !year.isEmpty { parts.append(year) }
        if !translatedEpisodes.isEmpty { parts.append(L("{0} episodes", translatedEpisodes.count)) }
        return parts.joined(separator: " · ")
    }

    func hasCharacter(named name: String) -> Bool {
        let n = TitleMatcher.normalize(name)
        return characters.contains { TitleMatcher.normalize($0.name) == n }
    }

    func hasTerm(_ source: String) -> Bool {
        let n = TitleMatcher.normalize(source)
        return glossary.contains { TitleMatcher.normalize($0.source) == n }
    }
}

// MARK: - Questions and suggestions during translation

/// A decision made by the user – included in the prompt for the rest of the run.
struct Clarification: Identifiable, Hashable {
    let id = UUID()
    var question: String
    var answer: String
}

struct TranslatorQuestion: Identifiable, Hashable {
    let id = UUID()
    var cueSeqs: [Int]
    var question: String
    var options: [String]
    var suggested: String?
    var answer: String?
    var isResolved: Bool { answer != nil }
}

struct ProfileSuggestion: Identifiable, Hashable {
    enum Kind: Hashable {
        case character(CharacterNote)
        case term(GlossaryEntry)
        case note(String)
    }
    let id = UUID()
    var kind: Kind
    var accepted = true
    var foundAtCue: Int?

    var dedupeKey: String {
        switch kind {
        case .character(let c): return "c:" + TitleMatcher.normalize(c.name)
        case .term(let g): return "t:" + TitleMatcher.normalize(g.source)
        case .note(let n): return "n:" + TitleMatcher.normalize(n)
        }
    }
}
