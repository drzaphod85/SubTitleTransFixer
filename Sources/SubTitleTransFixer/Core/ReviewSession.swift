import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// Review of a subtitle file: technical checks locally and a language review
/// (spelling, grammar, punctuation …) with Claude, using the same prompts as translation.
@MainActor
@Observable
final class ReviewSession {
    var fileURL: URL?
    var fileName = ""
    var cues: [ReviewCue] = []
    var detection: LanguageDetection?
    /// The language being reviewed. nil = use the detected one.
    var languageCode: String?
    var profileID: UUID?

    // Original file to compare with
    var sourceFileName: String?
    var sourceLanguage: Language?
    /// Original text per subtitle (seq) in the file being reviewed.
    var sourceTexts: [Int: String] = [:]
    /// Original subtitles that have no counterpart in the translation.
    var missingSource: [(seq: Int, text: String)] = []
    var showSource = true

    var localIssues: [ReviewIssue] = []
    var claudeIssues: [ReviewIssue] = []
    /// Timing suggestions from the audio of the video.
    var audioIssues: [ReviewIssue] = []

    // Video that belongs to the file
    @ObservationIgnored let media = MediaSupport()
    /// The subtitle shown in the playback preview.
    var previewSeq: Int?
    var isCheckingAudio = false
    var ignoredKeys: Set<String> = []

    var isReviewing = false
    var progress: Double = 0
    var statusText = L("Open or drop an .srt file to review it.")
    var errorMessage: String?
    /// Has Claude reviewed the whole file?
    var claudeDone = false

    // Undo/redo and saving
    private struct Snapshot {
        var cues: [ReviewCue]
        var claudeIssues: [ReviewIssue]
        var audioIssues: [ReviewIssue]
        var ignoredKeys: Set<String>
    }

    private var snapshot: Snapshot {
        Snapshot(cues: cues, claudeIssues: claudeIssues, audioIssues: audioIssues, ignoredKeys: ignoredKeys)
    }
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    @ObservationIgnored private var lastTyping: (seq: Int, time: Date)?
    /// The subtitles as they were loaded – used by "Revert all".
    @ObservationIgnored private var initialCues: [ReviewCue] = []
    /// The subtitles as they were last saved (or loaded).
    private var savedCues: [ReviewCue] = []
    /// true when the file was opened from disk (Save then writes back to it).
    private var isFileBacked = false
    /// A backup (.bak) is written the first time a file is overwritten.
    @ObservationIgnored private var backupWritten = false

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
    var hasUnsavedChanges: Bool { hasFile && cues != savedCues }
    /// Anything changed (including removed or sorted subtitles) since the file was opened?
    var hasChangesSinceOpen: Bool { cues != initialCues }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// All active (not ignored) issues, sorted by subtitle.
    var issues: [ReviewIssue] {
        (localIssues + claudeIssues + audioIssues)
            .filter { !ignoredKeys.contains($0.key) }
            .sorted { ($0.cueSeq, -$0.severity.rawValue) < ($1.cueSeq, -$1.severity.rawValue) }
    }

    func issues(for seq: Int) -> [ReviewIssue] {
        issues.filter { $0.cueSeq == seq }
    }

    // MARK: - Loading

    func openPanel() {
        guard confirmDiscardChanges() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.message = L("Choose a subtitle file to review")
        if panel.runModal() == .OK, let url = panel.url { load(url: url, confirmed: true) }
    }

    func load(url: URL, confirmed: Bool = false) {
        guard confirmed || confirmDiscardChanges() else { return }
        stop()
        do {
            let parsed = SRT.parse(try SRT.readText(at: url))
            guard !parsed.isEmpty else {
                errorMessage = L("No subtitles found in {0}.", url.lastPathComponent)
                return
            }
            fileURL = url
            isFileBacked = true
            media.setVideo(MediaLocator.findVideo(for: url))
            setCues(parsed.map { ReviewCue(seq: $0.seq, number: $0.number, timecode: $0.timecode, original: $0.original, text: $0.original,
                                           originalTimecode: $0.timecode) },
                    name: url.lastPathComponent)
            if let original = findOriginal(for: url) {
                loadSource(url: original)
                if hasSource {
                    statusText = L("Read {0} subtitles in {1} and found the original {2} to compare with.", cues.count, language.inlineName, original.lastPathComponent)
                }
            }
        } catch {
            errorMessage = L("Could not read the file: {0}", error.localizedDescription)
        }
    }

    /// Review a translation straight from the translation view.
    func load(translation session: TranslationSession) {
        guard confirmDiscardChanges() else { return }
        stop()
        fileURL = session.fileURL.map {
            $0.deletingLastPathComponent().appendingPathComponent(
                SRT.outputName(for: $0.lastPathComponent, source: session.sourceLanguage, target: session.targetLanguage))
        }
        let cues = session.cues.map { c in
            let t = c.translation.isEmpty ? c.original : c.translation
            return ReviewCue(seq: c.seq, number: c.number, timecode: c.timecode, original: t, text: t,
                             originalTimecode: c.timecode)
        }
        isFileBacked = false
        media.setVideo(session.fileURL.flatMap { MediaLocator.findVideo(for: $0) })
        setCues(cues, name: fileURL?.lastPathComponent ?? L("Translation"))
        languageCode = session.targetLanguage.code
        profileID = session.profileID

        // The original is already linked subtitle by subtitle.
        sourceFileName = session.fileURL?.lastPathComponent ?? L("the original")
        sourceLanguage = session.sourceLanguage
        sourceTexts = Dictionary(uniqueKeysWithValues: session.cues.map { ($0.seq, $0.original) })
        missingSource = []
        recheck()
        statusText = L("Reviewing the translation into {0} and comparing with the original in {1}.", language.inlineName, session.sourceLanguage.inlineName)
    }

    private func setCues(_ new: [ReviewCue], name: String) {
        cues = new
        audioIssues = []
        previewSeq = nil
        initialCues = new
        savedCues = new
        undoStack = []
        redoStack = []
        backupWritten = false
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
        // The same prompt as when translating: preferably one for this language, otherwise one
        // for the same work in another language (the prompt then says to adapt to this language).
        profileID = library.bestMatch(for: title, targetLanguage: language.code)?.profile.id
            ?? library.bestMatch(for: title)?.profile.id
        recheck()
        statusText = L("Read {0} subtitles in {1}. {2} technical issues.", cues.count, language.inlineName, localIssues.count)
    }

    // MARK: - Original file

    func chooseSourcePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.message = L("Choose the original file to compare the translation with")
        panel.directoryURL = fileURL?.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url { loadSource(url: url) }
    }

    func loadSource(url: URL) {
        do {
            let parsed = SRT.parse(try SRT.readText(at: url))
            guard !parsed.isEmpty else {
                errorMessage = L("No subtitles found in {0}.", url.lastPathComponent)
                return
            }
            let detected = LanguageDetector.detect(texts: parsed.map(\.original), fileName: url.lastPathComponent)
            sourceFileName = url.lastPathComponent
            sourceLanguage = detected?.language
            align(source: parsed)
            claudeIssues.removeAll { $0.category == .accuracy }
            recheck()
            var status = L("Comparing with {0} ({1}): {2} of {3} subtitles have a counterpart.",
                           url.lastPathComponent, detected?.language.displayName ?? "?", sourceTexts.count, cues.count)
            if detected?.language == language {
                status += " " + L("Note: the original seems to be in the same language as the file being reviewed.")
            }
            statusText = status
        } catch {
            errorMessage = L("Could not read the original file: {0}", error.localizedDescription)
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

    /// Pairs subtitles by their timecodes, so that it works even when the
    /// original and the translation split subtitles differently.
    private func align(source: [Cue]) {
        typealias Timed = (start: Int, end: Int, text: String)
        let src: [Timed] = source.compactMap { c -> Timed? in
            SRT.times(of: c.timecode).map { (start: $0.start, end: $0.end, text: c.original) }
        }
        let dst: [(seq: Int, start: Int, end: Int)] = cues.compactMap { c -> (seq: Int, start: Int, end: Int)? in
            SRT.times(of: c.timecode).map { (seq: c.seq, start: $0.start, end: $0.end) }
        }

        // Without parsable timecodes: pair in order if the counts match.
        guard src.count == source.count, dst.count == cues.count else {
            if source.count == cues.count {
                sourceTexts = Dictionary(uniqueKeysWithValues: zip(cues, source).map { ($0.seq, $1.original) })
            } else {
                sourceTexts = [:]
                errorMessage = L("The timecodes in the original file cannot be parsed, and the number of subtitles differs.")
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

        // Original subtitles that ended up nowhere – attach them to the nearest subtitle.
        missingSource = src.indices.filter { !used.contains($0) }.compactMap { j -> (seq: Int, text: String)? in
            let s = src[j]
            let visible = SubtitleChecker.stripTags(s.text).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !visible.isEmpty else { return nil }
            let nearest = dst.min { abs($0.start - s.start) < abs($1.start - s.start) }
            return nearest.map { (seq: $0.seq, text: s.text) }
        }
    }

    /// Looks for the original in the same folder: "Show_sv.srt" → "Show_en.srt", "Show.en.srt", "Show.srt" …
    private func findOriginal(for url: URL) -> URL? {
        let dir = url.deletingLastPathComponent()
        let base = SRT.baseName(url.lastPathComponent)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        let candidates = files.filter {
            $0.pathExtension.lowercased() == "srt" && $0.lastPathComponent != url.lastPathComponent
                && SRT.baseName($0.lastPathComponent) == base
                && LanguageDetector.hint(fromFileName: $0.lastPathComponent) != language
        }
        // English first, then files with a language code in the name.
        return candidates.sorted { a, b in
            let la = LanguageDetector.hint(fromFileName: a.lastPathComponent)
            let lb = LanguageDetector.hint(fromFileName: b.lastPathComponent)
            if (la == .english) != (lb == .english) { return la == .english }
            return (la != nil) && (lb == nil)
        }.first
    }

    // MARK: - Video and audio

    func chooseVideoPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = MediaLocator.videoExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.message = L("Choose the video that belongs to the subtitles")
        panel.directoryURL = fileURL?.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            media.setVideo(url)
            audioIssues = []
        }
    }

    func clearVideo() {
        media.setVideo(nil)
        audioIssues = []
        previewSeq = nil
    }

    /// Analyses the audio of the whole video and suggests new times for subtitles
    /// whose start or end seems to be off.
    func checkTimingAgainstAudio() {
        guard media.hasVideo, !isCheckingAudio else { return }
        isCheckingAudio = true
        statusText = L("Analysing the audio … this takes a few seconds per episode.")
        Task {
            defer { isCheckingAudio = false }
            do {
                let envelope = try await media.loadFullEnvelope()
                var found: [ReviewIssue] = []
                let times = cues.map { SRT.times(of: $0.timecode) }
                for (i, cue) in cues.enumerated() {
                    guard let t = times[i] else { continue }
                    let start = Double(t.start) / 1000, end = Double(t.end) / 1000
                    let prevEnd = i > 0 ? times[i - 1].map { Double($0.end) / 1000 } : nil
                    let nextStart = i + 1 < cues.count ? times[i + 1].map { Double($0.start) / 1000 } : nil
                    guard let s = SpeechTiming.suggest(envelope: envelope, envelopeStart: 0, start: start, end: end,
                                                       prevEnd: prevEnd, nextStart: nextStart) else { continue }
                    let dStart = s.start - start, dEnd = s.end - end
                    guard abs(dStart) >= 0.3 || abs(dEnd) >= 0.4 else { continue }
                    let tc = SRT.format(ms: Int(s.start * 1000)) + " --> " + SRT.format(ms: Int(s.end * 1000))
                    found.append(ReviewIssue(cueSeq: cue.seq, category: .timing, severity: .suggestion,
                                             message: L("The audio suggests moving the start {0} s and the end {1} s.",
                                                        signed(dStart), signed(dEnd)),
                                             fix: .timecode(tc), origin: .audio, basedOn: cue.timecode))
                }
                audioIssues = found
                statusText = L("The audio analysis suggests new times for {0} subtitles. Play them to check before you accept.", found.count)
            } catch {
                errorMessage = error.localizedDescription
                statusText = L("The audio could not be analysed.")
            }
        }
    }

    private func signed(_ d: Double) -> String {
        (d >= 0 ? "+" : "−") + formatNumber(abs(d))
    }

    // MARK: - Checks

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

    // MARK: - Editing (every change can be undone)

    private func checkpoint() {
        undoStack.append(snapshot)
        if undoStack.count > 300 { undoStack.removeFirst() }
        redoStack = []
        lastTyping = nil
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        restore(previous)
        statusText = L("Undid the last change.")
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        restore(next)
        statusText = L("Redid the change.")
    }

    private func restore(_ s: Snapshot) {
        cues = s.cues
        claudeIssues = s.claudeIssues
        audioIssues = s.audioIssues
        ignoredKeys = s.ignoredKeys
        lastTyping = nil
        recheck()
    }

    /// Goes back to the file exactly as it was opened.
    func revertAll() {
        guard cues != initialCues else { return }
        checkpoint()
        cues = initialCues
        recheck()
        statusText = L("All changes were reverted. Undo brings them back.")
    }

    func updateText(seq: Int, text: String) {
        guard let i = index(of: seq), cues[i].text != text else { return }
        // Typing in the same subtitle counts as one change, so Undo doesn't go letter by letter.
        if let last = lastTyping, last.seq == seq, Date().timeIntervalSince(last.time) < 2 {
            lastTyping = (seq, Date())
        } else {
            checkpoint()
            lastTyping = (seq, Date())
        }
        cues[i].text = text
        recheck()
    }

    /// Sets a new start and end time. Returns false if a time cannot be parsed.
    @discardableResult
    func updateTimecode(seq: Int, start: String, end: String) -> Bool {
        guard let i = index(of: seq),
              let t = SRT.times(of: "\(start.trimmingCharacters(in: .whitespaces)) --> \(end.trimmingCharacters(in: .whitespaces))")
        else { return false }
        let new = SRT.format(ms: t.start) + " --> " + SRT.format(ms: t.end)
        guard new != cues[i].timecode else { return true }
        checkpoint()
        cues[i].timecode = new
        recheck()
        return true
    }

    func revert(seq: Int) {
        guard let i = index(of: seq), let original = initialCues.first(where: { $0.seq == seq }) else { return }
        checkpoint()
        cues[i].text = original.text
        cues[i].timecode = original.timecode
        recheck()
    }

    func ignore(_ issue: ReviewIssue) {
        checkpoint()
        switch issue.origin {
        case .claude: claudeIssues.removeAll { $0.id == issue.id }
        case .audio: audioIssues.removeAll { $0.id == issue.id }
        case .local: ignoredKeys.insert(issue.key)
        }
    }

    /// Can the suggestion be used? (Claude's suggestions only apply to the text that was reviewed.)
    func canApply(_ issue: ReviewIssue) -> Bool {
        guard issue.fix != nil else { return false }
        guard let based = issue.basedOn else { return true }
        guard let i = index(of: issue.cueSeq) else { return false }
        switch issue.origin {
        case .claude: return cues[i].text == based
        case .audio: return cues[i].timecode == based
        case .local: return true
        }
    }

    func apply(_ issue: ReviewIssue) {
        guard let fix = issue.fix, canApply(issue) else { return }
        checkpoint()
        applyWithoutCheckpoint(issue, fix: fix)
        recheck()
    }

    private func applyWithoutCheckpoint(_ issue: ReviewIssue, fix: IssueFix) {
        perform(fix, seq: issue.cueSeq)
        if issue.origin == .audio { audioIssues.removeAll { $0.id == issue.id } }
        guard issue.origin == .claude else { return }
        claudeIssues.removeAll { $0.id == issue.id }
        // Claude puts all corrections of a subtitle in every "fixed", so other
        // issues on the same subtitle are now done as well.
        if let i = index(of: issue.cueSeq) {
            let now = cues[i].text
            claudeIssues.removeAll { $0.cueSeq == issue.cueSeq && $0.fix == .text(now) }
        }
    }

    private func perform(_ fix: IssueFix, seq: Int) {
        switch fix {
        case .text(let t):
            if let i = index(of: seq) { cues[i].text = t }
        case .timecode(let tc):
            if let i = index(of: seq) { cues[i].timecode = tc }
        case .renumber:
            for i in cues.indices { cues[i].number = String(i + 1) }
        case .sortByTime:
            cues.sort { (SRT.times(of: $0.timecode)?.start ?? Int.max) < (SRT.times(of: $1.timecode)?.start ?? Int.max) }
            for i in cues.indices { cues[i].number = String(i + 1) }
        case .deleteCue:
            cues.removeAll { $0.seq == seq }
            claudeIssues.removeAll { $0.cueSeq == seq }
            audioIssues.removeAll { $0.cueSeq == seq }
        }
    }

    /// Applies every suggestion that matches `filter` – Claude's suggestions and the
    /// automatic technical fixes. One single step for Undo. Returns how many were applied.
    @discardableResult
    func applyAll(where filter: (ReviewIssue) -> Bool) -> Int {
        let candidates = issues.filter { filter($0) && $0.fix != nil && canApply($0) }
        guard !candidates.isEmpty else { return 0 }
        checkpoint()
        var applied = 0
        // Claude's suggestions first: they replace whole subtitles.
        for issue in claudeIssues where !ignoredKeys.contains(issue.key) && filter(issue) && canApply(issue) {
            if let fix = issue.fix, claudeIssues.contains(where: { $0.id == issue.id }) {
                applyWithoutCheckpoint(issue, fix: fix)
                applied += 1
            }
        }
        for issue in audioIssues where filter(issue) && canApply(issue) {
            if let fix = issue.fix {
                applyWithoutCheckpoint(issue, fix: fix)
                applied += 1
            }
        }
        recheck()
        // Then the technical fixes, in several passes since one fix can change the next.
        for _ in 0..<6 {
            var touched = Set<Int>()
            var didSomething = false
            for issue in localIssues where issue.fix != nil && !ignoredKeys.contains(issue.key)
                && filter(issue) && !touched.contains(issue.cueSeq) {
                perform(issue.fix!, seq: issue.cueSeq)
                touched.insert(issue.cueSeq)
                applied += 1
                didSomething = true
                // These change every subtitle – recheck before anything else.
                if issue.fix == .renumber || issue.fix == .sortByTime { break }
            }
            recheck()
            if !didSomething { break }
        }
        statusText = L("Applied {0} suggestions. Undo reverts them.", applied)
        return applied
    }

    /// How many suggestions `applyAll(where:)` would apply.
    func applicableCount(where filter: (ReviewIssue) -> Bool) -> Int {
        issues.filter { filter($0) && $0.fix != nil && canApply($0) }.count
    }

    private func index(of seq: Int) -> Int? {
        let i = seq - 1
        return cues.indices.contains(i) && cues[i].seq == seq ? i : cues.firstIndex { $0.seq == seq }
    }

    // MARK: - Language review with Claude

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
            statusText = L("Claude is reviewing the {0} – part {1} of {2}…", language.inlineName, n + 1, batches.count)
            do {
                let found = try await reviewBatch(batch, client: client)
                claudeIssues += found
            } catch is CancellationError {
                break
            } catch {
                if (error as? URLError)?.code == .cancelled { break }
                errorMessage = L("Part {0} could not be reviewed: {1}", n + 1, error.localizedDescription)
            }
            progress = Double(n + 1) / Double(batches.count)
        }
        if Task.isCancelled {
            statusText = L("The review was stopped. {0} language issues so far.", claudeIssues.count)
        } else {
            claudeDone = true
            statusText = L("✓ Done. Claude found {0} language issues, plus {1} technical ones.", claudeIssues.count, localIssues.count)
        }
    }

    private func reviewBatch(_ indices: [Int], client: AnthropicClient) async throws -> [ReviewIssue] {
        // The same base style, target-language rules and work profile as translation.
        let system = PromptBuilder.reviewPrompt(profile: profile, settings: settings, language: language,
                                                source: hasSource ? (sourceLanguage ?? .english) : nil)

        let first = indices.first ?? 0
        var user = ""
        let context = cues[max(0, first - 3)..<first]
        if !context.isEmpty {
            user += "PRECEDING SUBTITLES (do NOT review, context only):\n"
            user += context.map { $0.text.replacingOccurrences(of: "\n", with: " ") }.joined(separator: "\n") + "\n\n"
        }
        let items: [[String: Any]] = indices.map { i in
            var item: [String: Any] = ["id": cues[i].seq, "text": cues[i].text]
            if hasSource { item["original"] = sourceTexts[cues[i].seq] ?? NSNull() }
            return item
        }
        let json = (try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .withoutEscapingSlashes]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        user += "Review these subtitles:\n" + json

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

    // MARK: - Saving

    /// Saves to the file that was opened (a .bak copy is made the first time),
    /// or asks for a file name when there is none.
    @discardableResult
    func save() -> Bool {
        guard hasFile else { return false }
        guard isFileBacked, let url = fileURL else { return saveAs() }
        let fm = FileManager.default
        if !backupWritten, fm.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("bak")
            try? fm.removeItem(at: backup)
            try? fm.copyItem(at: url, to: backup)
            backupWritten = true
        }
        return write(to: url)
    }

    @discardableResult
    func saveAs() -> Bool {
        guard hasFile else { return false }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? fileName
        panel.directoryURL = fileURL?.deletingLastPathComponent()
        panel.message = L("Save the reviewed subtitles")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        guard write(to: url) else { return false }
        fileURL = url
        fileName = url.lastPathComponent
        isFileBacked = true
        backupWritten = true // the user chose this file; no backup of what was there
        return true
    }

    private func write(to url: URL) -> Bool {
        let out = cues.map { "\($0.number)\n\($0.timecode)\n\($0.text)" }.joined(separator: "\n\n") + "\n"
        do {
            try out.write(to: url, atomically: true, encoding: .utf8)
            savedCues = cues
            statusText = L("✓ Saved {0} subtitles ({1} changed) to {2}.", cues.count, changedCount, url.lastPathComponent)
            return true
        } catch {
            errorMessage = L("Could not save: {0}", error.localizedDescription)
            return false
        }
    }

    /// Asks what to do with unsaved changes. Returns true when it is fine to continue.
    func confirmDiscardChanges() -> Bool {
        guard hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = L("Do you want to save the changes to “{0}”?", fileName)
        alert.informativeText = L("Your changes will be lost if you don't save them.")
        alert.addButton(withTitle: L("Save"))
        alert.addButton(withTitle: L("Cancel"))
        alert.addButton(withTitle: L("Don't Save"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }
}
