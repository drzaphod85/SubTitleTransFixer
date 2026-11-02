import AppKit
import SwiftUI

enum CueFilter: String, CaseIterable, Identifiable {
    case all = "Alla"
    case questions = "Frågor"
    case long = "För långa"
    case edited = "Redigerade"
    case failed = "Fel"
    var id: String { rawValue }
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
                columnHeader
                Divider()
                cueList
            } else {
                emptyState
            }
            Divider()
            statusBar
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension.lowercased() == "srt" }) else { return false }
            session.load(url: url)
            return true
        }
        .inspector(isPresented: $showInspector) {
            InspectorView(selectedSeq: $selectedSeq)
                .inspectorColumnWidth(min: 280, ideal: 330, max: 460)
        }
        .toolbar { toolbar }
        .navigationTitle(session.fileURL?.lastPathComponent ?? "Översätt")
        .navigationSubtitle(session.profile.map { "Prompt: \($0.title)" } ?? "Standardstil")
        .sheet(item: Binding(
            get: { session.activeQuestion },
            set: { if $0 == nil && session.activeQuestion != nil { session.answerActive(nil, saveToProfile: false) } }
        )) { q in
            QuestionSheet(question: q)
        }
        .sheet(isPresented: $session.showSuggestionsSheet) {
            SuggestionsSheet()
        }
        .sheet(isPresented: $showGenerate) {
            GenerateProfileSheet(existingID: nil, prefillTitle: session.titleGuess?.title) { newID in
                session.profileID = newID
                session.profileAutoMatched = false
            }
        }
        .alert("Något gick fel", isPresented: Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )) {
            Button("OK") { session.errorMessage = nil }
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    // MARK: Delar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { session.openPanel() } label: { Label("Öppna", systemImage: "folder") }
                .help("Öppna en engelsk .srt-fil (⌘O)")
            if session.isRunning {
                Button { session.stop() } label: { Label("Stoppa", systemImage: "stop.fill") }
            } else {
                Button { session.start() } label: {
                    Label(session.translatedCount > 0 && session.translatedCount < session.cues.count ? "Fortsätt" : "Översätt",
                          systemImage: "play.fill")
                }
                .disabled(!session.hasFile)
                .help("Översätt till svenska (⌘R)")
            }
            Button { session.savePanel() } label: { Label("Spara", systemImage: "square.and.arrow.down") }
                .disabled(session.translatedCount == 0)
                .help("Spara svensk .srt (⌘S)")
            Button { showInspector.toggle() } label: { Label("Sidopanel", systemImage: "sidebar.right") }
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
                    Text("\(session.cues.count) repliker")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            profileBanner

            Picker("Prompt", selection: Binding(
                get: { session.profileID },
                set: { session.profileID = $0; session.profileAutoMatched = false }
            )) {
                Text("Standardstil (ingen profil)").tag(UUID?.none)
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
                Text(session.profileAutoMatched ? "Hittade sparad prompt" : "Använder prompt")
                    .font(.callout)
                Button("Visa") { model.selection = .profile(p.id) }
                    .buttonStyle(.link)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(.orange)
                Text("Ingen sparad prompt").font(.callout)
                Button("Skapa med Claude…") { showGenerate = true }
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

                TextField("Sök i repliker", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)

                Spacer()
                Toggle("Följ med", isOn: $followProgress)
                    .toggleStyle(.checkbox)
                    .help("Rulla automatiskt till repliken som översätts")
            }
            HStack(spacing: 12) {
                Text("#").frame(width: 92, alignment: .leading)
                Text("ORIGINAL (ENGELSKA)").frame(maxWidth: .infinity, alignment: .leading)
                Text("ÖVERSÄTTNING (SVENSKA)").frame(maxWidth: .infinity, alignment: .leading)
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
        return f == .all ? "Alla (\(n))" : "\(f.rawValue) (\(n))"
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
            Label("Släpp en .srt-fil här", systemImage: "captions.bubble")
        } description: {
            Text("Undertextaren översätter engelska undertexter till svenska med Claude.\nPrompten för serien eller filmen hittas automatiskt om den finns sparad.")
        } actions: {
            Button("Öppna undertext…") { session.openPanel() }
                .buttonStyle(.borderedProminent)
            if !model.settings.hasAPIKey {
                SettingsLink { Text("Lägg in API-nyckel…") }
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
                Label("\(session.openQuestions.count) öppna frågor", systemImage: "questionmark.bubble.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            if !session.suggestions.isEmpty {
                Button {
                    session.showSuggestionsSheet = true
                } label: {
                    Label("\(session.suggestions.count) nya uppgifter till prompten", systemImage: "lightbulb.fill")
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

// MARK: - En rad: original + översättning

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
                        Text("Översätter…").foregroundStyle(.secondary)
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
                    Text(String(format: "%.1f", cps))
                        .font(.caption.monospacedDigit().weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(cpsColor(cps, max: maxCPS).opacity(0.18), in: Capsule())
                        .foregroundStyle(cpsColor(cps, max: maxCPS))
                        .help("Tecken per sekund (mål ≤ \(Int(maxCPS)))")
                }
                if cue.longestLine(of: cue.translation) > model.settings.maxLineLength {
                    Image(systemName: "text.badge.xmark")
                        .foregroundStyle(.orange)
                        .help("En rad är längre än \(model.settings.maxLineLength) tecken")
                }
            }
            .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .listRowBackground(hasQuestion ? Color.orange.opacity(0.12) : nil)
        .contextMenu {
            Button("Översätt om") { session.retranslate(seqs: [cue.seq]) }
            Button("Återställ till original") { session.updateTranslation(seq: cue.seq, text: cue.original) }
            Button("Kopiera original") {
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
