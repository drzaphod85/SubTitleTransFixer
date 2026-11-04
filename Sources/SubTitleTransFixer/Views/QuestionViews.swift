import SwiftUI

/// Shown when Claude is unsure and the run is paused.
struct QuestionSheet: View {
    @Environment(AppModel.self) private var model
    let question: TranslatorQuestion

    @State private var choice: String = ""
    @State private var custom: String = ""
    @State private var saveToProfile = true

    private var answer: String {
        let c = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        return c.isEmpty ? choice : c
    }

    var body: some View {
        let session = model.session
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "questionmark.bubble.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Claude is unsure")).font(.headline)
                    Text(L("The translation is paused until you answer."))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            Text(question.question)
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)

            CueContextList(seqs: question.cueSeqs)

            if !question.options.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(question.options, id: \.self) { opt in
                        Button {
                            choice = opt
                            custom = ""
                        } label: {
                            HStack {
                                Image(systemName: choice == opt && custom.isEmpty ? "largecircle.fill.circle" : "circle")
                                Text(opt).multilineTextAlignment(.leading)
                                if opt == question.suggested {
                                    Text(L("Claude's suggestion"))
                                        .font(.caption)
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(.blue.opacity(0.15), in: Capsule())
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            TextField(L("Or write your own answer / instruction"), text: $custom, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)

            Toggle(isOn: $saveToProfile) {
                Text(session.profile.map { L("Save the decision in the prompt for “{0}”", $0.title) }
                     ?? L("Save the decision (create a prompt first to save it permanently)"))
            }
            .disabled(session.profile == nil)

            HStack {
                Button(L("Stop the translation"), role: .destructive) { session.stop() }
                Spacer()
                Button(L("Skip")) { session.answerActive(nil, saveToProfile: false) }
                    .keyboardShortcut(.cancelAction)
                Button(L("Answer and continue")) {
                    session.answerActive(answer, saveToProfile: saveToProfile && session.profile != nil)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(answer.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 600)
        .interactiveDismissDisabled()
        .onAppear {
            choice = question.suggested ?? question.options.first ?? ""
        }
    }
}

/// Shows the subtitles concerned (original + current translation).
struct CueContextList: View {
    @Environment(AppModel.self) private var model
    let seqs: [Int]

    var body: some View {
        let cues = model.session.cues.filter { seqs.contains($0.seq) }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(cues) { c in
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Subtitle {0} · {1}", c.number, c.startTime))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(c.original)
                    if !c.translation.isEmpty {
                        Text(c.translation).foregroundStyle(.blue)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

/// Side panel: questions, new details and decisions.
struct InspectorView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case questions, suggestions, decisions
        var id: String { rawValue }
        var label: String {
            switch self {
            case .questions: return L("Questions")
            case .suggestions: return L("New")
            case .decisions: return L("Decisions")
            }
        }
    }

    @Environment(AppModel.self) private var model
    @Binding var selectedSeq: Int?
    @State private var tab: Tab = .questions

    var body: some View {
        let session = model.session
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { t in Text(t.label).tag(t) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch tab {
                    case .questions:
                        if session.questions.isEmpty {
                            hint(L("No questions yet. When Claude is unsure – e.g. about formal address, gender or a pun – the question shows up here."))
                        }
                        ForEach(session.questions.reversed()) { q in
                            QuestionCard(question: q, selectedSeq: $selectedSeq)
                        }
                    case .suggestions:
                        if session.suggestions.isEmpty {
                            hint(L("New characters, terms and observations that are not in the prompt are collected here during the translation."))
                        } else {
                            Button(L("Review and save in the prompt…")) { session.showSuggestionsSheet = true }
                                .buttonStyle(.borderedProminent)
                        }
                        ForEach(session.suggestions) { s in SuggestionRow(suggestion: s, compact: true) }
                    case .decisions:
                        if session.clarifications.isEmpty {
                            hint(L("Your answers to Claude's questions apply to the rest of the translation and are shown here."))
                        }
                        ForEach(session.clarifications) { c in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(c.question).font(.callout.weight(.medium))
                                Text("→ \(c.answer)").font(.callout).foregroundStyle(.blue)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Question in the side panel ("collect questions" mode – or already answered).
struct QuestionCard: View {
    @Environment(AppModel.self) private var model
    let question: TranslatorQuestion
    @Binding var selectedSeq: Int?
    @State private var custom = ""
    @State private var saveToProfile = true

    var body: some View {
        let session = model.session
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: question.isResolved ? "checkmark.bubble" : "questionmark.bubble.fill")
                    .foregroundStyle(question.isResolved ? .green : .orange)
                Text(question.question).font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(L("Subtitles: {0}", question.cueSeqs.map(String.init).joined(separator: ", "))) {
                selectedSeq = question.cueSeqs.first
            }
            .buttonStyle(.link)
            .font(.caption)

            if let answer = question.answer {
                Text("→ \(answer)").font(.callout).foregroundStyle(.blue)
            } else {
                ForEach(question.options, id: \.self) { opt in
                    Button {
                        session.answer(questionID: question.id, with: opt, saveToProfile: saveToProfile && session.profile != nil)
                    } label: {
                        HStack {
                            Text(opt).multilineTextAlignment(.leading)
                            if opt == question.suggested { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                HStack {
                    TextField(L("Your own answer"), text: $custom)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(submitCustom)
                    Button(L("Answer"), action: submitCustom).disabled(custom.isEmpty)
                }
                HStack {
                    Toggle(L("Save in the prompt"), isOn: $saveToProfile)
                        .toggleStyle(.checkbox)
                        .disabled(session.profile == nil)
                    Spacer()
                    Button(L("Keep the suggestion")) { session.dismiss(questionID: question.id) }
                        .buttonStyle(.link)
                }
                .font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((question.isResolved ? Color.gray : Color.orange).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func submitCustom() {
        let a = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty else { return }
        let session = model.session
        session.answer(questionID: question.id, with: a, saveToProfile: saveToProfile && session.profile != nil)
        custom = ""
    }
}

// MARK: - Suggestions for the prompt

struct SuggestionRow: View {
    @Environment(AppModel.self) private var model
    let suggestion: ProfileSuggestion
    var compact = false

    var body: some View {
        let session = model.session
        HStack(alignment: .top, spacing: 8) {
            if !compact {
                Toggle("", isOn: Binding(
                    get: { suggestion.accepted },
                    set: { v in
                        if let i = session.suggestions.firstIndex(where: { $0.id == suggestion.id }) {
                            session.suggestions[i].accepted = v
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
            }
            switch suggestion.kind {
            case .character(let c):
                Image(systemName: "person.fill").foregroundStyle(.blue).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).font(.callout.weight(.semibold))
                    if !c.description.isEmpty { Text(c.description).font(.callout) }
                    if !c.speech.isEmpty { Text(L("Speaks: {0}", c.speech)).font(.caption).foregroundStyle(.secondary) }
                }
            case .term(let g):
                Image(systemName: "character.book.closed.fill").foregroundStyle(.purple).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(g.source) → \(g.target)").font(.callout.weight(.semibold))
                    if !g.note.isEmpty { Text(g.note).font(.caption).foregroundStyle(.secondary) }
                }
            case .note(let n):
                Image(systemName: "note.text").foregroundStyle(.orange).frame(width: 18)
                Text(n).font(.callout)
            }
            Spacer(minLength: 0)
            if let at = suggestion.foundAtCue {
                Text("#\(at)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Asks the user whether the prompt should be updated with new information.
struct SuggestionsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let session = model.session
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill").font(.largeTitle).foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("New information was found")).font(.headline)
                    Text(session.profile.map { L("Do you want to update the prompt for “{0}” so that future episodes get even better?", $0.title) }
                         ?? L("There is no saved prompt for “{0}”. Do you want to create one with this information?", session.titleGuess?.title ?? L("the work")))
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            List {
                ForEach(session.suggestions) { s in
                    SuggestionRow(suggestion: s)
                        .padding(.vertical, 2)
                }
            }
            .frame(minHeight: 240)

            HStack {
                Button(L("Select all")) { setAll(true) }
                Button(L("Deselect all")) { setAll(false) }
                Spacer()
                Button(L("Not now")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("Discard")) {
                    session.suggestions = []
                    dismiss()
                }
                Button(session.profile == nil ? L("Create prompt") : L("Update the prompt")) {
                    session.applySuggestions()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!session.suggestions.contains(where: \.accepted))
            }
        }
        .padding(24)
        .frame(width: 640, height: 520)
    }

    private func setAll(_ v: Bool) {
        for i in model.session.suggestions.indices { model.session.suggestions[i].accepted = v }
    }
}
