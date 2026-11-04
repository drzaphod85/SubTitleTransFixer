import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label(L("General"), systemImage: "gearshape") }
            StyleSettings()
                .tabItem { Label(L("Base style"), systemImage: "text.quote") }
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
            Section(L("App language")) {
                Picker(L("Language"), selection: $s.appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in Text(lang.nativeName).tag(lang.rawValue) }
                }
                Text(L("The menus switch language after the app is restarted. Claude's questions and comments are written in this language."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L("Anthropic API")) {
                HStack {
                    SecureField(L("API key"), text: $keyDraft, prompt: Text(verbatim: "sk-ant-…"))
                    Button(L("Save")) {
                        s.apiKey = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        keySaved = true
                    }
                    .disabled(keyDraft.isEmpty)
                }
                if let problem = s.keychainProblem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if keySaved {
                    Text(L("✓ Saved in the keychain and read from there at every launch."))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(s.hasAPIKey ? L("A key is saved (taken from {0}).", s.apiKeySource.label)
                                     : L("No key saved. Create one at console.anthropic.com."))
                        .font(.caption).foregroundStyle(.secondary)
                }

                Picker(L("Model"), selection: $s.model) {
                    ForEach(AppSettings.modelChoices) { m in Text(m.label).tag(m.id) }
                    if !AppSettings.modelChoices.contains(where: { $0.id == s.model }) {
                        Text(s.model).tag(s.model)
                    }
                }
                TextField(L("Custom model ID"), text: $s.model)
                    .font(.system(.body, design: .monospaced))
                Picker(L("Effort"), selection: $s.effort) {
                    ForEach(AppSettings.effortChoices) { e in Text(e.label).tag(e.id) }
                }
                Toggle(L("Fallback model if a request is declined (server-side fallback)"), isOn: $s.useFallbacks)
            }

            Section(L("Languages")) {
                Picker(L("Translate from"), selection: $s.sourceLanguage) {
                    Text(L("Automatic (detect the language)")).tag(Language.auto)
                    Divider()
                    ForEach(Language.all) { lang in Text(lang.menuName).tag(lang.code) }
                }
                Picker(L("Translate into"), selection: $s.targetLanguage) {
                    ForEach(Language.all) { lang in Text(lang.menuName).tag(lang.code) }
                }
                Text(L("Can also be changed directly in the main window. The language is detected with macOS's built-in language recognition and the file name (e.g. _en, .ger)."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L("Translation")) {
                Stepper(L("Subtitles per request: {0}", s.batchSize), value: $s.batchSize, in: 5...60, step: 5)
                Stepper(L("Context (earlier subtitles): {0}", s.contextSize), value: $s.contextSize, in: 0...20)
                Stepper(L("Max characters/second: {0}", Int(s.maxCPS)), value: $s.maxCPS, in: 10...30, step: 1)
                Stepper(L("Max characters per line: {0}", s.maxLineLength), value: $s.maxLineLength, in: 30...60)
            }

            Section(L("Questions and prompts")) {
                Picker(L("When Claude is unsure"), selection: $s.questionMode) {
                    ForEach(QuestionMode.allCases) { m in Text(m.label).tag(m) }
                }
                Toggle(L("Suggest updates to the prompt (new characters, terms …)"), isOn: $s.suggestProfileUpdates)
                Toggle(L("Web search when Claude creates prompts"), isOn: $s.webSearchForProfiles)
                HStack {
                    Text(L("The prompt library is stored in"))
                    Spacer()
                    Button(L("Show in Finder")) {
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
            Text(L("The base style applies to every translation and review. The work profile is added on top. Placeholders: {SOURCE_LANGUAGE} and {TARGET_LANGUAGE} become the language names, {TARGET_RULES} the target language's own rules (e.g. du/ni, du/Sie), {MAX_LINE_LEN} and {MAX_CPS} the values under General."))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $s.baseStyle)
                .font(.system(.body, design: .monospaced))
            HStack {
                Button(L("Load from file…")) {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.plainText, .text]
                    if panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url, encoding: .utf8) {
                        s.baseStyle = text
                    }
                }
                Spacer()
                Button(L("Restore default")) { s.baseStyle = PromptBuilder.defaultStyle }
            }
        }
        .padding(20)
    }
}
