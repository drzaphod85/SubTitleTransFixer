import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// Granskning av en undertextfil: tekniska kontroller lokalt och
/// språkgranskning (stavning, grammatik, interpunktion …) med Claude.
@MainActor
@Observable
final class ReviewSession {
    var fileURL: URL?
    var fileName = ""
    var cues: [ReviewCue] = []
    var detection: LanguageDetection?
    /// Språket som granskas. nil = använd det upptäckta.
    var languageCode: String?
    var profileID: UUID?

    // Originalfil att jämföra med
    var sourceFileName: String?
    var sourceLanguage: Language?
    /// Originaltext per replik (seq) i filen som granskas.
    var sourceTexts: [Int: String] = [:]
    /// Originalrepliker som inte motsvaras av någon replik i översättningen.
    var missingSource: [(seq: Int, text: String)] = []
    var showSource = true

    var localIssues: [ReviewIssue] = []
    var claudeIssues: [ReviewIssue] = []
    var ignoredKeys: Set<String> = []

    var isReviewing = false
    var progress: Double = 0
    var statusText = "Öppna eller släpp en .srt-fil för att granska den."
    var errorMessage: String?
    /// Har Claude granskat hela filen?
    var claudeDone = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored let library: PromptLibrary

    init(settings: AppSettings, library: PromptLibrary) {
        self.settings = settings
        self.library = library
    }

    var hasFile: Bool { !cues.isEmpty }
    var hasSource: Bool { sourceFileName != nil }
    var language: Language { Language.find(languageCode) ?? detection?.language ?? .swedish }
    var profile: SeriesProfile? { library.profile(id: profileID) }
    var changedCount: Int { cues.filter(\.isChanged).count }

    /// Alla aktiva (ej ignorerade) anmärkningar, sorterade per replik.
    var issues: [ReviewIssue] {
        (localIssues + claudeIssues)
            .filter { !ignoredKeys.contains($0.key) }
            .sorted { ($0.cueSeq, -$0.severity.rawValue) < ($1.cueSeq, -$1.severity.rawValue) }
    }

    func issues(for seq: Int) -> [ReviewIssue] {
        issues.filter { $0.cueSeq == seq }
    }

    // MARK: - Läsa in

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.message = "Välj en undertextfil att granska"
        if panel.runModal() == .OK, let url = panel.url { load(url: url) }
    }

    func load(url: URL) {
        stop()
        do {
            let parsed = SRT.parse(try SRT.readText(at: url))
            guard !parsed.isEmpty else {
                errorMessage = "Hittade inga repliker i \(url.lastPathComponent)."
                return
            }
            fileURL = url
            setCues(parsed.map { ReviewCue(seq: $0.seq, number: $0.number, timecode: $0.timecode, original: $0.original, text: $0.original) },
                    name: url.lastPathComponent)
            if let original = findOriginal(for: url) {
                loadSource(url: original)
                if hasSource {
                    statusText = "Läste \(cues.count) repliker på \(language.name) och hittade originalet \(original.lastPathComponent) att jämföra med."
                }
            }
        } catch {
            errorMessage = "Kunde inte läsa filen: \(error.localizedDescription)"
        }
    }

    /// Granska en översättning direkt från översättningsvyn.
    func load(translation session: TranslationSession) {
        stop()
        fileURL = session.fileURL.map {
            $0.deletingLastPathComponent().appendingPathComponent(
                SRT.outputName(for: $0.lastPathComponent, source: session.sourceLanguage, target: session.targetLanguage))
        }
        let cues = session.cues.map { c in
            let t = c.translation.isEmpty ? c.original : c.translation
            return ReviewCue(seq: c.seq, number: c.number, timecode: c.timecode, original: t, text: t)
        }
        setCues(cues, name: fileURL?.lastPathComponent ?? "Översättning")
        languageCode = session.targetLanguage.code
        profileID = session.profileID

        // Originalet är redan kopplat replik för replik.
        sourceFileName = session.fileURL?.lastPathComponent ?? "originalet"
        sourceLanguage = session.sourceLanguage
        sourceTexts = Dictionary(uniqueKeysWithValues: session.cues.map { ($0.seq, $0.original) })
        missingSource = []
        recheck()
        statusText = "Granskar översättningen till \(language.name) och jämför med originalet på \(session.sourceLanguage.name)."
    }

    private func setCues(_ new: [ReviewCue], name: String) {
        cues = new
        fileName = name
        claudeIssues = []
        ignoredKeys = []
        claudeDone = false
        progress = 0
        errorMessage = nil
        languageCode = nil
        sourceFileName = nil
        sourceLanguage = nil
        sourceTexts = [:]
        missingSource = []
        detection = LanguageDetector.detect(texts: new.map(\.text), fileName: name)
        let title = TitleMatcher.guess(fromFileName: name).title
        profileID = library.bestMatch(for: title, targetLanguage: language.code)?.profile.id
        recheck()
        statusText = "Läste \(cues.count) repliker på \(language.name). \(localIssues.count) tekniska anmärkningar."
    }

    // MARK: - Originalfil

    func chooseSourcePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.message = "Välj originalfilen som översättningen ska jämföras med"
        panel.directoryURL = fileURL?.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url { loadSource(url: url) }
    }

    func loadSource(url: URL) {
        do {
            let parsed = SRT.parse(try SRT.readText(at: url))
            guard !parsed.isEmpty else {
                errorMessage = "Hittade inga repliker i \(url.lastPathComponent)."
                return
            }
            let detected = LanguageDetector.detect(texts: parsed.map(\.original), fileName: url.lastPathComponent)
            sourceFileName = url.lastPathComponent
            sourceLanguage = detected?.language
            align(source: parsed)
            claudeIssues.removeAll { $0.category == .accuracy }
            recheck()
            var status = "Jämför med \(url.lastPathComponent)"
            if let l = detected?.language { status += " (\(l.name))" }
            status += ": \(sourceTexts.count) av \(cues.count) repliker har en motsvarighet."
            if detected?.language == language {
                status += " OBS: originalet verkar vara på samma språk som filen som granskas."
            }
            statusText = status
        } catch {
            errorMessage = "Kunde inte läsa originalfilen: \(error.localizedDescription)"
        }
    }

    func clearSource() {
        sourceFileName = nil
        sourceLanguage = nil
        sourceTexts = [:]
        missingSource = []
        claudeIssues.removeAll { $0.category == .accuracy }
        recheck()
    }

    /// Parar ihop repliker via tidkoderna, så att det fungerar även när
    /// original och översättning delar upp repliker olika.
    private func align(source: [Cue]) {
        typealias Timed = (start: Int, end: Int, text: String)
        let src: [Timed] = source.compactMap { c -> Timed? in
            SRT.times(of: c.timecode).map { (start: $0.start, end: $0.end, text: c.original) }
        }
        let dst: [(seq: Int, start: Int, end: Int)] = cues.compactMap { c -> (seq: Int, start: Int, end: Int)? in
            SRT.times(of: c.timecode).map { (seq: c.seq, start: $0.start, end: $0.end) }
        }

        // Utan tolkbara tidkoder: para ihop i ordning om antalet stämmer.
        guard src.count == source.count, dst.count == cues.count else {
            if source.count == cues.count {
                sourceTexts = Dictionary(uniqueKeysWithValues: zip(cues, source).map { ($0.seq, $1.original) })
            } else {
                sourceTexts = [:]
                errorMessage = "Tidkoderna i originalfilen går inte att tolka, och antalet repliker skiljer sig."
            }
            missingSource = []
            return
        }

        func overlaps(_ a: (start: Int, end: Int), _ b: (start: Int, end: Int)) -> Bool {
            let overlap = min(a.end, b.end) - max(a.start, b.start)
            let shortest = max(min(a.end - a.start, b.end - b.start), 1)
            return overlap > 0 && (overlap >= 200 || Double(overlap) >= 0.3 * Double(shortest))
        }

        var texts: [Int: [String]] = [:]
        var used = Set<Int>()
        var j0 = 0
        for d in dst {
            while j0 < src.count && src[j0].end <= d.start - 2000 { j0 += 1 }
            var j = j0
            while j < src.count && src[j].start < d.end + 2000 {
                if overlaps((d.start, d.end), (src[j].start, src[j].end)) {
                    texts[d.seq, default: []].append(src[j].text)
                    used.insert(j)
                }
                j += 1
            }
        }
        sourceTexts = texts.mapValues { $0.joined(separator: "\n") }

        // Originalrepliker som inte hamnade någonstans – knyt dem till närmaste replik.
        missingSource = src.indices.filter { !used.contains($0) }.compactMap { j -> (seq: Int, text: String)? in
            let s = src[j]
            let visible = SubtitleChecker.stripTags(s.text).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !visible.isEmpty else { return nil }
            let nearest = dst.min { abs($0.start - s.start) < abs($1.start - s.start) }
            return nearest.map { (seq: $0.seq, text: s.text) }
        }
    }

    /// Letar efter originalet i samma mapp: "Show_sv.srt" → "Show_en.srt", "Show.en.srt", "Show.srt" …
    private func findOriginal(for url: URL) -> URL? {
        let dir = url.deletingLastPathComponent()
        let base = Self.baseName(url.lastPathComponent)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        let candidates = files.filter {
            $0.pathExtension.lowercased() == "srt" && $0.lastPathComponent != url.lastPathComponent
                && Self.baseName($0.lastPathComponent) == base
                && LanguageDetector.hint(fromFileName: $0.lastPathComponent) != language
        }
        // Engelska först, därefter filer med språkkod i namnet.
        return candidates.sorted { a, b in
            let la = LanguageDetector.hint(fromFileName: a.lastPathComponent)
            let lb = LanguageDetector.hint(fromFileName: b.lastPathComponent)
            if (la == .english) != (lb == .english) { return la == .english }
            return (la != nil) && (lb == nil)
        }.first
    }

    /// Filnamn utan ändelse och språkkod, i gemener.
    private static func baseName(_ fileName: String) -> String {
        var base = (fileName as NSString).deletingPathExtension.lowercased()
        let tokens = ["forced", "sdh", "hi", "cc"] + Language.all.flatMap { [$0.code] + $0.aliases }
        var changed = true
        while changed {
            changed = false
            for t in tokens {
                for sep in ["_", ".", "-", " "] where base.hasSuffix(sep + t) {
                    base = String(base.dropLast(t.count + 1))
                    changed = true
                }
            }
        }
        return base
    }

    // MARK: - Kontroller

    func recheck() {
        let options = SubtitleChecker.Options(maxCPS: settings.maxCPS, maxLineLength: settings.maxLineLength,
                                              language: language)
        var found = SubtitleChecker.check(cues, options: options)
        if hasSource {
            found += SubtitleChecker.compare(cues, sources: sourceTexts, missing: missingSource,
                                             sourceLanguage: sourceLanguage ?? .english)
        }
        localIssues = found
    }

    func updateText(seq: Int, text: String) {
        guard let i = index(of: seq) else { return }
        cues[i].text = text
        recheck()
    }

    func revert(seq: Int) {
        guard let i = index(of: seq) else { return }
        cues[i].text = cues[i].original
        recheck()
    }

    func ignore(_ issue: ReviewIssue) {
        if issue.origin == .claude {
            claudeIssues.removeAll { $0.id == issue.id }
        } else {
            ignoredKeys.insert(issue.key)
        }
    }

    /// Kan förslaget användas? (Claudes förslag gäller bara texten som granskades.)
    func canApply(_ issue: ReviewIssue) -> Bool {
        guard issue.fix != nil else { return false }
        if issue.origin == .claude, let based = issue.basedOn, let i = index(of: issue.cueSeq) {
            return cues[i].text == based
        }
        return true
    }

    func apply(_ issue: ReviewIssue) {
        guard let fix = issue.fix, canApply(issue) else { return }
        perform(fix, seq: issue.cueSeq)
        if issue.origin == .claude {
            // Övriga Claude-förslag på samma replik bygger på den gamla texten
            // och visas därefter som inaktuella (se canApply).
            claudeIssues.removeAll { $0.id == issue.id }
        }
        recheck()
    }

    private func perform(_ fix: IssueFix, seq: Int) {
        switch fix {
        case .text(let t):
            if let i = index(of: seq) { cues[i].text = t }
        case .timecode(let tc):
            if let i = index(of: seq) { cues[i].timecode = tc }
        case .renumber:
            for i in cues.indices { cues[i].number = String(cues[i].seq) }
        }
    }

    /// Åtgärdar alla lokala anmärkningar som har en automatisk rättning.
    /// Körs i flera varv eftersom en rättning kan ändra förutsättningarna för nästa.
    func applyAllLocal(category: IssueCategory? = nil) -> Int {
        var applied = 0
        for _ in 0..<6 {
            var touched = Set<Int>()
            var didSomething = false
            for issue in localIssues where issue.fix != nil && !ignoredKeys.contains(issue.key)
                && (category == nil || issue.category == category) && !touched.contains(issue.cueSeq) {
                perform(issue.fix!, seq: issue.cueSeq)
                touched.insert(issue.cueSeq)
                applied += 1
                didSomething = true
            }
            recheck()
            if !didSomething { break }
        }
        return applied
    }

    /// Godtar alla Claudes förslag (ev. bara i en kategori).
    func applyAllClaude(category: IssueCategory? = nil) -> Int {
        var applied = 0
        for issue in claudeIssues where category == nil || issue.category == category {
            if canApply(issue) {
                perform(issue.fix!, seq: issue.cueSeq)
                claudeIssues.removeAll { $0.id == issue.id }
                applied += 1
            }
        }
        recheck()
        return applied
    }

    var autoFixableLocalCount: Int {
        localIssues.filter { $0.fix != nil && !ignoredKeys.contains($0.key) }.count
    }

    var applicableClaudeCount: Int {
        claudeIssues.filter { canApply($0) }.count
    }

    private func index(of seq: Int) -> Int? {
        let i = seq - 1
        return cues.indices.contains(i) && cues[i].seq == seq ? i : cues.firstIndex { $0.seq == seq }
    }

    // MARK: - Språkgranskning med Claude

    func startClaudeReview() {
        guard !isReviewing, hasFile else { return }
        task = Task { await runClaudeReview() }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func runClaudeReview() async {
        isReviewing = true
        errorMessage = nil
        defer { isReviewing = false }
        let client: AnthropicClient
        do { client = try settings.makeClient() } catch {
            errorMessage = error.localizedDescription
            return
        }

        claudeIssues = []
        claudeDone = false
        let size = hasSource ? 30 : 40
        let batches = stride(from: 0, to: cues.count, by: size).map { Array($0..<min($0 + size, cues.count)) }
        for (n, batch) in batches.enumerated() {
            if Task.isCancelled { break }
            statusText = "Claude granskar \(language.name) – del \(n + 1) av \(batches.count)…"
            do {
                let found = try await reviewBatch(batch, client: client)
                claudeIssues += found
            } catch is CancellationError {
                break
            } catch {
                if (error as? URLError)?.code == .cancelled { break }
                errorMessage = "Del \(n + 1) kunde inte granskas: \(error.localizedDescription)"
            }
            progress = Double(n + 1) / Double(batches.count)
        }
        if Task.isCancelled {
            statusText = "Granskningen stoppades. \(claudeIssues.count) språkliga anmärkningar hittills."
        } else {
            claudeDone = true
            statusText = "✓ Klar. Claude hittade \(claudeIssues.count) språkliga anmärkningar, plus \(localIssues.count) tekniska."
        }
    }

    private func reviewBatch(_ indices: [Int], client: AnthropicClient) async throws -> [ReviewIssue] {
        let lang = language
        var system = """
        Du är en noggrann korrekturläsare av undertexter på \(lang.name). Du granskar
        stavning, grammatik, interpunktion, ordval och konsekvens. Undertexter är
        förkortat talspråk: korta meningar, utelämnade ord och talspråkliga former är
        tillåtna och ska INTE rapporteras. Rapportera bara verkliga fel och tydliga
        förbättringar – hellre för få än för många.

        Regler:
        - Ange för varje anmärkning hela repliken rättad i "fixed". Ändra bara det
          som anmärkningen gäller. Behåll radbrytningar (\\n), <i>-taggar och
          dialogstreck exakt som de är.
        - Rapportera inte radlängd, tidkoder eller läshastighet – det kontrolleras separat.
        - Konsekvens: samma namn eller term ska stavas likadant genom hela filen.
        - "meaning" används när repliken är obegriplig eller uppenbart felaktig.
        - Skriv "message" på svenska, kort och konkret (t.ex. "”sina” ska vara ”hans”
          eftersom subjektet är ett annat").

        \(hasSource ? comparisonInstructions : "")
        Svara ENBART med JSON:
        {"issues": [{"id": <replikens id>, "category": "spelling" | "grammar" |
          "punctuation" | "wording" | "consistency" | "meaning" | "accuracy",
          "severity": "error" | "warning" | "suggestion",
          "message": "...", "fixed": "<hela repliken rättad>"}]}
        Finns inga fel: {"issues": []}
        """
        if !lang.targetRules.isEmpty {
            system += "\n\nREGLER FÖR \(lang.name.uppercased())\n\(lang.targetRules)"
        }
        if let profile {
            system += "\n\nVERKSPROFIL (namn och termer ska följa denna)\n" + PromptBuilder.profileSection(profile)
        }

        let first = indices.first ?? 0
        var user = ""
        let context = cues[max(0, first - 3)..<first]
        if !context.isEmpty {
            user += "FÖREGÅENDE REPLIKER (granska INTE, bara sammanhang):\n"
            user += context.map { $0.text.replacingOccurrences(of: "\n", with: " ") }.joined(separator: "\n") + "\n\n"
        }
        let items: [[String: Any]] = indices.map { i in
            var item: [String: Any] = ["id": cues[i].seq, "text": cues[i].text]
            if hasSource { item["original"] = sourceTexts[cues[i].seq] ?? NSNull() }
            return item
        }
        let json = (try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .withoutEscapingSlashes]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        user += "Granska de här replikerna:\n" + json

        let raw = try await client.complete(system: system, user: user)
        let parsed = try JSONExtract.value(from: raw)
        let list = ((parsed as? [String: Any])?["issues"] as? [[String: Any]]) ?? (parsed as? [[String: Any]]) ?? []

        let valid = Dictionary(uniqueKeysWithValues: indices.map { (cues[$0].seq, cues[$0].text) })
        return list.compactMap { item -> ReviewIssue? in
            guard let seq = JSONExtract.int(item["id"]), let current = valid[seq] else { return nil }
            let message = JSONExtract.string(item["message"])
            guard !message.isEmpty else { return nil }
            let fixed = item["fixed"] as? String
            let severity: IssueSeverity
            switch JSONExtract.string(item["severity"]).lowercased() {
            case "error": severity = .error
            case "warning": severity = .warning
            default: severity = .suggestion
            }
            return ReviewIssue(cueSeq: seq,
                               category: IssueCategory.fromClaude(JSONExtract.string(item["category"])),
                               severity: severity,
                               message: message,
                               fix: (fixed?.isEmpty == false && fixed != current) ? .text(fixed!) : nil,
                               origin: .claude,
                               basedOn: current)
        }
    }

    private var comparisonInstructions: String {
        let src = (sourceLanguage ?? .english).name
        return """
        JÄMFÖRELSE MED ORIGINALET (\(src))
        Varje replik har också fältet "original" med originalrepliken (null om inget
        i originalet visas samtidigt). Kontrollera även att översättningen stämmer:
        - felöversättningar och fel betydelse → "accuracy"
        - viktigt innehåll som fallit bort, eller sådant som lagts till → "accuracy"
        - namn, siffror, negationer och vem som talar eller tilltalas → "accuracy"
        - fel ton eller tilltal (t.ex. du/ni) jämfört med originalet → "wording"
        Normal förtätning av undertexter (kortare formuleringar, utelämnade
        fyllnadsord, upprepningar) är INTE fel. Rapportera bara när innebörd går
        förlorad eller blir fel. Citera originalets ord i "message" när det hjälper.
        I "fixed" ska hela den rättade översättningen stå.

        """
    }

    // MARK: - Spara

    func savePanel() {
        guard hasFile else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? fileName
        panel.directoryURL = fileURL?.deletingLastPathComponent()
        panel.message = "Spara den granskade undertexten"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let out = cues.map { "\($0.number)\n\($0.timecode)\n\($0.text)" }.joined(separator: "\n\n") + "\n"
        do {
            try out.write(to: url, atomically: true, encoding: .utf8)
            statusText = "✓ Sparade \(cues.count) repliker (\(changedCount) ändrade) till \(url.lastPathComponent)."
        } catch {
            errorMessage = "Kunde inte spara: \(error.localizedDescription)"
        }
    }
}
