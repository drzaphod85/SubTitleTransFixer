import Foundation

/// Låter Claude skapa (eller förbättra) en översättningsprofil för ett visst verk.
enum ProfileGenerator {
    struct Request {
        var title: String
        var kind: MediaKind
        var year: String
        var extraInfo: String
        /// Ett urval engelska repliker ur den inlästa filen (för att förankra tonen).
        var sampleLines: [String]
        var webSearch: Bool
        /// Befintlig profil som ska förbättras/kompletteras (nil = skapa ny).
        var existing: SeriesProfile?
    }

    static let system = """
    Du är en mycket erfaren svensk undertextöversättare och redaktör, med bred
    kunskap om film och TV. Din uppgift är att skriva en VERKSPROFIL som en annan
    översättare (en AI) får som instruktion när den översätter undertexter till
    ett specifikt verk från engelska till svenska. Profilen läggs ovanpå en
    generell stilguide för undertextning, så upprepa inte allmänna regler om
    radlängd, CPS eller markup – fokusera på det som är speciellt för just detta verk.

    En bra profil innehåller:
    - synopsis: 2–4 meningar om miljö, tidsperiod, genre och ton.
    - style_guide: konkreta, verksspecifika instruktioner på svenska, t.ex.
      tidsenlig ton (undvik anakronistiska ord), när du/ni ska användas och mellan
      vilka, hur dialekter och sociala skillnader återges (naturlig svenska –
      ingen påhittad dialekt), facktermer i verkets värld (t.ex. veterinärmedicin,
      militär, sci-fi-teknik), återkommande uttryck, kraftuttryck och humor.
    - characters: huvudpersoner och viktiga bifigurer med kort beskrivning och hur
      de talar/tilltalar varandra (titlar, förnamn, smeknamn).
    - glossary: återkommande namn, platser, titlar och begrepp med rekommenderad
      svensk översättning (eller "behålls" om de ska stå kvar på engelska).
    - notes: övrigt som är bra att veta, inklusive sådant du är osäker på.

    Var saklig. Om du inte känner till verket säkert, säg det i notes och bygg
    profilen på det du kan se i replikerna i stället för att hitta på.
    Om du har tillgång till webbsökning, använd den för att kontrollera
    rollista, miljö och etablerade svenska namn.

    Svara till sist ENBART med ett JSON-objekt på formen:
    {"title": "...", "aliases": ["..."], "kind": "series" | "film", "year": "...",
     "synopsis": "...", "style_guide": "...",
     "characters": [{"name": "...", "description": "...", "speech": "..."}],
     "glossary": [{"source": "...", "target": "...", "note": "..."}],
     "notes": ["..."]}
    """

    static func generate(_ r: Request, client: AnthropicClient) async throws -> SeriesProfile {
        var user = ""
        if let existing = r.existing {
            user += "Förbättra och komplettera den här befintliga profilen. Behåll allt som "
            user += "användaren har skrivit om det inte är uppenbart fel, och returnera hela "
            user += "den uppdaterade profilen.\n\nBEFINTLIG PROFIL (JSON):\n"
            user += encode(existing) + "\n\n"
        } else {
            user += "Skapa en ny verksprofil.\n\n"
        }
        user += "Titel: \(r.title)\nTyp: \(r.kind.label)\n"
        if !r.year.isEmpty { user += "År: \(r.year)\n" }
        if !r.extraInfo.isEmpty { user += "\nAnvändarens egna önskemål och information:\n\(r.extraInfo)\n" }
        if !r.sampleLines.isEmpty {
            user += "\nUTDRAG UR DE ENGELSKA UNDERTEXTERNA (för ton och namn):\n"
            user += r.sampleLines.joined(separator: "\n")
            user += "\n"
        }

        let raw = try await client.complete(system: system, user: user, maxTokens: 16000, webSearch: r.webSearch)
        guard let obj = try JSONExtract.value(from: raw) as? [String: Any] else {
            throw AnthropicClient.APIError(message: "Claude returnerade ingen profil.")
        }
        return profile(from: obj, base: r.existing, fallbackTitle: r.title, fallbackKind: r.kind)
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
        // Lägg filnamnstiteln som alias om Claude valde ett annat officiellt namn
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

        // Ersätt listorna med Claudes (som vid förbättring redan innehåller de gamla),
        // men behåll id:n för poster som fanns.
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

    /// Nya poster vinner; gamla som Claude inte nämnde behålls.
    private static func merged<T>(old: [T], new: [T], key: (T) -> String) -> [T] {
        let newKeys = Set(new.map { TitleMatcher.normalize(key($0)) })
        return new + old.filter { !newKeys.contains(TitleMatcher.normalize(key($0))) }
    }

    private static func encode(_ p: SeriesProfile) -> String {
        let dict: [String: Any] = [
            "title": p.title, "aliases": p.aliases, "kind": p.kind.rawValue, "year": p.year,
            "synopsis": p.synopsis, "style_guide": p.styleGuide,
            "characters": p.characters.map { ["name": $0.name, "description": $0.description, "speech": $0.speech] },
            "glossary": p.glossary.map { ["source": $0.source, "target": $0.target, "note": $0.note] },
            "notes": p.notes,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
