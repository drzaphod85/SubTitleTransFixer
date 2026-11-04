import AppKit
import Foundation
import UniformTypeIdentifiers

/// A file (or a profile from a JSON file) waiting to be imported.
struct ImportCandidate: Identifiable {
    enum Source {
        /// Free text, e.g. a style guide in .md/.txt that was used with STYLE_FILE.
        case text(String)
        /// A profile exported from SubTitle TransFixer (or Undertextaren).
        case profile(SeriesProfile)
    }

    enum Status: Equatable {
        case pending, working, done
        case failed(String)
    }

    let id = UUID()
    let fileName: String
    var source: Source
    var title: String
    var kind: MediaKind = .series
    /// The language the prompt is for translating into.
    var targetLanguage: String = "sv"
    /// nil = create a new prompt, otherwise update this one.
    var targetID: UUID?
    /// Let Claude split the text into style guide, characters and glossary.
    var structureWithClaude = false
    var status: Status = .pending

    var isText: Bool {
        if case .text = source { return true }
        return false
    }

    var preview: String {
        switch source {
        case .text(let t): return String(t.prefix(400))
        case .profile(let p): return L("{0} characters, {1} terms, {2} notes", p.characters.count, p.glossary.count, p.notes.count)
        }
    }
}

enum PromptImporter {
    static var allowedTypes: [UTType] {
        [UTType(filenameExtension: "md"), UTType("net.daringfireball.markdown"),
         .plainText, .text, .json].compactMap { $0 }
    }

    /// Reads files and turns them into import candidates.
    @MainActor
    static func candidates(from urls: [URL], library: PromptLibrary, defaultTarget: String) -> (items: [ImportCandidate], errors: [String]) {
        var items: [ImportCandidate] = []
        var errors: [String] = []

        for url in urls {
            let name = url.lastPathComponent
            do {
                let text = try SRT.readText(at: url)
                if url.pathExtension.lowercased() == "json" {
                    let profiles = try decodeProfiles(Data(text.utf8))
                    guard !profiles.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                    for p in profiles {
                        var c = ImportCandidate(fileName: name, source: .profile(p), title: p.title, kind: p.kind,
                                                targetLanguage: p.targetLanguage)
                        c.targetID = library.profile(id: p.id)?.id
                            ?? library.bestMatch(for: p.title, targetLanguage: p.targetLanguage, threshold: 0.95)?.profile.id
                        items.append(c)
                    }
                } else {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        errors.append(L("{0}: the file is empty.", name))
                        continue
                    }
                    let title = titleGuess(fileName: name, text: trimmed)
                    let lang = defaultTarget
                    var c = ImportCandidate(fileName: name, source: .text(trimmed), title: title, targetLanguage: lang)
                    c.targetID = library.bestMatch(for: title, targetLanguage: lang)?.profile.id
                    items.append(c)
                }
            } catch {
                errors.append(L("{0}: could not be read ({1}).", name, error.localizedDescription))
            }
        }
        return (items, errors)
    }

    static func decodeProfiles(_ data: Data) throws -> [SeriesProfile] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let list = try? decoder.decode([SeriesProfile].self, from: data) { return list }
        return [try decoder.decode(SeriesProfile.self, from: data)]
    }

    static func encodeProfiles(_ profiles: [SeriesProfile]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(profiles)
    }

    /// "all-creatures-great-and-small_stil.md" → "All Creatures Great And Small"
    static func titleGuess(fileName: String, text: String) -> String {
        // Words that describe the file rather than the work – in English and the Nordic languages.
        let stopWords: Set<String> = [
            "style", "styleguide", "prompt", "prompts", "guide", "translation", "translate",
            "profile", "system", "instructions", "srt", "en", "sv", "swe",
            "stil", "stilguide", "profil", "översättning", "oversattning", "svenska", "instruktioner",
            "oversettelse", "oversættelse", "instruksjoner",
            "tyyli", "käännös", "ohjeet", "þýðing", "stíll",
        ]
        let guess = TitleMatcher.guess(fromFileName: fileName).title
        let words = guess
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map(String.init)
            .filter { !stopWords.contains($0.lowercased()) }
        var title = words.joined(separator: " ")

        // Nothing left of the file name? Use the first heading in the text.
        if title.isEmpty, let heading = text.components(separatedBy: "\n")
            .first(where: { $0.hasPrefix("#") }) {
            title = heading.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces))
        }
        if title.isEmpty { title = (fileName as NSString).deletingPathExtension }

        // Turn "all creatures" into "All Creatures" if everything is lower case
        if title == title.lowercased() {
            title = title.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        }
        return title
    }

    /// Saves prompts as JSON (the same format the import reads).
    @MainActor
    static func exportPanel(_ profiles: [SeriesProfile], suggestedName: String) -> String? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try encodeProfiles(profiles).write(to: url, options: .atomic)
            return nil
        } catch {
            return L("Could not export: {0}", error.localizedDescription)
        }
    }
}
