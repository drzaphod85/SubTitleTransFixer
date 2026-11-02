import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("Allmänt", systemImage: "gearshape") }
            StyleSettings()
                .tabItem { Label("Grundstil", systemImage: "text.quote") }
        }
        .frame(width: 620, height: 520)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var keyDraft = ""
    @State private var keySaved = false

    var body: some View {
        @Bindable var s = model.settings
        Form {
            Section("Anthropic API") {
                HStack {
                    SecureField("API-nyckel", text: $keyDraft, prompt: Text("sk-ant-…"))
                    Button("Spara") {
                        s.apiKey = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        keySaved = true
                    }
                    .disabled(keyDraft.isEmpty)
                }
                Text(keySaved ? "✓ Sparad i nyckelringen." : (s.hasAPIKey ? "En nyckel är sparad." : "Ingen nyckel sparad. Skapa en på console.anthropic.com."))
                    .font(.caption).foregroundStyle(.secondary)

                Picker("Modell", selection: $s.model) {
                    ForEach(AppSettings.modelChoices) { m in Text(m.label).tag(m.id) }
                    if !AppSettings.modelChoices.contains(where: { $0.id == s.model }) {
                        Text(s.model).tag(s.model)
                    }
                }
                TextField("Eget modell-id", text: $s.model)
                    .font(.system(.body, design: .monospaced))
                Picker("Ansträngning (effort)", selection: $s.effort) {
                    ForEach(AppSettings.effortChoices) { e in Text(e.label).tag(e.id) }
                }
                Toggle("Reservmodell om en förfrågan avböjs (server-side fallback)", isOn: $s.useFallbacks)
            }

            Section("Översättning") {
                Stepper("Repliker per anrop: \(s.batchSize)", value: $s.batchSize, in: 5...60, step: 5)
                Stepper("Kontext (tidigare repliker): \(s.contextSize)", value: $s.contextSize, in: 0...20)
                Stepper("Max tecken/sekund: \(Int(s.maxCPS))", value: $s.maxCPS, in: 10...30, step: 1)
                Stepper("Max tecken per rad: \(s.maxLineLength)", value: $s.maxLineLength, in: 30...60)
            }

            Section("Frågor och prompter") {
                Picker("När Claude är osäker", selection: $s.questionMode) {
                    ForEach(QuestionMode.allCases) { m in Text(m.label).tag(m) }
                }
                Toggle("Föreslå uppdateringar av prompten (nya karaktärer, termer …)", isOn: $s.suggestProfileUpdates)
                Toggle("Webbsökning när Claude skapar prompter", isOn: $s.webSearchForProfiles)
                HStack {
                    Text("Promptbiblioteket sparas i")
                    Spacer()
                    Button("Visa i Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.library.fileURL])
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct StyleSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var s = model.settings
        VStack(alignment: .leading, spacing: 8) {
            Text("Grundstilen gäller alla översättningar. Verksprofilen läggs ovanpå. {MAX_LINE_LEN} och {MAX_CPS} ersätts med värdena under Allmänt.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $s.baseStyle)
                .font(.system(.body, design: .monospaced))
            HStack {
                Button("Läs in från fil…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.plainText, .text]
                    if panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url, encoding: .utf8) {
                        s.baseStyle = text
                    }
                }
                Spacer()
                Button("Återställ standard") { s.baseStyle = PromptBuilder.defaultStyle }
            }
        }
        .padding(20)
    }
}
