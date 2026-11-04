import AppKit
import SwiftUI

enum CueFilter: String, CaseIterable, Identifiable {
    case all, questions, long, edited, failed
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return L("All")
        case .questions: return L("Questions")
        case .long: return L("Too long")
        case .edited: return L("Edited")
        case .failed: return L("Failed")
        }
    }
}

struct TranslationView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: CueFilter = .all
    @State private var search = ""
    @State private var showInspector = true
    @State private var followProgress = true
    @State private var selectedSeq: Int?
    @State private var showGenerate = false

    private var session: TranslationSession { model.session }

    var body: some View {
        @Bindable var session = model.session
        VStack(spacing: 0) {
            if session.hasFile {
                header
                Divider()
                LanguageBar()
                Divider()
                columnHeader
                Divider()
                cueList
            } else {
                emptyState
            }
            Divider()
            statusBar
        }
        .dropDestination(for: URL.self) { urls, _ in handleDrop(urls) }
        .inspector(isPresented: $showInspector) {
            InspectorView(selectedSeq: $selectedSeq)
                .inspectorColumnWidth(min: 280, ideal: 330, max: 460)
        }
        .toolbar { toolbar }
        .navigationTitle(session.fileURL?.lastPathComponent ?? L("Translate"))
        .navigationSubtitle(session.profile.map { L("Prompt: {0}", $0.title) } ?? L("Base style"))
        .sheet(item: activeQuestionBinding) { q in
            QuestionSheet(question: q)
        }
        .sheet(isPresented: $session.showSuggestionsSheet) {
            SuggestionsSheet()
        }
        .sheet(isPresented: $showGenerate) {
            GenerateProfileSheet(existingID: nil, prefillTitle: session.titleGuess?.title,
                                 reference: session.otherLanguageMatch) { newID in
                session.profileID = newID
                session.profileAutoMatched = false
            }
        }
        .alert(L("Something went wrong"), isPresented: Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )) {
            Button(L("OK")) { session.errorMessage = nil }
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    // MARK: Helpers

    private func handleDrop(_ urls: [URL]) -> Bool {
        let srt: URL? = urls.first { url in url.pathExtension.lowercased() == "srt" }
        guard let url = srt else { return false }
        session.load(url: url)
        return true
    }

    /// Closing the question dialog without an answer counts as "skip".
    private var activeQuestionBinding: Binding<TranslatorQuestion?> {
        let session = self.session
        return Binding<TranslatorQuestion?>(
            get: { session.activeQuestion },
            set: { newValue in
                if newValue == nil && session.activeQuestion != nil {
                    session.answerActive(nil, saveToProfile: false)
                }
            }
        )
    }

    // MARK: Parts

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { session.openPanel() } label: { Label(L("Open"), systemImage: "folder") }
                .help(L("Open an .srt file (⌘O)"))
            if session.isRunning {
                Button { session.stop() } label: { Label(L("Stop"), systemImage: "stop.fill") }
            } else {
                Button { session.start() } label: {
                    Label(session.translatedCount > 0 && session.translatedCount < session.cues.count ? L("Continue") : L("Translate"),
                          systemImage: "play.fill")
                }
                .disabled(!session.hasFile)
                .help(L("Translate into {0} (⌘R)", session.targetLanguage.inlineName))
            }
            Button {
                model.review.load(translation: session)
                model.selection = .review
            } label: { Label(L("Review"), systemImage: "checkmark.seal") }
                .disabled(session.translatedCount == 0)
                .help(L("Review the translation: technical errors, spelling, grammar and punctuation"))
            Button { session.savePanel() } label: { Label(L("Save"), systemImage: "square.and.arrow.down") }
                .disabled(session.translatedCount == 0)
                .help(L("Save the translated .srt (⌘S)"))
            Button { showInspector.toggle() } label: { Label(L("Side panel"), systemImage: "sidebar.right") }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.titleGuess?.title ?? "")
                    .font(.title3.weight(.semibold))
                HStack(spacing: 8) {
                    if let ep = session.titleGuess?.episode {
                        Text(ep).font(.caption.monospaced())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    Text(L("{0} subtitles", session.cues.count))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            profileBanner

            Picker(L("Prompt"), selection: Binding(
                get: { session.profileID },
                set: { session.profileID = $0; session.profileAutoMatched = false }
            )) {
                Text(L("Base style (no profile)")).tag(UUID?.none)
                Divider()
                ForEach(model.library.sorted) { p in
                    Label(p.title, systemImage: p.kind.symbol).tag(Optional(p.id))
                }
            }
            .frame(maxWidth: 280)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var profileBanner: some View {
        if let p = session.profile {
            HStack(spacing: 6) {
                Image(systemName: session.profileAutoMatched ? "checkmark.seal.fill" : "text.badge.checkmark")
                    .foregroundStyle(.green)
                Text(session.profileAutoMatched ? L("Found a saved prompt") : L("Using prompt"))
                    .font(.callout)
                Button(L("Show")) { model.selection = .profile(p.id) }
                    .buttonStyle(.link)
            }
        } else if let other = session.otherLanguageMatch {
            HStack(spacing: 6) {
                Image(systemName: "globe").foregroundStyle(.orange)
                Text(L("The prompt for “{0}” is for {1}", other.title, Language.find(other.targetLanguage)?.inlineName ?? other.targetLanguage))
                    .font(.callout)
                Button(L("Use anyway")) {
                    session.profileID = other.id
                    session.profileAutoMatched = false
                }
                .buttonStyle(.link)
                Button(L("Create for {0}…", session.targetLanguage.inlineName)) { showGenerate = true }
                    .buttonStyle(.link)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(.orange)
                Text(L("No saved prompt")).font(.callout)
                Button(L("Create with Claude…")) { showGenerate = true }
                    .buttonStyle(.link)
            }
        }
    }

    private var columnHeader: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Picker("", selection: $filter) {
                    ForEach(CueFilter.allCases) { f in Text(label(for: f)).tag(f) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 460)

                TextField(L("Search subtitles"), text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)

                Spacer()
                Toggle(L("Follow"), isOn: $followProgress)
                    .toggleStyle(.checkbox)
                    .help(L("Scroll automatically to the subtitle being translated"))
            }
            HStack(spacing: 12) {
                Text("#").frame(width: 92, alignment: .leading)
                Text(L("ORIGINAL ({0})", session.sourceLanguage.displayName.uppercased())).frame(maxWidth: .infinity, alignment: .leading)
                Text(L("TRANSLATION ({0})", session.targetLanguage.displayName.uppercased())).frame(maxWidth: .infinity, alignment: .leading)
                Text("CPS").frame(width: 64, alignment: .trailing)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func label(for f: CueFilter) -> String {
        let n = filtered(f, search: "").count
        return "\(f.label) (\(n))"
    }

    private func filtered(_ f: CueFilter, search: String) -> [Int] {
        let maxCPS = model.settings.maxCPS
        let maxLen = model.settings.maxLineLength
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return session.cues.indices.filter { i in
            let c = session.cues[i]
            let pass: Bool
            switch f {
            case .all: pass = true
            case .questions: pass = c.status == .question
                || session.questions.contains { !$0.isResolved && $0.cueSeqs.contains(c.seq) }
            case .long: pass = (c.translationCPS ?? 0) > maxCPS || c.longestLine(of: c.translation) > maxLen
            case .edited: pass = c.status == .edited
            case .failed: pass = c.status == .failed
            }
            guard pass else { return false }
            if q.isEmpty { return true }
            return c.original.lowercased().contains(q) || c.translation.lowercased().contains(q)
        }
    }

    private var cueList: some View {
        let indices = filtered(filter, search: search)
        return ScrollViewReader { proxy in
            List(selection: $selectedSeq) {
                ForEach(indices, id: \.self) { i in
                    CueRow(index: i)
                        .tag(session.cues[i].seq)
                        .id(session.cues[i].seq)
                        .listRowSeparator(.visible)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .onChange(of: session.progress) {
                guard followProgress else { return }
                if let c = session.cues.first(where: { $0.status == .translating || $0.translation.isEmpty }) {
                    withAnimation { proxy.scrollTo(c.seq, anchor: .center) }
                }
            }
            .onChange(of: session.activeQuestion?.id) {
                if let s = session.activeQuestion?.cueSeqs.first {
                    selectedSeq = s
                    withAnimation { proxy.scrollTo(s, anchor: .center) }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(L("Drop an .srt file here"), systemImage: "captions.bubble")
        } description: {
            Text(L("SubTitle TransFixer translates subtitles between languages with Claude. The original's language is detected automatically.\nThe prompt for the series or film is found automatically if one is saved."))
        } actions: {
            Button(L("Open subtitles…")) { session.openPanel() }
                .buttonStyle(.borderedProminent)
            if !model.settings.hasAPIKey {
                SettingsLink { Text(L("Add API key…")) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if session.isRunning {
                ProgressView(value: session.progress)
                    .frame(width: 180)
            }
            Text(session.statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if !session.openQuestions.isEmpty {
                Label(L("{0} open questions", session.openQuestions.count), systemImage: "questionmark.bubble.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            if !session.suggestions.isEmpty {
                Button {
                    session.showSuggestionsSheet = true
                } label: {
                    Label(L("{0} new details for the prompt", session.suggestions.count), systemImage: "lightbulb.fill")
                }
                .buttonStyle(.link)
                .font(.callout)
            }
            if session.hasFile {
                Text("\(session.translatedCount)/\(session.cues.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

// MARK: - One row: original + translation

struct CueRow: View {
    @Environment(AppModel.self) private var model
    let index: Int

    var body: some View {
        let session = model.session
        let cue = session.cues[index]
        let maxCPS = model.settings.maxCPS
        let hasQuestion = cue.status == .question
            || session.questions.contains { !$0.isResolved && $0.cueSeqs.contains(cue.seq) }
            || session.activeQuestion?.cueSeqs.contains(cue.seq) == true

        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    statusIcon(cue.status, hasQuestion: hasQuestion)
                    Text(cue.number).font(.callout.monospacedDigit().weight(.semibold))
                }
                Text(cue.startTime)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 92, alignment: .leading)

            Text(cue.original)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.primary.opacity(0.85))

            Group {
                if cue.status == .translating && cue.translation.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(L("Translating…")).foregroundStyle(.secondary)
                    }
                } else {
                    TextField("", text: Binding(
                        get: { session.cues[index].translation },
                        set: { session.updateTranslation(seq: cue.seq, text: $0) }
                    ), axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                if let cps = cue.translationCPS {
                    Text(formatNumber(cps))
                        .font(.caption.monospacedDigit().weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(cpsColor(cps, max: maxCPS).opacity(0.18), in: Capsule())
                        .foregroundStyle(cpsColor(cps, max: maxCPS))
                        .help(L("Characters per second (target ≤ {0})", Int(maxCPS)))
                }
                if cue.longestLine(of: cue.translation) > model.settings.maxLineLength {
                    Image(systemName: "text.badge.xmark")
                        .foregroundStyle(.orange)
                        .help(L("A line is longer than {0} characters", model.settings.maxLineLength))
                }
            }
            .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .listRowBackground(hasQuestion ? Color.orange.opacity(0.12) : nil)
        .contextMenu {
            Button(L("Translate again")) { session.retranslate(seqs: [cue.seq]) }
            Button(L("Reset to original")) { session.updateTranslation(seq: cue.seq, text: cue.original) }
            Button(L("Copy original")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cue.original, forType: .string)
            }
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: CueStatus, hasQuestion: Bool) -> some View {
        if hasQuestion {
            Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
        } else {
            switch status {
            case .pending: Image(systemName: "circle").foregroundStyle(.tertiary)
            case .translating: Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.blue)
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .question: Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
            case .edited: Image(systemName: "pencil.circle.fill").foregroundStyle(.purple)
            case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
        }
    }

    private func cpsColor(_ cps: Double, max: Double) -> Color {
        if cps > max + 3 { return .red }
        if cps > max { return .orange }
        return .green
    }
}
