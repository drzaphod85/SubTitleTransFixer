import AppKit
import Foundation

/// Opening files from outside the app's own Open panels: drag and drop onto the
/// window, onto the Dock icon, "Open With" in Finder, or a double-click on a
/// subtitle file when the app is the default for .srt.
extension AppModel {
    /// Where a subtitle file should be opened.
    enum OpenTarget {
        case translate
        case review
        /// Decide from the file: a file already in the target language is
        /// reviewed, anything else is translated. Used for Finder and the Dock.
        case automatic
    }

    static let promptExtensions: Set<String> = ["md", "markdown", "txt", "json"]

    /// Opens the files and returns whether any of them could be used.
    ///
    /// - `.srt`: opened for translation or review (only the first one).
    /// - Video: used as the review's video when a file is being reviewed.
    /// - `.md`, `.txt`, `.json`: offered for import into the prompt library.
    @discardableResult
    func open(_ urls: [URL], in target: OpenTarget = .automatic) -> Bool {
        let files = urls.filter(\.isFileURL)
        func with(_ extensions: Set<String>) -> [URL] {
            files.filter { extensions.contains($0.pathExtension.lowercased()) }
        }
        let subtitles = with(["srt"])
        let videos = with(MediaLocator.videoExtensions)
        let prompts = with(Self.promptExtensions)
        var handled = false

        if let srt = subtitles.first {
            handled = true
            switch resolve(target, for: srt) {
            case .review:
                if review.confirmDiscardChanges() {
                    review.load(url: srt, confirmed: true)
                    selection = .review
                }
            default:
                if confirmReplaceTranslation(with: srt) {
                    session.load(url: srt)
                    selection = .translate
                }
            }
        }
        if let video = videos.first, review.hasFile, selection == .review {
            review.useVideo(video)
            handled = true
        }
        if !prompts.isEmpty {
            importFiles(prompts)
            handled = true
        }
        return handled
    }

    private func resolve(_ target: OpenTarget, for url: URL) -> OpenTarget {
        guard target == .automatic else { return target }
        if selection == .review { return .review }
        guard let raw = try? SRT.readText(at: url) else { return .translate }
        let texts = SRT.parse(raw).map(\.original)
        let detected = LanguageDetector.detect(texts: texts, fileName: url.lastPathComponent)
        return detected?.language == settings.target ? .review : .translate
    }

    /// Asks before a started translation is replaced by another file.
    private func confirmReplaceTranslation(with url: URL) -> Bool {
        guard session.translatedCount > 0, session.fileURL != url else { return true }
        let alert = NSAlert()
        alert.messageText = L("Open “{0}”?", url.lastPathComponent)
        alert.informativeText = L("The translation of “{0}” will be closed. Save it first if you want to keep it.",
                                  session.fileURL?.lastPathComponent ?? "")
        alert.addButton(withTitle: L("Open"))
        alert.addButton(withTitle: L("Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
