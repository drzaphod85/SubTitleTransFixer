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
        detection = LanguageDetector.detect(texts: new.map(\.text), fileName: name)
        let title = TitleMatcher.guess(fromFileName: name).title
        profileID = library.bestMatch(for: title, targetLanguage: language.code)?.profile.id
        recheck()
        statusText = "Läste \(cues.count) repliker på \(language.name). \(localIssues.count) tekniska anmärkningar."
    }

    // MARK: - Kontroller

    func recheck() {
        let options = SubtitleChecker.Options(maxCPS: settings.maxCPS, maxLineLength: settings.maxLineLength,
                                              language: language)
        localIssues = SubtitleChecker.check(cues, options: options)
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
        let size = 40
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

        Svara ENBART med JSON:
        {"issues": [{"id": <replikens id>, "category": "spelling" | "grammar" |
          "punctuation" | "wording" | "consistency" | "meaning",
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
        let items: [[String: Any]] = indices.map { ["id": cues[$0].seq, "text": cues[$0].text] }
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
