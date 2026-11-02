import Foundation

/// Låter Claude skapa (eller förbättra) en översättningsprofil för ett visst verk.
enum ProfileGenerator {
    struct Request {
        var title: String
        var kind: MediaKind
        var year: String
        var extraInfo: String
        /// Ett urval repliker ur den inlästa filen (för att förankra tonen).
        var sampleLines: [String]
        var webSearch: Bool
        /// Befintlig profil som ska förbättras/kompletteras (nil = skapa ny).
        var existing: SeriesProfile?
        /// Språket undertexterna är på.
        var source: Language = .english
        /// Språket profilen gäller översättning till.
        var target: Language = .swedish
        /// Profil för samma verk men ett annat målspråk – används som faktaunderlag.
        var reference: SeriesProfile? = nil
    }

    /// {SOURCE} och {TARGET} ersätts med språknamn.
    static let systemTemplate = """
    Du är en mycket erfaren undertextöversättare och redaktör, med bred
    kunskap om film och TV. Din uppgift är att skriva en VERKSPROFIL som en annan
    översättare (en AI) får som instruktion när den översätter undertexter till
    ett specifikt verk från {SOURCE} till {TARGET}. Profilen läggs ovanpå en
    generell stilguide för undertextning, så upprepa inte allmänna regler om
    radlängd, CPS eller markup – fokusera på det som är speciellt för just detta verk.

    En bra profil innehåller:
    - synopsis: 2–4 meningar om miljö, tidsperiod, genre och ton.
    - style_guide: konkreta, verksspecifika instruktioner (skrivna på svenska,
      användarens språk, men med exempel på {TARGET}), t.ex.
      tidsenlig ton (undvik anakronistiska ord), när du/ni ska användas och mellan
      vilka, hur dialekter och sociala skillnader återges (naturlig {TARGET} –
      ingen påhittad dialekt), facktermer i verkets värld (t.ex. veterinärmedicin,
      militär, sci-fi-teknik), återkommande uttryck, kraftuttryck och humor.
    - characters: huvudpersoner och viktiga bifigurer med kort beskrivning och hur
      de talar/tilltalar varandra (titlar, förnamn, smeknamn).
    - glossary: återkommande namn, platser, titlar och begrepp med rekommenderad
      översättning till {TARGET} (eller "behålls" om de ska stå kvar som i originalet).
    - notes: övrigt som är bra att veta, inklusive sådant du är osäker på.

    Var saklig. Om du inte känner till verket säkert, säg det i notes och bygg
    profilen på det du kan se i replikerna i stället för att hitta på.
    Om du har tillgång till webbsökning, använd den för att kontrollera
    rollista, miljö och etablerade namn på {TARGET}.

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
        if let ref = r.reference {
            let refLang = Language.find(ref.targetLanguage)?.name ?? ref.targetLanguage
            user += "Det finns redan en profil för verket för översättning till \(refLang). Använd fakta om "
            user += "verket, miljön och karaktärerna därifrån, men skriv om tilltalsregler, stil och ordlista "
            user += "för \(r.target.name).\n\nPROFIL FÖR \(refLang.uppercased()) (JSON):\n" + encode(ref) + "\n\n"
        }
        user += "Titel: \(r.title)\nTyp: \(r.kind.label)\nFrån: \(r.source.name)\nTill: \(r.target.name)\n"
        if !r.year.isEmpty { user += "År: \(r.year)\n" }
        if !r.extraInfo.isEmpty { user += "\nAnvändarens egna önskemål och information:\n\(r.extraInfo)\n" }
        if !r.sampleLines.isEmpty {
            user += "\nUTDRAG UR UNDERTEXTERNA PÅ \(r.source.name.uppercased()) (för ton och namn):\n"
            user += r.sampleLines.joined(separator: "\n")
            user += "\n"
        }

        let system = systemTemplate
            .replacingOccurrences(of: "{SOURCE}", with: r.source.name)
            .replacingOccurrences(of: "{TARGET}", with: r.target.name)
        let raw = try await client.complete(system: system, user: user, maxTokens: 16000, webSearch: r.webSearch)
        guard let obj = try JSONExtract.value(from: raw) as? [String: Any] else {
            throw AnthropicClient.APIError(message: "Claude returnerade ingen profil.")
        }
        var p = profile(from: obj, base: r.existing, fallbackTitle: r.title, fallbackKind: r.kind)
        if r.existing == nil { p.targetLanguage = r.target.code }
        return p
    }

    static let structureSystem = """
    Du är en erfaren undertextredaktör. Användaren har en befintlig
    översättningsprompt (stilguide) för ett visst verk, skriven för hand. Din
    uppgift är att föra över den till en strukturerad VERKSPROFIL utan att något
    går förlorat.

    Regler:
    - Tappa INGENTING. Varje instruktion, regel, exempel och namn i originalet ska
      finnas kvar någonstans i profilen.
    - Karaktärsbeskrivningar (vem någon är, hur hen talar, tilltal) → characters.
    - Namn, platser, titlar och termer med en angiven översättning (eller
      "behålls") → glossary.
    - Allt övrigt (ton, tidsperiod, du/ni-regler, dialekt, kraftuttryck, exempel,
      tekniska regler) → style_guide, så ordagrant som möjligt. Behåll
      originalets rubriker och punktlistor.
    - Lägg inte till egna regler. Du får skriva synopsis om du känner till verket
      och fylla i year och aliases om du vet dem säkert.
    - Behåll originalets språk (oftast svenska).

    Svara ENBART med ett JSON-objekt på formen:
    {"title": "...", "aliases": ["..."], "kind": "series" | "film", "year": "...",
     "synopsis": "...", "style_guide": "...",
     "characters": [{"name": "...", "description": "...", "speech": "..."}],
     "glossary": [{"source": "...", "target": "...", "note": "..."}],
     "notes": ["..."]}
    """

    /// Gör om en befintlig, handskriven prompt till en strukturerad profil.
    static func structure(text: String, title: String, kind: MediaKind, target: Language,
                          into existing: SeriesProfile?, client: AnthropicClient) async throws -> SeriesProfile {
        var user = "Titel: \(title)\nTyp: \(kind.label)\nPrompten gäller översättning till: \(target.name)\n"
        user += "\nBEFINTLIG PROMPT:\n<<<\n\(text)\n>>>\n"
        if existing != nil {
            user += "\nPrompten ska ersätta stilguiden i en befintlig profil. Befintliga karaktärer "
            user += "och termer finns redan; ta bara med dem i svaret om originalet säger något nytt om dem.\n"
        }
        let raw = try await client.complete(system: structureSystem, user: user, maxTokens: 16000)
        guard let obj = try JSONExtract.value(from: raw) as? [String: Any] else {
            throw AnthropicClient.APIError(message: "Claude returnerade ingen profil.")
        }
        var base = existing
        // Vid uppdatering ska den nya texten ersätta stilguiden helt.
        base?.styleGuide = ""
        var p = profile(from: obj, base: base, fallbackTitle: title, fallbackKind: kind)
        if p.styleGuide.isEmpty { p.styleGuide = text } // säkerhetsnät
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
