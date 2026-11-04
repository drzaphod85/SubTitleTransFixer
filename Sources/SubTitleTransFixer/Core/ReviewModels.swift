import Foundation
import SwiftUI

/// A subtitle in review mode. `original` is the text as it was loaded,
/// `text` is the current (possibly corrected) text.
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
        case .error: return L("Error")
        case .warning: return L("Warning")
        case .suggestion: return L("Suggestion")
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
    // Technical (local) checks
    case timing, numbering, length, readingSpeed, formatting, punctuation, consistency
    // Language (Claude)
    case spelling, grammar, wording, meaning
    // Comparison with the original
    case accuracy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .timing: return L("Timecodes")
        case .numbering: return L("Numbering")
        case .length: return L("Line length")
        case .readingSpeed: return L("Reading speed")
        case .formatting: return L("Formatting")
        case .punctuation: return L("Punctuation")
        case .consistency: return L("Consistency")
        case .spelling: return L("Spelling")
        case .grammar: return L("Grammar")
        case .wording: return L("Wording")
        case .meaning: return L("Meaning")
        case .accuracy: return L("Against the original")
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

    /// Maps Claude's category names.
    static func fromClaude(_ s: String) -> IssueCategory {
        switch s.lowercased() {
        case "spelling", "typo": return .spelling
        case "grammar": return .grammar
        case "punctuation": return .punctuation
        case "consistency": return .consistency
        case "meaning", "unclear": return .meaning
        case "formatting": return .formatting
        case "accuracy", "mistranslation", "omission", "addition", "names", "numbers": return .accuracy
        default: return .wording
        }
    }
}

enum IssueFix: Hashable {
    /// Replace the subtitle's text with this.
    case text(String)
    /// Replace the timecode with this.
    case timecode(String)
    /// Renumber all subtitles 1, 2, 3 …
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
    /// The text Claude reviewed – if the subtitle has changed since then,
    /// the suggestion cannot be applied as is.
    var basedOn: String?

    /// Stable key so that ignored local issues stay ignored when the checks run again.
    var key: String {
        origin == .claude ? id.uuidString : "\(category.rawValue)|\(cueSeq)|\(message)"
    }
}
