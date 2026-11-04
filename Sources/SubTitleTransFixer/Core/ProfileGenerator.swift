import Foundation

/// Lets Claude create (or improve) a translation profile for a specific work.
enum ProfileGenerator {
    struct Request {
        var title: String
        var kind: MediaKind
        var year: String
        var extraInfo: String
        /// A selection of lines from the loaded file (to anchor the tone).
        var sampleLines: [String]
        var webSearch: Bool
        /// Existing profile to improve/complete (nil = create a new one).
        var existing: SeriesProfile?
        /// The language of the subtitles.
        var source: Language = .english
        /// The language the profile is for translating into.
        var target: Language = .swedish
        /// Profile for the same work but another target language – used as a source of facts.
        var reference: SeriesProfile? = nil
    }

    /// {SOURCE}, {TARGET} and {UI_LANGUAGE} are replaced with language names.
    static let systemTemplate = """
    You are a very experienced subtitle translator and editor with broad knowledge of
    film and TV. Your task is to write a WORK PROFILE that another translator (an AI)
    receives as instructions when translating the subtitles of a specific work from
    {SOURCE} into {TARGET}. The profile is added on top of a general subtitling style
    guide, so do not repeat general rules about line length, CPS or markup – focus on
    what is special about this particular work.

    A good profile contains:
    - synopsis: 2–4 sentences about setting, period, genre and tone.
    - style_guide: concrete, work-specific instructions (written in {UI_LANGUAGE}, the
      user's language, with examples in {TARGET}), e.g. a period-appropriate tone
      (avoid anachronisms), when formal or informal address is used and between whom,
      how dialects and social differences are rendered (natural {TARGET} – no invented
      dialect), technical terms in the work's world (e.g. veterinary medicine,
      military, sci-fi technology), recurring expressions, swearing and humour.
    - characters: main characters and important supporting characters with a short
      description and how they speak to / address each other (titles, first names,
      nicknames). Write descriptions in {UI_LANGUAGE}.
    - glossary: recurring names, places, titles and terms with the recommended
      {TARGET} translation (or "keep" if they stay as in the original).
    - notes: anything else worth knowing, including things you are unsure about,
      written in {UI_LANGUAGE}.

    Be factual. If you do not know the work for certain, say so in notes and base the
    profile on what you can see in the lines instead of making things up.
    If you have web search, use it to check the cast, setting and established
    {TARGET} names.

    Finally, reply ONLY with a JSON object of the form:
    {"title": "...", "aliases": ["..."], "kind": "series" | "film", "year": "...",
     "synopsis": "...", "style_guide": "...",
     "characters": [{"name": "...", "description": "...", "speech": "..."}],
     "glossary": [{"source": "...", "target": "...", "note": "..."}],
     "notes": ["..."]}
    """

    static func generate(_ r: Request, client: AnthropicClient) async throws -> SeriesProfile {
        var user = ""
        if let existing = r.existing {
            user += "Improve and complete this existing profile. Keep everything the user has "
            user += "written unless it is obviously wrong, and return the whole updated profile."
            user += "\n\nEXISTING PROFILE (JSON):\n" + encode(existing) + "\n\n"
        } else {
            user += "Create a new work profile.\n\n"
        }
        if let ref = r.reference {
            let refLang = Language.find(ref.targetLanguage)?.englishName ?? ref.targetLanguage
            user += "There is already a profile for this work for translation into \(refLang). Use its facts "
            user += "about the work, the setting and the characters, but rewrite the rules of address, style "
            user += "and glossary for \(r.target.englishName).\n\nPROFILE FOR \(refLang.uppercased()) (JSON):\n"
            user += encode(ref) + "\n\n"
        }
        user += "Title: \(r.title)\nType: \(r.kind == .series ? "TV series" : "film")\n"
        user += "From: \(r.source.englishName)\nInto: \(r.target.englishName)\n"
        if !r.year.isEmpty { user += "Year: \(r.year)\n" }
        if !r.extraInfo.isEmpty { user += "\nThe user's own wishes and information:\n\(r.extraInfo)\n" }
        if !r.sampleLines.isEmpty {
            user += "\nEXCERPT FROM THE \(r.source.englishName.uppercased()) SUBTITLES (for tone and names):\n"
            user += r.sampleLines.joined(separator: "\n")
            user += "\n"
        }

        let system = systemTemplate
            .replacingOccurrences(of: "{SOURCE}", with: r.source.englishName)
            .replacingOccurrences(of: "{TARGET}", with: r.target.englishName)
            .replacingOccurrences(of: "{UI_LANGUAGE}", with: L10n.languageNameForPrompts)
        let raw = try await client.complete(system: system, user: user, maxTokens: 16000, webSearch: r.webSearch)
        guard let obj = try JSONExtract.value(from: raw) as? [String: Any] else {
            throw AnthropicClient.APIError(message: L("Claude did not return a profile."))
        }
        var p = profile(from: obj, base: r.existing, fallbackTitle: r.title, fallbackKind: r.kind)
        if r.existing == nil { p.targetLanguage = r.target.code }
        return p
    }

    static let structureSystem = """
    You are an experienced subtitle editor. The user has an existing, hand-written
    translation prompt (style guide) for a specific work. Your task is to transfer it
    into a structured WORK PROFILE without losing anything.

    Rules:
    - Lose NOTHING. Every instruction, rule, example and name in the original must
      remain somewhere in the profile.
    - Character descriptions (who someone is, how they speak, forms of address) → characters.
    - Names, places, titles and terms with a given translation (or "keep") → glossary.
    - Everything else (tone, period, rules of address, dialect, swearing, examples,
      technical rules) → style_guide, as verbatim as possible. Keep the original's
      headings and bullet lists.
    - Do not add rules of your own. You may write a synopsis if you know the work and
      fill in year and aliases if you know them for certain.
    - Keep the original's language.

    Reply ONLY with a JSON object of the form:
    {"title": "...", "aliases": ["..."], "kind": "series" | "film", "year": "...",
     "synopsis": "...", "style_guide": "...",
     "characters": [{"name": "...", "description": "...", "speech": "..."}],
     "glossary": [{"source": "...", "target": "...", "note": "..."}],
     "notes": ["..."]}
    """

    /// Turns an existing, hand-written prompt into a structured profile.
    static func structure(text: String, title: String, kind: MediaKind, target: Language,
                          into existing: SeriesProfile?, client: AnthropicClient) async throws -> SeriesProfile {
        var user = "Title: \(title)\nType: \(kind == .series ? "TV series" : "film")\n"
        user += "The prompt is for translation into: \(target.englishName)\n"
        user += "\nEXISTING PROMPT:\n<<<\n\(text)\n>>>\n"
        if existing != nil {
            user += "\nThe prompt replaces the style guide of an existing profile. Its characters and "
            user += "terms are already there; only include them in the reply if the original says something new about them.\n"
        }
        let raw = try await client.complete(system: structureSystem, user: user, maxTokens: 16000)
        guard let obj = try JSONExtract.value(from: raw) as? [String: Any] else {
            throw AnthropicClient.APIError(message: L("Claude did not return a profile."))
        }
        var base = existing
        // When updating, the new text replaces the style guide entirely.
        base?.styleGuide = ""
        var p = profile(from: obj, base: base, fallbackTitle: title, fallbackKind: kind)
        if p.styleGuide.isEmpty { p.styleGuide = text } // safety net
        if existing == nil { p.title = title; p.kind = kind }
        p.targetLanguage = target.code
        return p
    }

    static func profile(from obj: [String: Any], base: SeriesProfile?, fallbackTitle: String, fallbackKind: MediaKind) -> SeriesProfile {
        var p = base ?? SeriesProfile(title: fallbackTitle, kind: fallbackKind)
        let title = JSONExtract.string(obj["title"])
        if base == nil, !title.isEmpty { p.title = title }
        if base == nil { p.kind = MediaKind(rawValue: JSONExtract.string(obj["kind"])) ?? fallbackKind }

        var aliases = Set(p.aliases)
        for a in JSONExtract.strings(obj["aliases"]) where TitleMatcher.normalize(a) != TitleMatcher.normalize(p.title) {
            aliases.insert(a)
        }
        // Add the title from the file name as an alias if Claude chose another official name
        if TitleMatcher.normalize(fallbackTitle) != TitleMatcher.normalize(p.title), !fallbackTitle.isEmpty {
            aliases.insert(fallbackTitle)
        }
        p.aliases = aliases.sorted()

        let year = JSONExtract.string(obj["year"])
        if !year.isEmpty { p.year = year }
        let synopsis = JSONExtract.string(obj["synopsis"])
        if !synopsis.isEmpty { p.synopsis = synopsis }
        let style = JSONExtract.string(obj["style_guide"])
        if !style.isEmpty { p.styleGuide = style }

        // Replace the lists with Claude's (which already contain the old ones when improving),
        // but keep the ids of existing entries.
        let chars = (obj["characters"] as? [[String: Any]] ?? []).compactMap { c -> CharacterNote? in
            let name = JSONExtract.string(c["name"])
            guard !name.isEmpty else { return nil }
            let old = p.characters.first { TitleMatcher.normalize($0.name) == TitleMatcher.normalize(name) }
            return CharacterNote(id: old?.id ?? UUID(), name: name,
                                 description: JSONExtract.string(c["description"]),
                                 speech: JSONExtract.string(c["speech"]))
        }
        if !chars.isEmpty { p.characters = merged(old: p.characters, new: chars) { $0.name } }

        let terms = (obj["glossary"] as? [[String: Any]] ?? []).compactMap { g -> GlossaryEntry? in
            let source = JSONExtract.string(g["source"])
            guard !source.isEmpty else { return nil }
            let old = p.glossary.first { TitleMatcher.normalize($0.source) == TitleMatcher.normalize(source) }
            return GlossaryEntry(id: old?.id ?? UUID(), source: source,
                                 target: JSONExtract.string(g["target"]),
                                 note: JSONExtract.string(g["note"]))
        }
        if !terms.isEmpty { p.glossary = merged(old: p.glossary, new: terms) { $0.source } }

        let notes = JSONExtract.strings(obj["notes"])
        if !notes.isEmpty {
            var all = p.notes
            for n in notes where !all.contains(n) { all.append(n) }
            p.notes = all
        }
        return p
    }

    /// New entries win; old ones that Claude did not mention are kept.
    private static func merged<T>(old: [T], new: [T], key: (T) -> String) -> [T] {
        let newKeys = Set(new.map { TitleMatcher.normalize(key($0)) })
        return new + old.filter { !newKeys.contains(TitleMatcher.normalize(key($0))) }
    }

    private static func encode(_ p: SeriesProfile) -> String {
        let dict: [String: Any] = [
            "title": p.title, "aliases": p.aliases, "kind": p.kind.rawValue, "year": p.year,
            "target_language": p.targetLanguage,
            "synopsis": p.synopsis, "style_guide": p.styleGuide,
            "characters": p.characters.map { ["name": $0.name, "description": $0.description, "speech": $0.speech] },
            "glossary": p.glossary.map { ["source": $0.source, "target": $0.target, "note": $0.note] },
            "notes": p.notes,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
