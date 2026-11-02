import Foundation

// MARK: - Repliker

enum CueStatus: String, Hashable {
    case pending      // ej översatt ännu
    case translating  // skickad till Claude
    case done         // översatt
    case question     // översatt, men Claude har en öppen fråga
    case edited       // ändrad för hand
    case failed       // anropet misslyckades
}

struct Cue: Identifiable, Hashable {
    /// Löpnummer i filen (1, 2, 3 …). Används som id mot API:t så att
    /// dubbletter eller trasig numrering i originalfilen inte ställer till det.
    let seq: Int
    /// Numret som står i .srt-filen. Skrivs tillbaka oförändrat.
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

// MARK: - Promptprofiler (en per TV-serie / film)

enum MediaKind: String, Codable, CaseIterable, Identifiable {
    case series, film
    var id: String { rawValue }
    var label: String { self == .series ? "TV-serie" : "Film" }
    var symbol: String { self == .series ? "tv" : "film" }
}

struct CharacterNote: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var description: String
    /// Hur personen talar / tilltalas (du/ni, dialekt, jargong …)
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
    /// Andra namn som filer kan heta, t.ex. "ACGAS", "All Creatures".
    var aliases: [String] = []
    var kind: MediaKind = .series
    var year: String = ""
    var synopsis: String = ""
    /// Verksspecifik stilguide – läggs ovanpå grundstilen.
    var styleGuide: String = ""
    var characters: [CharacterNote] = []
    var glossary: [GlossaryEntry] = []
    var notes: [String] = []
    var translatedEpisodes: [String] = []
    var createdAt = Date()
    var updatedAt = Date()

    init(title: String, kind: MediaKind = .series) {
        self.title = title
        self.kind = kind
    }

    // Tolerant avkodning så att äldre sparade filer fortsätter fungera
    // när nya fält läggs till.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Namnlös"
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        kind = try c.decodeIfPresent(MediaKind.self, forKey: .kind) ?? .series
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
        if !year.isEmpty { parts.append(year) }
        if !translatedEpisodes.isEmpty { parts.append("\(translatedEpisodes.count) avsnitt") }
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

// MARK: - Frågor och förslag under översättning

/// Ett beslut som användaren har fattat – följer med i prompten resten av körningen.
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
