import Foundation

/// Bygger systemprompten: grundstil (från skriptet) + verksprofil +
/// användarens beslut + svarsformat.
enum PromptBuilder {
    /// Generisk stilguide – samma som DEFAULT_STYLE i translate-srt.mjs.
    /// {MAX_LINE_LEN} och {MAX_CPS} ersätts med värdena från Inställningar.
    static let defaultStyle = """
    Du är en erfaren undertextöversättare som översätter till svenska. Du hanterar
    alla genrer – drama, komedi, action, dokumentär, science fiction – och
    anpassar tonen efter det du ser i replikerna.

    TON OCH STIL
    - Skriv naturlig, talad svenska. Undertexter ska låta som människor som pratar,
      inte som skriftspråk.
    - Du-tilltal som grundregel, om inte sammanhanget tydligt kräver ni/Ni
      (t.ex. formellt eller historiskt tilltal).
    - Matcha originalets register: ledigt förblir ledigt, formellt förblir
      formellt, slang återges med naturlig svensk slang snarare än ordagrant.
    - Bevara humor, ironi och känsloläge. Översätt skämt så att poängen landar på
      svenska – hellre en fungerande motsvarighet än en ordagrann som faller platt.
    - Håll varje karaktärs röst konsekvent genom hela materialet.

    NAMN OCH BEGREPP
    - Behåll egennamn (personer, platser, organisationer, varumärken) oöversatta,
      om det inte finns en etablerad svensk form.
    - Böj namn med svensk genitiv (Annas, Davids, Sarahs).
    - Facktermer och egennamn på fiktiva begrepp behålls konsekvent – översätt inte
      samma term på två olika sätt.
    - Måttenheter, valutor och liknande behålls som i originalet om inget annat
      krävs för begripligheten.

    ÖVERSÄTTNINGSREGLER (undertextteknik)
    - Översätt ENBART repliktexten. Lägg aldrig till kommentarer eller förklaringar.
    - Max 2 rader per replik. Sikta på max {MAX_LINE_LEN} tecken per rad och högst
      {MAX_CPS} tecken/sekund. Blir en replik för lång: förtäta och korta utan att
      tappa innebörd eller ton.
    - Översätt inte fyllnadsord och tvekljud ordagrant (eh, um, well) – utelämna
      eller återge naturligt när de inte tillför något.
    - Behåll markup som <i>...</i> oförändrad.
    - Behåll utrop, frågetecken och tankstreck som hör till talrytmen.
    """

    static let responseFormat = """
    SVARSFORMAT
    Svara ENBART med ett JSON-objekt – ingen annan text, inga ```-staket:
    {
      "translations": [{"id": <samma id>, "sv": "<svensk text>"}],
      "questions": [
        {"cue_ids": [<id>], "question": "<kort fråga på svenska>",
         "options": ["<alternativ 1>", "<alternativ 2>"], "suggested": "<det alternativ du valde>"}
      ],
      "profile_updates": {
        "characters": [{"name": "<namn>", "description": "<vem personen är>", "speech": "<hur hen talar/tilltalas>"}],
        "glossary": [{"source": "<engelska>", "target": "<vald svensk översättning>", "note": "<kort förklaring>"}],
        "notes": ["<annan viktig iakttagelse för kommande avsnitt>"]
      }
    }

    FRÅGOR TILL ANVÄNDAREN
    - Översätt ALLTID varje replik med ditt bästa förslag, även när du ställer en fråga.
    - Ställ en fråga bara när du är genuint osäker och valet faktiskt påverkar
      översättningen, t.ex.: du eller ni mellan två bestämda personer, talarens
      eller tilltalades kön när svenskan kräver det, en tvetydig ordlek, ett
      återkommande begrepp utan etablerad översättning, eller oklart vem/vad som avses.
    - Högst 2 frågor per anrop. Fråga aldrig om sådant som redan avgörs av
      verksprofilen eller av användarens beslut ovan.
    - Ge alltid 2–4 konkreta alternativ och ange i "suggested" det du valde.

    NY INFORMATION TILL VERKSPROFILEN
    - Lägg i "profile_updates" endast sådant som INTE redan står i verksprofilen
      och som är värdefullt för kommande avsnitt: nya namngivna karaktärer,
      återkommande termer/namn med vald svensk översättning, viktiga relationer
      eller tilltalsregler.
    - Lämna listorna tomma om inget nytt dök upp. Hitta aldrig på.
    """

    static func baseStyle(_ settings: AppSettings) -> String {
        settings.baseStyle
            .replacingOccurrences(of: "{MAX_LINE_LEN}", with: "\(settings.maxLineLength)")
            .replacingOccurrences(of: "{MAX_CPS}", with: String(format: "%g", settings.maxCPS))
    }

    /// Profilens del av prompten (används även i förhandsvisningen).
    static func profileSection(_ p: SeriesProfile) -> String {
        var out: [String] = []
        var head = "VERKET: \(p.title) (\(p.kind.label.lowercased())"
        if !p.year.isEmpty { head += ", \(p.year)" }
        head += ")"
        out.append(head)
        if !p.synopsis.isEmpty { out.append("Om verket: \(p.synopsis)") }

        if !p.styleGuide.isEmpty {
            out.append("\nSÄRSKILD STILGUIDE FÖR DETTA VERK (går före grundstilen vid konflikt)\n\(p.styleGuide)")
        }
        if !p.characters.isEmpty {
            let lines = p.characters.map { c -> String in
                var l = "- \(c.name)"
                if !c.description.isEmpty { l += ": \(c.description)" }
                if !c.speech.isEmpty { l += " Talar/tilltalas: \(c.speech)" }
                return l
            }
            out.append("\nKARAKTÄRER\n" + lines.joined(separator: "\n"))
        }
        if !p.glossary.isEmpty {
            let lines = p.glossary.map { g -> String in
                var l = "- \(g.source) → \(g.target)"
                if !g.note.isEmpty { l += " (\(g.note))" }
                return l
            }
            out.append("\nORDLISTA (använd alltid dessa översättningar)\n" + lines.joined(separator: "\n"))
        }
        if !p.notes.isEmpty {
            out.append("\nÖVRIGA ANTECKNINGAR OCH TIDIGARE BESLUT\n" + p.notes.map { "- \($0)" }.joined(separator: "\n"))
        }
        return out.joined(separator: "\n")
    }

    static func systemPrompt(profile: SeriesProfile?, clarifications: [Clarification], settings: AppSettings) -> String {
        var parts = [baseStyle(settings)]
        if let profile {
            parts.append("=== VERKSPROFIL ===\n" + profileSection(profile))
        }
        if !clarifications.isEmpty {
            let lines = clarifications.map { "- Fråga: \($0.question)\n  Beslut: \($0.answer)" }
            parts.append("=== ANVÄNDARENS BESLUT UNDER DENNA ÖVERSÄTTNING (följ dessa) ===\n" + lines.joined(separator: "\n"))
        }
        parts.append(responseFormat)
        return parts.joined(separator: "\n\n")
    }
}
