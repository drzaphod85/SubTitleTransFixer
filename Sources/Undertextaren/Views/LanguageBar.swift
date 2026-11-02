import SwiftUI

/// Rad med "Från"/"Till"-språk och resultatet av språkigenkänningen.
struct LanguageBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        let session = model.session

        HStack(spacing: 10) {
            Image(systemName: "globe").foregroundStyle(.secondary)

            Text("Från").foregroundStyle(.secondary)
            Picker("Från", selection: $settings.sourceLanguage) {
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
            .help("Byt plats på språken")

            Text("Till").foregroundStyle(.secondary)
            Picker("Till", selection: $settings.targetLanguage) {
                ForEach(Language.all) { lang in
                    Text(lang.menuName).tag(lang.code)
                }
            }
            .labelsHidden()
            .frame(width: 200)

            if let d = session.detection {
                Label("Upptäckt: \(d.language.displayName)", systemImage: d.confidence >= 0.8 ? "checkmark.circle" : "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(d.confidence >= 0.8 ? Color.secondary : Color.orange)
                    .help(d.summary)
            }

            if session.sameLanguageWarning {
                Label("Filen verkar redan vara på \(session.targetLanguage.name)", systemImage: "exclamationmark.triangle.fill")
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
        guard let d = detection else { return "Automatiskt" }
        return "Automatiskt (\(d.language.displayName))"
    }
}
