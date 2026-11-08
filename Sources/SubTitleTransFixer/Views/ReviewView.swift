import SwiftUI

/// Review a subtitle file: technical checks and a language review with Claude.
struct ReviewView: View {
    @Environment(AppModel.self) private var model
    @State private var severityFilter: IssueSeverity?
    @State private var categoryFilter: IssueCategory?
    @State private var showAllCues = false
    @State private var search = ""

    private var review: ReviewSession { model.review }

    var body: some View {
        VStack(spacing: 0) {
            if review.hasFile {
                ReviewHeader()
                Divider()
                ReviewActionBar(acceptCount: review.applicableCount(where: matchesFilter),
                                acceptAll: { _ = review.applyAll(where: matchesFilter) })
                Divider()
                filterBar
                Divider()
                cueList
            } else {
                emptyState
            }
            Divider()
            statusBar
        }
        .fileDrop(.review)
        .toolbar { toolbar }
        .navigationTitle(review.hasFile ? review.fileName : L("Review"))
        .navigationSubtitle(review.hasFile ? L("Reviewing {0}", review.language.inlineName) : "")
        .sheet(item: previewBinding) { item in
            MediaPreviewSheet(seq: item.id)
        }
        .alert(L("Something went wrong"), isPresented: errorBinding) {
            Button(L("OK")) { review.errorMessage = nil }
        } message: {
            Text(review.errorMessage ?? "")
        }
    }

    // MARK: Helpers

    private struct PreviewItem: Identifiable { let id: Int }

    private var previewBinding: Binding<PreviewItem?> {
        let review = self.review
        return Binding(get: { review.previewSeq.map(PreviewItem.init) }, set: { review.previewSeq = $0?.id })
    }

    private var errorBinding: Binding<Bool> {
        let review = self.review
        return Binding(get: { review.errorMessage != nil }, set: { if !$0 { review.errorMessage = nil } })
    }

    private func filtered(_ all: [ReviewIssue]) -> [ReviewIssue] {
        all.filter(matchesFilter)
    }

    /// The issues shown with the current severity and category filter.
    private func matchesFilter(_ issue: ReviewIssue) -> Bool {
        (severityFilter == nil || issue.severity == severityFilter)
            && (categoryFilter == nil || issue.category == categoryFilter)
    }

    // MARK: Parts

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { review.openPanel() } label: { Label(L("Open"), systemImage: "folder") }
                .help(L("Open an .srt file to review"))
        }
    }

    private var filterBar: some View {
        let all = review.issues
        let counts = Dictionary(grouping: all, by: \.category).mapValues(\.count)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Picker("", selection: $severityFilter) {
                    Text(verbatim: "\(L("All")) (\(all.count))").tag(IssueSeverity?.none)
                    ForEach(IssueSeverity.allCases.reversed()) { s in
                        Text(verbatim: "\(s.label) (\(all.filter { $0.severity == s }.count))").tag(Optional(s))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 420)

                TextField(L("Search"), text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                Spacer()
                if review.hasSource {
                    Toggle(L("Show original"), isOn: Binding(get: { review.showSource }, set: { review.showSource = $0 }))
                        .toggleStyle(.checkbox)
                }
                Toggle(L("Show all subtitles"), isOn: $showAllCues)
                    .toggleStyle(.checkbox)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(IssueCategory.allCases.filter { counts[$0] != nil }) { cat in
                        CategoryChip(category: cat, count: counts[cat] ?? 0, selected: categoryFilter == cat) {
                            categoryFilter = categoryFilter == cat ? nil : cat
                        }
                    }
                    if counts.isEmpty {
                        Label(L("No issues"), systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var cueList: some View {
        let issues = filtered(review.issues)
        let bySeq = Dictionary(grouping: issues, by: \.cueSeq)
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let visible = review.cues.filter { cue in
            guard showAllCues || bySeq[cue.seq] != nil else { return false }
            return q.isEmpty || cue.text.lowercased().contains(q)
        }
        return List {
            // Identified by seq, so rows stay correct when subtitles are removed or sorted.
            ForEach(visible, id: \.seq) { cue in
                ReviewCueRow(cue: cue, issues: bySeq[cue.seq] ?? [])
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .overlay {
            if visible.isEmpty && !review.cues.isEmpty {
                ContentUnavailableView(L("Nothing to show"), systemImage: "checkmark.seal",
                                       description: Text(review.claudeDone || !issues.isEmpty
                                                         ? L("No issues match the filter.")
                                                         : L("No technical issues. Click “Review language” to let Claude check spelling and grammar.")))
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(L("Review a subtitle file"), systemImage: "checkmark.seal")
        } description: {
            Text(L("Drop an .srt file here. Technical errors (timecodes, line length, spaces, punctuation …) are found right away, and Claude can review spelling, grammar and punctuation in any language – following the same prompts as the translation."))
        } actions: {
            Button(L("Open subtitles…")) { review.openPanel() }
                .buttonStyle(.borderedProminent)
            if model.session.translatedCount > 0 {
                Button(L("Review current translation")) { review.load(translation: model.session) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if review.isReviewing {
                ProgressView(value: review.progress).frame(width: 180)
            }
            Text(review.statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if review.changedCount > 0 {
                Text(L("{0} changed subtitles", review.changedCount))
                    .font(.callout)
                    .foregroundStyle(.purple)
            }
            if review.hasUnsavedChanges {
                Label(L("Not saved"), systemImage: "circle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .help(L("The changes are only in the app until you save."))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

// MARK: - Header with language and profile

private struct ReviewHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            mainRow
            SourceRow()
            MediaRow()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var mainRow: some View {
        let review = model.review
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(review.fileName).font(.title3.weight(.semibold)).lineLimit(1)
                Text(L("{0} subtitles", review.cues.count)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "globe").foregroundStyle(.secondary)
            Picker(L("Language"), selection: Binding(
                get: { review.language.code },
                set: { review.languageCode = $0; review.recheck() }
            )) {
                ForEach(Language.all) { lang in Text(lang.menuName).tag(lang.code) }
            }
            .frame(width: 220)
            if let d = review.detection {
                Text(L("Detected: {0}", d.language.displayName))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(d.summary)
            }
            Picker(L("Prompt"), selection: Binding(
                get: { review.profileID },
                set: { review.profileID = $0 }
            )) {
                Text(L("No prompt")).tag(UUID?.none)
                Divider()
                ForEach(model.library.sorted) { p in Text(p.title).tag(Optional(p.id)) }
            }
            .frame(width: 220)
            .help(L("Claude reviews against the same style guide, rules and glossary as when translating"))
        }
    }
}

/// Start Claude's review, accept everything, undo/redo, revert and save.
private struct ReviewActionBar: View {
    @Environment(AppModel.self) private var model
    let acceptCount: Int
    let acceptAll: () -> Void
    @State private var confirmRevert = false

    var body: some View {
        let review = model.review
        HStack(spacing: 10) {
            if review.isReviewing {
                Button(role: .destructive) { review.stop() } label: {
                    Label(L("Stop the review"), systemImage: "stop.fill")
                }
                ProgressView(value: review.progress).frame(width: 140)
            } else {
                Button { review.startClaudeReview() } label: {
                    Label(review.hasSource ? L("Review and compare with Claude") : L("Review language with Claude"),
                          systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .help(review.hasSource
                      ? L("Let Claude review the language and compare the translation with the original")
                      : L("Let Claude review spelling, grammar, punctuation and wording"))
            }

            Button { acceptAll() } label: {
                Label(L("Accept all suggestions ({0})", acceptCount), systemImage: "checkmark.circle")
            }
            .disabled(acceptCount == 0)
            .help(L("Applies every suggestion shown with the current filter – Claude's and the automatic fixes. Undo reverts them."))

            Spacer()

            Button { review.undo() } label: { Label(L("Undo"), systemImage: "arrow.uturn.backward") }
                .disabled(!review.canUndo)
                .help(L("Undo the last change"))
            Button { review.redo() } label: { Label(L("Redo"), systemImage: "arrow.uturn.forward") }
                .disabled(!review.canRedo)
                .help(L("Redo the change"))
            Button(L("Revert all…")) { confirmRevert = true }
                .disabled(!review.hasChangesSinceOpen)
                .help(L("Go back to the file as it was when you opened it"))
            Button(L("Save As…")) { review.saveAs() }
            Button { review.save() } label: { Label(L("Save"), systemImage: "square.and.arrow.down") }
                .help(L("Save to the file you opened (a .bak copy is made the first time)"))
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .confirmationDialog(L("Revert all changes?"), isPresented: $confirmRevert) {
            Button(L("Revert all"), role: .destructive) { review.revertAll() }
        } message: {
            Text(L("The file goes back to how it was when you opened it. Undo can bring the changes back."))
        }
    }
}

/// The original file the translation is compared with.
private struct SourceRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let review = model.review
        HStack(spacing: 8) {
            Image(systemName: "arrow.left.arrow.right")
                .foregroundStyle(review.hasSource ? Color.accentColor : Color.secondary)
            if let name = review.sourceFileName {
                Text(L("Comparing with the original:")).foregroundStyle(.secondary)
                Text(name).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                if let lang = review.sourceLanguage {
                    Text(verbatim: "(\(lang.displayName))").foregroundStyle(.secondary)
                }
                Text("· " + L("{0} of {1} subtitles linked", review.sourceTexts.count, review.cues.count))
                    .foregroundStyle(.secondary)
                if !review.missingSource.isEmpty {
                    Text("· " + L("{0} missing in the translation", review.missingSource.count))
                        .foregroundStyle(.orange)
                }
                Button(L("Change…")) { review.chooseSourcePanel() }.buttonStyle(.link)
                Button(L("Remove")) { review.clearSource() }.buttonStyle(.link)
            } else {
                Text(L("No original file – only the language is reviewed.")).foregroundStyle(.secondary)
                Button(L("Compare with original file…")) { review.chooseSourcePanel() }.buttonStyle(.link)
            }
            Spacer()
        }
        .font(.callout)
    }
}

private struct CategoryChip: View {
    let category: IssueCategory
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("\(category.label) \(count)", systemImage: category.symbol)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(selected ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - A subtitle with its issues

private struct ReviewCueRow: View {
    @Environment(AppModel.self) private var model
    let cue: ReviewCue
    let issues: [ReviewIssue]
    @State private var editingTime = false
    @State private var startDraft = ""
    @State private var endDraft = ""
    @State private var invalidTime = false

    var body: some View {
        let review = model.review
        let seq = cue.seq
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(cue.number).font(.callout.monospacedDigit().weight(.semibold))
                    if editingTime {
                        timeEditor(seq: cue.seq)
                    } else {
                        Button {
                            let parts = cue.timecode.components(separatedBy: "-->")
                            startDraft = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
                            endDraft = parts.count > 1
                                ? String(parts[1].trimmingCharacters(in: .whitespaces).split(separator: " ").first ?? "") : ""
                            invalidTime = false
                            editingTime = true
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(cue.startTime)
                                Text(verbatim: "→ " + cue.endTime)
                            }
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(L("Click to edit the timecode"))
                    }
                    if let cps = cue.cps {
                        Text(verbatim: formatNumber(cps) + " CPS").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 110, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    if review.hasSource && review.showSource {
                        SourceText(text: review.sourceTexts[cue.seq], language: review.sourceLanguage)
                    }
                    TextField("", text: Binding(
                        get: { review.cues.first { $0.seq == seq }?.text ?? cue.text },
                        set: { review.updateText(seq: cue.seq, text: $0) }
                    ), axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if review.media.hasVideo {
                    Button { review.previewSeq = seq } label: {
                        Image(systemName: "play.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(L("Play from 5 seconds before to 5 seconds after and adjust the timing"))
                }
                if cue.isChanged {
                    Button { review.revert(seq: cue.seq) } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(L("Reset to the original:") + "\n" + cue.original)
                }
            }
            ForEach(issues) { issue in
                IssueRow(issue: issue, currentText: cue.text)
                    .padding(.leading, 122)
            }
        }
        .padding(.vertical, 4)
    }

    private func timeEditor(seq: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            TextField("", text: $startDraft).onSubmit { commit(seq) }
            TextField("", text: $endDraft).onSubmit { commit(seq) }
            HStack(spacing: 6) {
                Button { commit(seq) } label: { Image(systemName: "checkmark") }
                    .help(L("Use the new timecode"))
                Button { editingTime = false } label: { Image(systemName: "xmark") }
                    .help(L("Cancel"))
            }
            .buttonStyle(.borderless)
            if invalidTime {
                Text(L("Use the format 00:00:01,000")).font(.caption2).foregroundStyle(.red)
            }
        }
        .font(.caption2.monospacedDigit())
        .textFieldStyle(.roundedBorder)
    }

    private func commit(_ seq: Int) {
        if model.review.updateTimecode(seq: seq, start: startDraft, end: endDraft) {
            editingTime = false
        } else {
            invalidTime = true
        }
    }
}

private struct IssueRow: View {
    @Environment(AppModel.self) private var model
    let issue: ReviewIssue
    let currentText: String

    var body: some View {
        let review = model.review
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: issue.severity.symbol)
                .foregroundStyle(issue.severity.color)
                .help(issue.severity.label)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(issue.category.label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                    if issue.origin == .claude {
                        Image(systemName: "sparkles").font(.caption2).foregroundStyle(.purple)
                            .help(L("Found by Claude"))
                    } else if issue.origin == .audio {
                        Image(systemName: "waveform").font(.caption2).foregroundStyle(.teal)
                            .help(L("Suggested by the audio analysis – play the subtitle to check"))
                    }
                    Text(issue.message)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                fixPreview
                if issue.fix == nil {
                    Text(issue.category == .timing || issue.category == .readingSpeed
                         ? (review.media.hasVideo
                            ? L("No automatic fix – press ▶ to play the subtitle and adjust its timing, or click the time on the left.")
                            : L("No automatic fix – click the time on the left to edit the timecode, or edit the text."))
                         : L("No automatic fix – edit the text directly, or ignore the issue."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if issue.fix != nil {
                Button(L("Fix")) { review.apply(issue) }
                    .controlSize(.small)
                    .disabled(!review.canApply(issue))
                    .help(review.canApply(issue) ? L("Use the suggestion") : L("The subtitle has changed since Claude reviewed it"))
            }
            Button(L("Ignore")) { review.ignore(issue) }
                .controlSize(.small)
                .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var fixPreview: some View {
        switch issue.fix {
        case .some(.text(let fixed)):
            let diff = TextDiff.highlight(old: issue.basedOn ?? currentText, new: fixed)
            VStack(alignment: .leading, spacing: 2) {
                Text(diff.old).font(.callout)
                Text(diff.new).font(.callout)
            }
            .padding(6)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            if !model.review.canApply(issue) {
                Text(L("The subtitle has changed since the review.")).font(.caption).foregroundStyle(.secondary)
            }
        case .some(.timecode(let tc)):
            Text(L("New timecode: {0}", tc)).font(.caption.monospaced()).foregroundStyle(.secondary)
        case .some(.deleteCue):
            Text(L("The subtitle will be removed.")).font(.caption).foregroundStyle(.secondary)
        case .some(.sortByTime):
            Text(L("All subtitles will be sorted by start time and renumbered.")).font(.caption).foregroundStyle(.secondary)
        case .some(.renumber):
            Text(L("All subtitles will be renumbered 1, 2, 3 …")).font(.caption).foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }
}

/// The original's text above the subtitle being reviewed.
private struct SourceText: View {
    let text: String?
    let language: Language?

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text((language?.code ?? "orig").uppercased())
                .font(.caption2.weight(.bold).monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
            if let text {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text(L("Nothing in the original is shown at the same time"))
                    .font(.callout.italic())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
