import AppKit
import Foundation
import UniformTypeIdentifiers

/// En fil (eller en profil ur en JSON-fil) som väntar på att importeras.
struct ImportCandidate: Identifiable {
    enum Source {
        /// Fri text, t.ex. en stilguide i .md/.txt som användes med STYLE_FILE.
        case text(String)
        /// En profil exporterad från Undertextaren.
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
    /// nil = skapa ny prompt, annars uppdatera den här.
    var targetID: UUID?
    /// Låt Claude dela upp texten i stilguide, karaktärer och ordlista.
    var structureWithClaude = false
    var status: Status = .pending

    var isText: Bool {
        if case .text = source { return true }
        return false
    }

    var preview: String {
        switch source {
        case .text(let t): return String(t.prefix(400))
        case .profile(let p): return "\(p.characters.count) karaktärer, \(p.glossary.count) termer, \(p.notes.count) anteckningar"
        }
    }
}

enum PromptImporter {
    static var allowedTypes: [UTType] {
        [UTType(filenameExtension: "md"), UTType("net.daringfireball.markdown"),
         .plainText, .text, .json].compactMap { $0 }
    }

    /// Läser filer och gör importkandidater av dem.
    @MainActor
    static func candidates(from urls: [URL], library: PromptLibrary) -> (items: [ImportCandidate], errors: [String]) {
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
                        var c = ImportCandidate(fileName: name, source: .profile(p), title: p.title, kind: p.kind)
                        c.targetID = library.profile(id: p.id)?.id ?? library.bestMatch(for: p.title, threshold: 0.95)?.profile.id
                        items.append(c)
                    }
                } else {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        errors.append("\(name): filen är tom.")
                        continue
                    }
                    let title = titleGuess(fileName: name, text: trimmed)
                    var c = ImportCandidate(fileName: name, source: .text(trimmed), title: title)
                    c.targetID = library.bestMatch(for: title)?.profile.id
                    items.append(c)
                }
            } catch {
                errors.append("\(name): kunde inte läsas (\(error.localizedDescription)).")
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
        let stopWords: Set<String> = [
            "style", "styleguide", "stil", "stilguide", "prompt", "prompts", "guide",
            "translation", "translate", "översättning", "oversattning", "profile", "profil",
            "sv", "swe", "svenska", "en", "srt", "system", "instructions", "instruktioner",
        ]
        let guess = TitleMatcher.guess(fromFileName: fileName).title
        let words = guess
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map(String.init)
            .filter { !stopWords.contains($0.lowercased()) }
        var title = words.joined(separator: " ")

        // Inget kvar av filnamnet? Ta första rubriken i texten.
        if title.isEmpty, let heading = text.components(separatedBy: "\n")
            .first(where: { $0.hasPrefix("#") }) {
            title = heading.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces))
        }
        if title.isEmpty { title = (fileName as NSString).deletingPathExtension }

        // Gör "all creatures" → "All Creatures" om allt är gemener
        if title == title.lowercased() {
            title = title.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        }
        return title
    }

    /// Sparar prompter som JSON (samma format som importen läser).
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
            return "Kunde inte exportera: \(error.localizedDescription)"
        }
    }
}
