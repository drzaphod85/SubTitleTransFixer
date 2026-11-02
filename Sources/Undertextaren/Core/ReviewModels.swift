import Foundation
import SwiftUI

/// En replik i granskningsläget. `original` är texten som den lästes in,
/// `text` är den aktuella (ev. rättade) texten.
struct ReviewCue: Identifiable, Hashable {
    let seq: Int
    var number: String
    var timecode: String
    let original: String
    var text: String

    var id: Int { seq }
    var isChanged: Bool { text != original }

    var startTime: String {
        (timecode.components(separatedBy: "-->").first ?? timecode).trimmingCharacters(in: .whitespaces)
    }
    var duration: Double? { SRT.duration(of: timecode) }
    var cps: Double? {
        guard let d = duration, !text.isEmpty else { return nil }
        return Double(text.replacingOccurrences(of: "\n", with: "").count) / d
    }
}

enum IssueSeverity: Int, Comparable, CaseIterable, Identifiable {
    case suggestion = 0, warning = 1, error = 2

    var id: Int { rawValue }
    static func < (a: IssueSeverity, b: IssueSeverity) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .error: return "Fel"
        case .warning: return "Varning"
        case .suggestion: return "Förslag"
        }
    }
    var symbol: String {
        switch self {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .suggestion: return "lightbulb.fill"
        }
    }
    var color: Color {
        switch self {
        case .error: return .red
        case .warning: return .orange
        case .suggestion: return .blue
        }
    }
}

enum IssueCategory: String, CaseIterable, Identifiable {
    // Tekniska (lokala) kontroller
    case timing, numbering, length, readingSpeed, formatting, punctuation, consistency
    // Språkliga (Claude)
    case spelling, grammar, wording, meaning
    // Jämförelse med originalet
    case accuracy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .timing: return "Tidkoder"
        case .numbering: return "Numrering"
        case .length: return "Radlängd"
        case .readingSpeed: return "Läshastighet"
        case .formatting: return "Formatering"
        case .punctuation: return "Interpunktion"
        case .consistency: return "Konsekvens"
        case .spelling: return "Stavning"
        case .grammar: return "Grammatik"
        case .wording: return "Ordval"
        case .meaning: return "Betydelse"
        case .accuracy: return "Mot originalet"
        }
    }

    var symbol: String {
        switch self {
        case .timing: return "clock"
        case .numbering: return "number"
        case .length: return "text.alignleft"
        case .readingSpeed: return "speedometer"
        case .formatting: return "textformat"
        case .punctuation: return "ellipsis.curlybraces"
        case .consistency: return "equal.circle"
        case .spelling: return "textformat.abc.dottedunderline"
        case .grammar: return "text.book.closed"
        case .wording: return "quote.bubble"
        case .meaning: return "questionmark.bubble"
        case .accuracy: return "arrow.left.arrow.right"
        }
    }

    /// Översätter Claudes kategorinamn.
    static func fromClaude(_ s: String) -> IssueCategory {
        switch s.lowercased() {
        case "spelling", "typo", "stavning": return .spelling
        case "grammar", "grammatik": return .grammar
        case "punctuation", "interpunktion": return .punctuation
        case "consistency", "konsekvens": return .consistency
        case "meaning", "betydelse", "unclear": return .meaning
        case "formatting", "formatering": return .formatting
        case "accuracy", "mistranslation", "omission", "addition", "names", "numbers", "översättning": return .accuracy
        default: return .wording
        }
    }
}

enum IssueFix: Hashable {
    /// Ersätt replikens text med den här.
    case text(String)
    /// Ersätt tidkoden med den här.
    case timecode(String)
    /// Numrera om alla repliker 1, 2, 3 …
    case renumber
}

enum IssueOrigin: Hashable {
    case local, claude
}

struct ReviewIssue: Identifiable, Hashable {
    let id = UUID()
    var cueSeq: Int
    var category: IssueCategory
    var severity: IssueSeverity
    var message: String
    var fix: IssueFix?
    var origin: IssueOrigin = .local
    /// Texten som Claude granskade – är repliken ändrad sedan dess kan
    /// förslaget inte användas rakt av.
    var basedOn: String?

    /// Stabil nyckel så att ignorerade lokala anmärkningar förblir ignorerade
    /// när kontrollerna körs om.
    var key: String {
        origin == .claude ? id.uuidString : "\(category.rawValue)|\(cueSeq)|\(message)"
    }
}
