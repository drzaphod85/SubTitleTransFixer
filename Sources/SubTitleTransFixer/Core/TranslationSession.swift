import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// The translation engine. Corresponds to the main flow of translate-srt.mjs, plus
/// questions to the user and suggested updates to the work profile.
@MainActor
@Observable
final class TranslationSession {
    // File
    var fileURL: URL?
    var cues: [Cue] = []
    var titleGuess: TitleGuess?

    // Language
    /// The result of language detection for the loaded file.
    var detection: LanguageDetection?

    // Profile
    var profileID: UUID?
    /// true if the profile was found automatically from the file name
    var profileAutoMatched = false
    /// Prompt for the same work but another target language (if none exists for the right one).
    var otherLanguageMatch: SeriesProfile?

    // Running
    var isRunning = false
    var progress: Double = 0
    var statusText = L("Open or drop an .srt file to begin.")
    var errorMessage: String?

    // Questions & decisions
    var questions: [TranslatorQuestion] = []
    var activeQuestion: TranslatorQuestion?
    var clarifications: [Clarification] = []

    // Suggestions for the profile
    var suggestions: [ProfileSuggestion] = []
    var showSuggestionsSheet = false

    @ObservationIgnored private var questionContinuation: CheckedContinuation<String?, Never>?
    @ObservationIgnored private var runTask: Task<Void, Never>?

    @ObservationIgnored let library: PromptLibrary
    @ObservationIgnored let settings: AppSettings

    init(library: PromptLibrary, settings: AppSettings) {
        self.library = library
        self.settings = settings
    }

    var profile: SeriesProfile? { library.profile(id: profileID) }
    var translatedCount: Int { cues.filter { !$0.translation.isEmpty }.count }
    var openQuestions: [TranslatorQuestion] { questions.filter { !$0.isResolved } }
    var hasFile: Bool { !cues.isEmpty }

    /// The language translated from: chosen in settings, or detected.
    var sourceLanguage: Language {
        Language.find(settings.sourceLanguage) ?? detection?.language ?? .english
    }
    var targetLanguage: Language { settings.target }
    var isAutoSource: Bool { settings.sourceLanguage == Language.auto }

    /// Warning when the file already seems to be in the target language.
    var sameLanguageWarning: Bool {
        hasFile && sourceLanguage == targetLanguage
    }

    // MARK: - File

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.message = L("Choose a subtitle file to translate")
        if panel.runModal() == .OK, let url = panel.url { load(url: url) }
    }

    func load(url: URL) {
        stop()
        do {
            let raw = try SRT.readText(at: url)
            let parsed = SRT.parse(raw)
            guard !parsed.isEmpty else {
                errorMessage = L("No subtitles found in {0}.", url.lastPathComponent)
                return
            }
            fileURL = url
            cues = parsed
            questions = []
            clarifications = []
            suggestions = []
            progress = 0
            errorMessage = nil

            let guess = TitleMatcher.guess(fromFileName: url.lastPathComponent)
            titleGuess = guess
            detection = LanguageDetector.detect(texts: parsed.map(\.original), fileName: url.lastPathComponent)
            profileID = nil
            matchProfile()

            let read = detection.map { L("Read {0} subtitles in {1}.", cues.count, $0.language.inlineName) }
                ?? L("Read {0} subtitles.", cues.count)
            if let p = profile {
                statusText = read + " " + L("Found a saved prompt for “{0}”.", p.title)
            } else {
                statusText = read + " " + L("No saved prompt for “{0}” (into {1}).", guess.title, targetLanguage.inlineName)
            }
        } catch {
            errorMessage = L("Could not read the file: {0}", error.localizedDescription)
        }
    }

    /// Looks up a saved prompt for the work and the chosen target language.
    /// Runs on load and when the target language changes (if the prompt was chosen automatically).
    func matchProfile() {
        guard let guess = titleGuess else { return }
        guard profileID == nil || profileAutoMatched else { return }
        otherLanguageMatch = nil
        if let match = library.bestMatch(for: guess.title, targetLanguage: targetLanguage.code) {
            profileID = match.profile.id
            profileAutoMatched = true
        } else {
            profileID = nil
            profileAutoMatched = false
            otherLanguageMatch = library.bestMatch(for: guess.title)?.profile
        }
    }

    func savePanel() {
        guard hasFile else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.nameFieldStringValue = SRT.outputName(for: fileURL?.lastPathComponent ?? "subtitles.srt",
                                                    source: sourceLanguage, target: targetLanguage)
        panel.directoryURL = fileURL?.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try SRT.serialize(cues).write(to: url, atomically: true, encoding: .utf8)
                statusText = L("✓ Wrote {0} subtitles to {1}.", cues.count, url.lastPathComponent)
            } catch {
                errorMessage = L("Could not save: {0}", error.localizedDescription)
            }
        }
    }

    // MARK: - Running

    func start() {
        guard !isRunning, hasFile else { return }
        runTask = Task { await run() }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        if let c = questionContinuation {
            questionContinuation = nil
            activeQuestion = nil
            c.resume(returning: nil)
        }
    }

    /// Clears all translations (e.g. after changing profile).
    func resetTranslations() {
        stop()
        for i in cues.indices { cues[i].translation = ""; cues[i].status = .pending }
        questions = []
        clarifications = []
        suggestions = []
        progress = 0
    }

    private func run() async {
        isRunning = true
        errorMessage = nil
        defer { isRunning = false }

        let client: AnthropicClient
        do { client = try settings.makeClient() } catch {
            errorMessage = error.localizedDescription
            return
        }

        // Continue where we left off: only subtitles without a (successful) translation
        let pending = cues.indices.filter { cues[$0].translation.isEmpty || cues[$0].status == .failed }
        let size = max(settings.batchSize, 1)
        let batches = stride(from: 0, to: pending.count, by: size).map { Array(pending[$0..<min($0 + size, pending.count)]) }
        var processed = cues.count - pending.count

        for (n, batch) in batches.enumerated() {
            if Task.isCancelled { break }
            statusText = L("Batch {0}/{1} (subtitle {2}…)", n + 1, batches.count, cues[batch[0]].number)
            for i in batch { cues[i].status = .translating }

            do {
                let allowQuestions = settings.questionMode != .off
                var result = try await requestBatch(batch, client: client, allowQuestions: allowQuestions)
                apply(result, to: batch)

                if !result.questions.isEmpty {
                    switch settings.questionMode {
                    case .pause:
                        var answeredAny = false
                        for q in result.questions {
                            if Task.isCancelled { break }
                            if let answer = await ask(q) {
                                record(question: q, answer: answer)
                                answeredAny = true
                            }
                        }
                        if answeredAny && !Task.isCancelled {
                            statusText = L("Translating batch {0} again with your answers…", n + 1)
                            result = try await requestBatch(batch, client: client, allowQuestions: false)
                            apply(result, to: batch)
                        }
                    case .collect:
                        questions.append(contentsOf: result.questions)
                        for q in result.questions { for s in q.cueSeqs { markQuestion(seq: s) } }
                    case .off:
                        break
                    }
                }
            } catch is CancellationError {
                for i in batch where cues[i].status == .translating { cues[i].status = .pending }
                break
            } catch {
                for i in batch where cues[i].status == .translating { cues[i].status = .failed }
                errorMessage = L("Batch {0} failed: {1}", n + 1, error.localizedDescription)
                if (error as? URLError)?.code == .cancelled { break }
            }
            processed += batch.count
            progress = Double(processed) / Double(max(cues.count, 1))
        }

        if Task.isCancelled {
            statusText = L("Stopped. {0}/{1} subtitles translated.", translatedCount, cues.count)
            return
        }
        finish()
    }

    private func finish() {
        progress = 1
        let warned = cues.filter { ($0.translationCPS ?? 0) > settings.maxCPS + 3 }.count
        statusText = warned > 0
            ? L("✓ Done. {0}/{1} subtitles translated – {2} over the CPS target, check them.", translatedCount, cues.count, warned)
            : L("✓ Done. {0}/{1} subtitles translated.", translatedCount, cues.count)

        // Remember the episode in the profile
        if let id = profileID, let i = library.index(of: id) {
            let ep = titleGuess?.episode ?? fileURL?.lastPathComponent ?? ""
            if !ep.isEmpty, !library.profiles[i].translatedEpisodes.contains(ep) {
                library.profiles[i].translatedEpisodes.append(ep)
                library.upsert(library.profiles[i])
            }
        }
        if settings.suggestProfileUpdates && !suggestions.isEmpty {
            showSuggestionsSheet = true
        }
    }

    // MARK: - Questions

    /// Pauses the run and shows the question to the user. nil = skip.
    private func ask(_ q: TranslatorQuestion) async -> String? {
        await withCheckedContinuation { cont in
            questionContinuation = cont
            activeQuestion = q
        }
    }

    /// Called from the question dialog.
    func answerActive(_ answer: String?, saveToProfile: Bool) {
        guard let q = activeQuestion, let cont = questionContinuation else { return }
        var resolved = q
        resolved.answer = answer ?? L("(skipped – Claude's suggestion was kept)")
        questions.append(resolved)
        if let answer, saveToProfile, let id = profileID {
            library.addNote("\(q.question) → \(answer)", to: id)
        }
        activeQuestion = nil
        questionContinuation = nil
        cont.resume(returning: answer)
    }

    /// Answer to a question in the side panel ("collect questions" mode).
    func answer(questionID: UUID, with answer: String, saveToProfile: Bool) {
        guard let qi = questions.firstIndex(where: { $0.id == questionID }) else { return }
        let q = questions[qi]
        questions[qi].answer = answer
        record(question: q, answer: answer)
        if saveToProfile, let id = profileID {
            library.addNote("\(q.question) → \(answer)", to: id)
        }
        retranslate(seqs: q.cueSeqs)
    }

    func dismiss(questionID: UUID) {
        guard let qi = questions.firstIndex(where: { $0.id == questionID }) else { return }
        questions[qi].answer = L("(skipped – Claude's suggestion was kept)")
        for s in questions[qi].cueSeqs { if let i = index(ofSeq: s), cues[i].status == .question { cues[i].status = .done } }
    }

    private func record(question: TranslatorQuestion, answer: String) {
        clarifications.append(Clarification(question: question.question, answer: answer))
    }

    // MARK: - Single subtitles

    func retranslate(seqs: [Int]) {
        let indices = seqs.compactMap { index(ofSeq: $0) }.sorted()
        guard !indices.isEmpty else { return }
        Task {
            do {
                let client = try settings.makeClient()
                for i in indices { cues[i].status = .translating }
                let result = try await requestBatch(indices, client: client, allowQuestions: false)
                apply(result, to: indices)
            } catch {
                for i in indices where cues[i].status == .translating { cues[i].status = .failed }
                errorMessage = L("Could not translate again: {0}", error.localizedDescription)
            }
        }
    }

    func updateTranslation(seq: Int, text: String) {
        guard let i = index(ofSeq: seq) else { return }
        cues[i].translation = text
        cues[i].status = .edited
    }

    private func index(ofSeq seq: Int) -> Int? {
        let i = seq - 1
        return cues.indices.contains(i) && cues[i].seq == seq ? i : cues.firstIndex { $0.seq == seq }
    }

    private func markQuestion(seq: Int) {
        if let i = index(ofSeq: seq) { cues[i].status = .question }
    }

    // MARK: - API request for a batch

    private struct BatchResult {
        var translations: [Int: String] = [:]
        var questions: [TranslatorQuestion] = []
        var suggestions: [ProfileSuggestion] = []
    }

    private func requestBatch(_ indices: [Int], client: AnthropicClient, allowQuestions: Bool) async throws -> BatchResult {
        let source = sourceLanguage, target = targetLanguage
        let system = PromptBuilder.systemPrompt(profile: profile, clarifications: clarifications, settings: settings,
                                                source: source, target: target)
        let srcTag = source.code.uppercased(), dstTag = target.code.uppercased()

        // Sliding context window: previously translated subtitles
        let first = indices.first ?? 0
        let context = cues[..<first].filter { !$0.translation.isEmpty }.suffix(settings.contextSize)
        var user = ""
        if !context.isEmpty {
            user += "EARLIER SUBTITLES (for context, do NOT translate these again):\n"
            user += context.map {
                "\(srcTag): \($0.original.replacingOccurrences(of: "\n", with: " "))\n\(dstTag): \($0.translation.replacingOccurrences(of: "\n", with: " "))"
            }.joined(separator: "\n")
            user += "\n\n"
        }

        let items: [[String: Any]] = indices.map { i in
            let c = cues[i]
            var item: [String: Any] = ["id": c.seq, "text": c.original]
            if let d = c.duration {
                item["seconds"] = (d * 100).rounded() / 100
                item["max_chars"] = Int(d * settings.maxCPS)
            }
            return item
        }
        let itemsJSON = (try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .withoutEscapingSlashes]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        user += "Translate the \"text\" field of every object from \(source.englishName) into \(target.englishName) following the style and rules.\n"
        user += "Keep line breaks (\\n) where they fit. Aim to stay under\n"
        user += "max_chars per subtitle. Reply according to the RESPONSE FORMAT.\n"
        user += allowQuestions
            ? "You may ask questions if you are genuinely unsure.\n"
            : "Ask NO questions in this request – leave \"questions\" empty.\n"
        if !settings.suggestProfileUpdates { user += "Leave \"profile_updates\" empty.\n" }
        user += "\n" + itemsJSON

        let raw = try await client.complete(system: system, user: user)
        let parsed = try JSONExtract.value(from: raw)

        var result = BatchResult()
        let obj = parsed as? [String: Any]
        let translations = (obj?["translations"] as? [[String: Any]]) ?? (parsed as? [[String: Any]]) ?? []
        for t in translations {
            let text = (t["translation"] as? String) ?? (t["text"] as? String) ?? (t["sv"] as? String)
            if let id = JSONExtract.int(t["id"]), let text { result.translations[id] = text }
        }

        let validSeqs = Set(indices.map { cues[$0].seq })
        for q in (obj?["questions"] as? [[String: Any]]) ?? [] {
            let text = JSONExtract.string(q["question"])
            guard !text.isEmpty else { continue }
            var seqs = ((q["cue_ids"] as? [Any]) ?? []).compactMap { JSONExtract.int($0) }.filter { validSeqs.contains($0) }
            if seqs.isEmpty { seqs = [cues[first].seq] }
            let suggested = JSONExtract.string(q["suggested"])
            result.questions.append(TranslatorQuestion(
                cueSeqs: seqs, question: text,
                options: JSONExtract.strings(q["options"]),
                suggested: suggested.isEmpty ? nil : suggested))
        }

        if let updates = obj?["profile_updates"] as? [String: Any] {
            let at = cues[first].seq
            for c in (updates["characters"] as? [[String: Any]]) ?? [] {
                let name = JSONExtract.string(c["name"])
                guard !name.isEmpty else { continue }
                result.suggestions.append(ProfileSuggestion(kind: .character(CharacterNote(
                    name: name, description: JSONExtract.string(c["description"]),
                    speech: JSONExtract.string(c["speech"]))), foundAtCue: at))
            }
            for g in (updates["glossary"] as? [[String: Any]]) ?? [] {
                let source = JSONExtract.string(g["source"])
                guard !source.isEmpty else { continue }
                result.suggestions.append(ProfileSuggestion(kind: .term(GlossaryEntry(
                    source: source, target: JSONExtract.string(g["target"]),
                    note: JSONExtract.string(g["note"]))), foundAtCue: at))
            }
            for n in JSONExtract.strings(updates["notes"]) {
                result.suggestions.append(ProfileSuggestion(kind: .note(n), foundAtCue: at))
            }
        }
        return result
    }

    private func apply(_ result: BatchResult, to indices: [Int]) {
        for i in indices {
            if let sv = result.translations[cues[i].seq] {
                cues[i].translation = sv
                cues[i].status = .done
            } else if cues[i].status == .translating {
                // Missing – keep the original, just like the script does
                print("⚠ missing translation for subtitle \(cues[i].number), keeping the original.")
                cues[i].translation = cues[i].original
                cues[i].status = .failed
            }
        }
        addSuggestions(result.suggestions)
    }

    private func addSuggestions(_ new: [ProfileSuggestion]) {
        var keys = Set(suggestions.map(\.dedupeKey))
        let p = profile
        for s in new where !keys.contains(s.dedupeKey) {
            // Filter out what is already in the profile
            switch s.kind {
            case .character(let c): if p?.hasCharacter(named: c.name) == true { continue }
            case .term(let g): if p?.hasTerm(g.source) == true { continue }
            case .note(let n): if p?.notes.contains(n) == true { continue }
            }
            keys.insert(s.dedupeKey)
            suggestions.append(s)
        }
    }

    // MARK: - Suggestions

    /// Saves accepted suggestions in the current profile – or creates a new profile.
    func applySuggestions() {
        let accepted = suggestions.filter(\.accepted)
        guard !accepted.isEmpty else { suggestions = []; return }
        if let id = profileID {
            library.apply(accepted, to: id)
        } else {
            let p = SeriesProfile(title: titleGuess?.title ?? L("New profile"), targetLanguage: targetLanguage.code)
            library.upsert(p)
            library.apply(accepted, to: p.id)
            profileID = p.id
        }
        suggestions = []
    }

    /// A selection of lines from the original – material for Claude when creating a profile.
    func sampleLines(limit: Int = 150) -> [String] {
        guard !cues.isEmpty else { return [] }
        let step = max(cues.count / limit, 1)
        return stride(from: 0, to: cues.count, by: step).prefix(limit)
            .map { cues[$0].original.replacingOccurrences(of: "\n", with: " ") }
    }
}
