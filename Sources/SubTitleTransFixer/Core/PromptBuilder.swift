import Foundation

/// Builds the system prompts. Translation and review share the same base
/// style, target-language rules and work profile, so that corrections made
/// in review follow the same rules as the translation.
enum PromptBuilder {
    /// Language-neutral style guide. Placeholders that are replaced:
    /// {SOURCE_LANGUAGE}, {TARGET_LANGUAGE}, {TARGET_RULES}, {MAX_LINE_LEN}, {MAX_CPS}.
    static let defaultStyle = """
    You are an experienced subtitle translator translating from {SOURCE_LANGUAGE}
    into {TARGET_LANGUAGE}. You handle every genre – drama, comedy, action,
    documentary, science fiction – and adapt the tone to what you see in the lines.

    TONE AND STYLE
    - Write natural spoken {TARGET_LANGUAGE}. Subtitles should sound like people
      talking, not like written prose.
    - Match the register of the original: casual stays casual, formal stays formal,
      slang becomes natural {TARGET_LANGUAGE} slang rather than a literal rendering.
    - Keep humour, irony and emotion. Translate jokes so that the point lands in
      {TARGET_LANGUAGE} – a working equivalent beats a literal joke that falls flat.
    - Keep every character's voice consistent throughout.

    NAMES AND TERMS
    - Keep proper names (people, places, organisations, brands) untranslated unless
      there is an established {TARGET_LANGUAGE} form.
    - Keep technical terms and invented terms consistent – never translate the same
      term in two different ways.
    - Keep units of measurement, currencies and the like as in the original unless
      something else is needed for comprehension.

    RULES FOR {TARGET_LANGUAGE}
    {TARGET_RULES}

    SUBTITLING RULES
    - Translate ONLY the dialogue. Never add comments or explanations.
    - At most 2 lines per subtitle. Aim for at most {MAX_LINE_LEN} characters per line
      and at most {MAX_CPS} characters per second. If a subtitle gets too long,
      condense it without losing meaning or tone.
    - Do not translate fillers and hesitations literally (uh, um, well) – leave them
      out or render them naturally when they add nothing.
    - Keep markup such as <i>...</i> unchanged.
    - Keep exclamations, question marks and dashes that belong to the speech rhythm.
    """

    /// Instructions for the translation response. {UI_LANGUAGE} is the language
    /// questions and profile notes are written in.
    static let responseFormat = """
    RESPONSE FORMAT
    Reply ONLY with a JSON object – no other text, no ``` fences:
    {
      "translations": [{"id": <same id>, "translation": "<translated text>"}],
      "questions": [
        {"cue_ids": [<id>], "question": "<short question in {UI_LANGUAGE}>",
         "options": ["<option 1>", "<option 2>"], "suggested": "<the option you chose>"}
      ],
      "profile_updates": {
        "characters": [{"name": "<name>", "description": "<who the person is>", "speech": "<how they speak / are addressed>"}],
        "glossary": [{"source": "<source language term>", "target": "<chosen translation>", "note": "<short explanation>"}],
        "notes": ["<other important observation for future episodes>"]
      }
    }

    QUESTIONS TO THE USER
    - ALWAYS translate every subtitle with your best suggestion, even when you ask a question.
    - Only ask when you are genuinely unsure and the choice actually affects the
      translation, e.g.: formal or informal address between two specific people,
      the gender of the speaker or addressee when the target language requires it,
      an ambiguous pun, a recurring term without an established translation, or
      unclear who or what is meant.
    - At most 2 questions per request. Never ask about anything already decided by
      the work profile or by the user's decisions above.
    - Always give 2–4 concrete options and put the one you chose in "suggested".
    - Write questions and options in {UI_LANGUAGE}.

    NEW INFORMATION FOR THE WORK PROFILE
    - Put in "profile_updates" only things that are NOT already in the work profile
      and that are valuable for future episodes: new named characters, recurring
      terms/names with the chosen translation, important relationships or rules of
      address. Write descriptions in {UI_LANGUAGE}.
    - Leave the lists empty if nothing new came up. Never make anything up.
    """

    static func baseStyle(_ settings: AppSettings, source: Language, target: Language) -> String {
        var rules = target.targetRules.isEmpty ? Language.genericTargetRules : target.targetRules
        rules = rules.trimmingCharacters(in: .whitespacesAndNewlines)
        var style = settings.baseStyle
            .replacingOccurrences(of: "{SOURCE_LANGUAGE}", with: source.englishName)
            .replacingOccurrences(of: "{TARGET_LANGUAGE}", with: target.englishName)
            .replacingOccurrences(of: "{TARGET_RULES}", with: rules)
            .replacingOccurrences(of: "{MAX_LINE_LEN}", with: "\(settings.maxLineLength)")
            .replacingOccurrences(of: "{MAX_CPS}", with: String(format: "%g", settings.maxCPS))
        // A custom base style without language placeholders: still state the languages.
        if !settings.baseStyle.contains("{TARGET_LANGUAGE}") {
            style = "LANGUAGES: Translate from \(source.englishName) into \(target.englishName).\n\(rules)\n\n" + style
        }
        return style
    }

    /// The profile's part of the prompt (also used in the preview).
    static func profileSection(_ p: SeriesProfile) -> String {
        var out: [String] = []
        var head = "THE WORK: \(p.title) (\(p.kind == .series ? "TV series" : "film")"
        if !p.year.isEmpty { head += ", \(p.year)" }
        head += ")"
        out.append(head)
        if !p.synopsis.isEmpty { out.append("About the work: \(p.synopsis)") }

        if !p.styleGuide.isEmpty {
            out.append("\nSTYLE GUIDE FOR THIS WORK (overrides the base style where they conflict)\n\(p.styleGuide)")
        }
        if !p.characters.isEmpty {
            let lines = p.characters.map { c -> String in
                var l = "- \(c.name)"
                if !c.description.isEmpty { l += ": \(c.description)" }
                if !c.speech.isEmpty { l += " Speaks / is addressed: \(c.speech)" }
                return l
            }
            out.append("\nCHARACTERS\n" + lines.joined(separator: "\n"))
        }
        if !p.glossary.isEmpty {
            let lines = p.glossary.map { g -> String in
                var l = "- \(g.source) → \(g.target)"
                if !g.note.isEmpty { l += " (\(g.note))" }
                return l
            }
            out.append("\nGLOSSARY (always use these translations)\n" + lines.joined(separator: "\n"))
        }
        if !p.notes.isEmpty {
            out.append("\nOTHER NOTES AND EARLIER DECISIONS\n" + p.notes.map { "- \($0)" }.joined(separator: "\n"))
        }
        return out.joined(separator: "\n")
    }

    /// Work profile and the user's decisions – shared by translation and review.
    private static func workContext(profile: SeriesProfile?, clarifications: [Clarification], target: Language) -> [String] {
        var parts: [String] = []
        if let profile {
            var section = "=== WORK PROFILE ===\n" + profileSection(profile)
            if profile.targetLanguage != target.code {
                let written = Language.find(profile.targetLanguage)?.englishName ?? profile.targetLanguage
                section += "\n\nNOTE: The profile was written for translation into \(written). Use the facts about "
                section += "the work and its characters, but adapt the glossary and forms of address to \(target.englishName)."
            }
            parts.append(section)
        }
        if !clarifications.isEmpty {
            let lines = clarifications.map { "- Question: \($0.question)\n  Decision: \($0.answer)" }
            parts.append("=== THE USER'S DECISIONS DURING THIS RUN (follow these) ===\n" + lines.joined(separator: "\n"))
        }
        return parts
    }

    /// System prompt for translation.
    static func systemPrompt(profile: SeriesProfile?, clarifications: [Clarification], settings: AppSettings,
                             source: Language, target: Language) -> String {
        var parts = [baseStyle(settings, source: source, target: target)]
        parts += workContext(profile: profile, clarifications: clarifications, target: target)
        parts.append(responseFormat.replacingOccurrences(of: "{UI_LANGUAGE}", with: L10n.languageNameForPrompts))
        return parts.joined(separator: "\n\n")
    }

    /// System prompt for review. Uses the same base style, target-language rules
    /// and work profile as translation, so that corrections follow the rules the
    /// subtitles were (or should have been) written by.
    /// - Parameter source: the original's language when comparing with an original file.
    static func reviewPrompt(profile: SeriesProfile?, settings: AppSettings, language: Language,
                             source: Language?) -> String {
        let ui = L10n.languageNameForPrompts
        var parts: [String] = []
        parts.append("""
        You are a meticulous proofreader and subtitle editor for \(language.englishName). You check
        spelling, grammar, punctuation, wording, comprehensibility and consistency. Subtitles
        are condensed spoken language: short sentences, omitted words and colloquial forms
        are allowed and must NOT be reported. Report only real errors and clear improvements
        – rather too few than too many.

        The subtitles must follow the style guide and work profile below – the same ones that
        are used when translating. Report deviations from them: glossary terms or names
        written differently, forms of address that break the rules, or a tone that does
        not fit the work.
        """)
        parts.append("=== STYLE GUIDE FOR THESE SUBTITLES ===\n"
                     + baseStyle(settings, source: source ?? language, target: language))
        parts += workContext(profile: profile, clarifications: [], target: language)

        var rules = """
        REVIEW RULES
        - For every issue, give the whole subtitle corrected in "fixed". Change only what the
          issue is about. Keep line breaks (\\n), <i> tags and dialogue dashes exactly as they are.
        - Do not report line length, timecodes or reading speed – they are checked separately.
        - Consistency: the same name or term must be spelled the same way throughout the file
          and must match the work profile's glossary.
        - Use "meaning" when a subtitle is incomprehensible or obviously wrong.
        - Write "message" in \(ui), short and concrete (quote the words concerned).
        """
        if let source {
            rules += """


            COMPARISON WITH THE ORIGINAL (\(source.englishName))
            Every subtitle also has the field "original" with the original subtitle (null if
            nothing in the original is shown at the same time). Also check that the
            translation is faithful:
            - mistranslations and wrong meaning → "accuracy"
            - important content that was dropped, or content that was added → "accuracy"
            - names, numbers, negations and who is speaking or being addressed → "accuracy"
            - wrong tone or form of address compared with the original → "wording"
            Normal subtitle condensation (shorter phrasing, dropped fillers, repetitions) is
            NOT an error. Report only when meaning is lost or wrong. Quote the original's
            words in "message" when it helps. "fixed" must contain the whole corrected translation.
            """
        }
        parts.append(rules)

        parts.append("""
        Reply ONLY with JSON:
        {"issues": [{"id": <the subtitle's id>, "category": "spelling" | "grammar" |
          "punctuation" | "wording" | "consistency" | "meaning"\(source != nil ? " | \"accuracy\"" : ""),
          "severity": "error" | "warning" | "suggestion",
          "message": "...", "fixed": "<the whole subtitle corrected>"}]}
        If there are no errors: {"issues": []}
        """)
        return parts.joined(separator: "\n\n")
    }
}
