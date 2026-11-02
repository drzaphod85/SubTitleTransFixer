import Foundation
import Observation

/// Sparade promptprofiler, en per TV-serie eller film.
/// Lagras som JSON i ~/Library/Application Support/Undertextaren/profiles.json
@MainActor
@Observable
final class PromptLibrary {
    var profiles: [SeriesProfile] = []
    var lastError: String?

    @ObservationIgnored let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        let dir = base.appendingPathComponent("Undertextaren", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("profiles.json")
        load()
    }

    var sorted: [SeriesProfile] {
        profiles.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            profiles = try decoder.decode([SeriesProfile].self, from: data)
        } catch {
            lastError = "Kunde inte läsa promptbiblioteket: \(error.localizedDescription)"
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(profiles)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            lastError = "Kunde inte spara promptbiblioteket: \(error.localizedDescription)"
        }
    }

    func profile(id: UUID?) -> SeriesProfile? {
        guard let id else { return nil }
        return profiles.first { $0.id == id }
    }

    func index(of id: UUID) -> Int? {
        profiles.firstIndex { $0.id == id }
    }

    func upsert(_ profile: SeriesProfile) {
        var p = profile
        p.updatedAt = Date()
        if let i = index(of: p.id) { profiles[i] = p } else { profiles.append(p) }
        save()
    }

    func delete(id: UUID) {
        profiles.removeAll { $0.id == id }
        save()
    }

    /// Hittar den sparade profil som bäst matchar en titel (t.ex. gissad ur filnamnet).
    /// - Parameter targetLanguage: om angivet räknas bara prompter för det målspråket.
    func bestMatch(for title: String, targetLanguage: String? = nil, threshold: Double = 0.82) -> (profile: SeriesProfile, score: Double)? {
        var best: (SeriesProfile, Double)?
        for p in profiles where targetLanguage == nil || p.targetLanguage == targetLanguage {
            let names = [p.title] + p.aliases
            let s = names.map { TitleMatcher.score(title, against: $0) }.max() ?? 0
            if s > (best?.1 ?? 0) { best = (p, s) }
        }
        guard let best, best.1 >= threshold else { return nil }
        return (best.0, best.1)
    }

    /// Lägger till godkända förslag i en profil.
    func apply(_ suggestions: [ProfileSuggestion], to id: UUID) {
        guard let i = index(of: id) else { return }
        var p = profiles[i]
        for s in suggestions where s.accepted {
            switch s.kind {
            case .character(let c):
                if !p.hasCharacter(named: c.name) { p.characters.append(c) }
            case .term(let g):
                if !p.hasTerm(g.source) { p.glossary.append(g) }
            case .note(let n):
                if !p.notes.contains(n) { p.notes.append(n) }
            }
        }
        upsert(p)
    }

    func addNote(_ note: String, to id: UUID) {
        guard let i = index(of: id) else { return }
        if !profiles[i].notes.contains(note) {
            profiles[i].notes.append(note)
            upsert(profiles[i])
        }
    }
}
