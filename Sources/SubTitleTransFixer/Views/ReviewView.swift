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
                filterBar
                Divider()
                cueList
            } else {
                emptyState
            }
            Divider()
            statusBar
        }
        .dropDestination(for: URL.self) { urls, _ in handleDrop(urls) }
        .toolbar { toolbar }
        .navigationTitle(review.hasFile ? review.fileName : L("Review"))
        .navigationSubtitle(review.hasFile ? L("Reviewing {0}", review.language.inlineName) : "")
        .alert(L("Something went wrong"), isPresented: errorBinding) {
            Button(L("OK")) { review.errorMessage = nil }
        } message: {
            Text(review.errorMessage ?? "")
        }
    }

    // MARK: Helpers

    private func handleDrop(_ urls: [URL]) -> Bool {
        let srt: URL? = urls.first { url in url.pathExtension.lowercased() == "srt" }
        guard let url = srt else { return false }
        review.load(url: url)
        return true
    }

    private var errorBinding: Binding<Bool> {
        let review = self.review
        return Binding(get: { review.errorMessage != nil }, set: { if !$0 { review.errorMessage = nil } })
    }

    private func filtered(_ all: [ReviewIssue]) -> [ReviewIssue] {
        all.filter { issue in
            (severityFilter == nil || issue.severity == severityFilter)
                && (categoryFilter == nil || issue.category == categoryFilter)
        }
    }

    // MARK: Parts

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { review.openPanel() } label: { Label(L("Open"), systemImage: "folder") }
                .help(L("Open an .srt file to review"))
            if review.isReviewing {
                Button { review.stop() } label: { Label(L("Stop"), systemImage: "stop.fill") }
            } else {
                Button { review.startClaudeReview() } label: {
                    Label(review.hasSource ? L("Review and compare") : L("Review language"), systemImage: "text.magnifyingglass")
                }
                .disabled(!review.hasFile)
                .help(review.hasSource
                      ? L("Let Claude review the language and compare the translation with the original")
                      : L("Let Claude review spelling, grammar, punctuation and wording"))
            }
            Menu {
                Button(L("All technical fixes ({0})", review.autoFixableLocalCount)) {
                    let n = review.applyAllLocal()
                    review.statusText = L("Fixed {0} technical issues.", n)
                }
                .disabled(review.autoFixableLocalCount == 0)
                Button(L("All of Claude's suggestions ({0})", review.applicableClaudeCount)) {
                    let n = review.applyAllClaude()
                    review.statusText = L("Accepted {0} suggestions from Claude.", n)
                }
                .disabled(review.applicableClaudeCount == 0)
                if let categoryFilter {
                    Divider()
                    Button(L("Everything in the category “{0}”", categoryFilter.label)) {
                        let n = review.applyAllLocal(category: categoryFilter) + review.applyAllClaude(category: categoryFilter)
                        review.statusText = L("Fixed {0} issues in “{1}”.", n, categoryFilter.label)
                    }
                }
            } label: {
                Label(L("Fix all"), systemImage: "wand.and.rays")
            }
            .disabled(!review.hasFile)
            Button { review.savePanel() } label: { Label(L("Save"), systemImage: "square.and.arrow.down") }
                .disabled(!review.hasFile)
                .help(L("Save the reviewed file"))
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
        let visible = review.cues.indices.filter { i in
            let cue = review.cues[i]
            guard showAllCues || bySeq[cue.seq] != nil else { return false }
            return q.isEmpty || cue.text.lowercased().contains(q)
        }
        return List {
            ForEach(visible, id: \.self) { i in
                ReviewCueRow(index: i, issues: bySeq[review.cues[i].seq] ?? [])
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
    let index: Int
    let issues: [ReviewIssue]

    var body: some View {
        let review = model.review
        let cue = review.cues[index]
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(cue.number).font(.callout.monospacedDigit().weight(.semibold))
                    Text(cue.startTime).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    if let cps = cue.cps {
                        Text(verbatim: formatNumber(cps) + " CPS").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 92, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    if review.hasSource && review.showSource {
                        SourceText(text: review.sourceTexts[cue.seq], language: review.sourceLanguage)
                    }
                    TextField("", text: Binding(
                        get: { review.cues[index].text },
                        set: { review.updateText(seq: cue.seq, text: $0) }
                    ), axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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
                    .padding(.leading, 104)
            }
        }
        .padding(.vertical, 4)
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
                    }
                    Text(issue.message)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                fixPreview
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
