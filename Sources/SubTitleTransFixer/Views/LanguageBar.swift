import SwiftUI

/// Row with the "From"/"To" languages and the result of language detection.
struct LanguageBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        let session = model.session

        HStack(spacing: 10) {
            Image(systemName: "globe").foregroundStyle(.secondary)

            Text(L("From")).foregroundStyle(.secondary)
            Picker(L("From"), selection: $settings.sourceLanguage) {
                Text(autoLabel(session.detection)).tag(Language.auto)
                Divider()
                ForEach(Language.all) { lang in
                    Text(lang.menuName).tag(lang.code)
                }
            }
            .labelsHidden()
            .frame(width: 240)

            Button {
                let source = session.sourceLanguage.code
                settings.sourceLanguage = settings.targetLanguage
                settings.targetLanguage = source
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .buttonStyle(.borderless)
            .help(L("Swap the languages"))

            Text(L("To")).foregroundStyle(.secondary)
            Picker(L("To"), selection: $settings.targetLanguage) {
                ForEach(Language.all) { lang in
                    Text(lang.menuName).tag(lang.code)
                }
            }
            .labelsHidden()
            .frame(width: 200)

            if let d = session.detection {
                Label(L("Detected: {0}", d.language.displayName), systemImage: d.confidence >= 0.8 ? "checkmark.circle" : "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(d.confidence >= 0.8 ? Color.secondary : Color.orange)
                    .help(d.summary)
            }

            if session.sameLanguageWarning {
                Label(L("The file already seems to be in {0}", session.targetLanguage.inlineName), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .onChange(of: settings.targetLanguage) {
            session.matchProfile()
        }
    }

    private func autoLabel(_ detection: LanguageDetection?) -> String {
        guard let d = detection else { return L("Automatic") }
        return L("Automatic ({0})", d.language.displayName)
    }
}
