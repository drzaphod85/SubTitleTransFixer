import Foundation

/// Tekniska kontroller av en undertextfil. Körs lokalt, utan Claude.
enum SubtitleChecker {
    struct Options {
        var maxCPS: Double = 17
        var maxLineLength: Int = 42
        var language: Language = .swedish
        var minDuration: Double = 0.7
        var maxDuration: Double = 7.0
        /// Minsta glapp som lämnas när ett överlapp rättas (ms).
        var overlapGap: Int = 40
    }

    static func check(_ cues: [ReviewCue], options o: Options) -> [ReviewIssue] {
        var issues: [ReviewIssue] = []
        issues += numbering(cues)
        issues += timing(cues, o)
        for (i, cue) in cues.enumerated() {
            issues += text(cue, previous: i > 0 ? cues[i - 1] : nil, o)
        }
        issues += ellipsisConsistency(cues)
        issues += dashConsistency(cues)
        return issues
    }

    // MARK: - Numrering

    private static func numbering(_ cues: [ReviewCue]) -> [ReviewIssue] {
        guard let first = cues.first(where: { $0.number != String($0.seq) }) else { return [] }
        let dupes = Dictionary(grouping: cues, by: \.number).filter { $0.value.count > 1 }.count
        var msg = "Numreringen stämmer inte från replik \(first.seq) (står ”\(first.number)”)."
        if dupes > 0 { msg += " \(dupes) nummer förekommer flera gånger." }
        msg += " Numrera om alla repliker 1, 2, 3 …"
        return [ReviewIssue(cueSeq: first.seq, category: .numbering, severity: dupes > 0 ? .warning : .suggestion,
                            message: msg, fix: .renumber)]
    }

    // MARK: - Tidkoder

    private static func timing(_ cues: [ReviewCue], _ o: Options) -> [ReviewIssue] {
        var issues: [ReviewIssue] = []
        for (i, cue) in cues.enumerated() {
            guard let t = SRT.times(of: cue.timecode) else {
                issues.append(ReviewIssue(cueSeq: cue.seq, category: .timing, severity: .error,
                                          message: "Tidkoden går inte att tolka: ”\(cue.timecode)”."))
                continue
            }
            let dur = Double(t.end - t.start) / 1000
            if t.end <= t.start {
                issues.append(ReviewIssue(cueSeq: cue.seq, category: .timing, severity: .error,
                                          message: "Sluttiden ligger före eller på starttiden."))
            } else if dur < o.minDuration {
                issues.append(ReviewIssue(cueSeq: cue.seq, category: .timing, severity: .warning,
                                          message: String(format: "Visas bara %.2f s – svår att hinna läsa (minst %.1f s rekommenderas).", dur, o.minDuration)))
            } else if dur > o.maxDuration {
                issues.append(ReviewIssue(cueSeq: cue.seq, category: .timing, severity: .suggestion,
                                          message: String(format: "Visas i %.1f s – ovanligt länge (över %.0f s).", dur, o.maxDuration)))
            }

            if i + 1 < cues.count, let next = SRT.times(of: cues[i + 1].timecode) {
                if next.start < t.start {
                    issues.append(ReviewIssue(cueSeq: cues[i + 1].seq, category: .timing, severity: .error,
                                              message: "Repliken börjar före föregående replik – fel ordning."))
                } else if next.start < t.end {
                    let newEnd = next.start - o.overlapGap
                    let fix: IssueFix? = newEnd - t.start >= 300
                        ? .timecode(SRT.replacingEnd(in: cue.timecode, with: newEnd)) : nil
                    issues.append(ReviewIssue(cueSeq: cue.seq, category: .timing, severity: .error,
                                              message: "Överlappar nästa replik med \(t.end - next.start) ms.", fix: fix))
                }
            }
        }
        return issues
    }

    // MARK: - Text

    private static func text(_ cue: ReviewCue, previous: ReviewCue?, _ o: Options) -> [ReviewIssue] {
        var issues: [ReviewIssue] = []
        let text = cue.text
        func add(_ cat: IssueCategory, _ sev: IssueSeverity, _ msg: String, _ fixed: String? = nil) {
            let fix: IssueFix? = fixed.flatMap { $0 != text ? .text($0) : nil }
            issues.append(ReviewIssue(cueSeq: cue.seq, category: cat, severity: sev, message: msg, fix: fix))
        }

        let visible = stripTags(text).trimmingCharacters(in: .whitespacesAndNewlines)
        if visible.isEmpty {
            add(.formatting, .error, "Repliken är tom.")
            return issues
        }

        let lines = text.components(separatedBy: "\n")

        // Antal rader och radlängd
        if lines.count > 2 {
            add(.length, .warning, "\(lines.count) rader – max 2 rader per replik rekommenderas.")
        }
        let longest = lines.map { stripTags($0).count }.max() ?? 0
        if longest > o.maxLineLength {
            add(.length, .warning, "En rad har \(longest) tecken (max \(o.maxLineLength)).")
        }

        // Läshastighet
        if let cps = cue.cps {
            if cps > o.maxCPS + 3 {
                add(.readingSpeed, .warning, String(format: "%.1f tecken/sekund – för snabbt att läsa (mål ≤ %.0f).", cps, o.maxCPS))
            } else if cps > o.maxCPS {
                add(.readingSpeed, .suggestion, String(format: "%.1f tecken/sekund – något över målet %.0f.", cps, o.maxCPS))
            }
        }

        // Mellanslag
        let tidy = lines
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        if tidy != text {
            add(.formatting, .suggestion, "Överflödiga mellanslag eller tomma rader.", tidy)
        }

        // Mellanslag före skiljetecken (franska använder det för ! ? : ;)
        let french = o.language.code == "fr"
        let beforePattern = french ? #" +([,]|\.(?!\.))"# : #" +([,!?:;]|\.(?!\.))"#
        if matches(text, beforePattern) {
            add(.punctuation, .warning, "Mellanslag före skiljetecken.",
                text.replacingOccurrences(of: beforePattern, with: "$1", options: .regularExpression))
        }

        // Saknat mellanslag efter skiljetecken
        let afterPattern = #"([,;:!?])(?=\p{L})"#
        if matches(text, afterPattern) {
            add(.punctuation, .warning, "Saknat mellanslag efter skiljetecken.",
                text.replacingOccurrences(of: afterPattern, with: "$1 ", options: .regularExpression))
        }

        // Upprepade ord ("att att")
        let repeatPattern = #"(?i)\b(\p{L}+)\s+\1\b"#
        if let word = firstMatch(text, repeatPattern, group: 1) {
            add(.spelling, .warning, "Ordet ”\(word)” står två gånger i rad.",
                text.replacingOccurrences(of: repeatPattern, with: "$1", options: .regularExpression))
        }

        // Taggar och parenteser
        for tag in ["i", "b", "u"] {
            let open = count(text, "(?i)<\(tag)>"), close = count(text, "(?i)</\(tag)>")
            if open != close {
                add(.formatting, .error, "Obalanserade <\(tag)>-taggar (\(open) öppnande, \(close) stängande).")
            }
        }
        if text.filter({ $0 == "(" }).count != text.filter({ $0 == ")" }).count {
            add(.punctuation, .warning, "Parenteserna går inte jämnt ut.")
        }
        if text.filter({ $0 == "[" }).count != text.filter({ $0 == "]" }).count {
            add(.punctuation, .warning, "Hakparenteserna går inte jämnt ut.")
        }
        if text.filter({ $0 == "\"" }).count % 2 == 1 {
            add(.punctuation, .suggestion, "Udda antal citattecken – kontrollera att citatet avslutas (det kan fortsätta i nästa replik).")
        }

        // Liten bokstav efter avslutad mening i föregående replik
        if let previous, let last = stripTags(previous.text).trimmingCharacters(in: .whitespacesAndNewlines).last,
           ".!?".contains(last), !previous.text.hasSuffix("..."), !previous.text.hasSuffix("…") {
            if let idx = firstLetterIndex(text), text[idx].isLowercase, !startsWithEllipsis(text) {
                var fixed = text
                fixed.replaceSubrange(idx...idx, with: String(text[idx]).uppercased())
                add(.punctuation, .suggestion, "Börjar med liten bokstav fast föregående replik avslutade en mening.", fixed)
            }
        }

        return issues
    }

    // MARK: - Konsekvens i hela filen

    private static func ellipsisConsistency(_ cues: [ReviewCue]) -> [ReviewIssue] {
        let threeDots = cues.filter { $0.text.contains("...") }
        let ellipsis = cues.filter { $0.text.contains("…") }
        guard !threeDots.isEmpty, !ellipsis.isEmpty else { return [] }
        let useEllipsis = ellipsis.count >= threeDots.count
        let minority = useEllipsis ? threeDots : ellipsis
        return minority.map { cue in
            let fixed = useEllipsis
                ? cue.text.replacingOccurrences(of: "...", with: "…")
                : cue.text.replacingOccurrences(of: "…", with: "...")
            return ReviewIssue(cueSeq: cue.seq, category: .consistency, severity: .suggestion,
                               message: "Filen använder mest ”\(useEllipsis ? "…" : "...")” men här står ”\(useEllipsis ? "..." : "…")”.",
                               fix: .text(fixed))
        }
    }

    private enum DashStyle: String, CaseIterable {
        case hyphenSpace = "- ", hyphen = "-", enSpace = "– ", en = "–"
    }

    private static func dashStyle(of line: String) -> DashStyle? {
        let l = stripTags(line)
        if l.hasPrefix("--") || l.hasPrefix("-->") { return nil }
        if l.hasPrefix("- ") { return .hyphenSpace }
        if l.hasPrefix("– ") { return .enSpace }
        if l.hasPrefix("-"), let c = l.dropFirst().first, c.isLetter || c == "\"" { return .hyphen }
        if l.hasPrefix("–"), let c = l.dropFirst().first, c.isLetter || c == "\"" { return .en }
        return nil
    }

    private static func dashConsistency(_ cues: [ReviewCue]) -> [ReviewIssue] {
        var counts: [DashStyle: Int] = [:]
        for cue in cues {
            for line in cue.text.components(separatedBy: "\n") {
                if let s = dashStyle(of: line) { counts[s, default: 0] += 1 }
            }
        }
        guard counts.count > 1, let major = counts.max(by: { $0.value < $1.value })?.key else { return [] }

        var issues: [ReviewIssue] = []
        for cue in cues {
            var changed = false
            let lines = cue.text.components(separatedBy: "\n").map { line -> String in
                guard let s = dashStyle(of: line), s != major else { return line }
                changed = true
                // Byt bara själva strecket i början av raden (efter ev. taggar).
                guard let r = line.range(of: s.rawValue) else { return line }
                var l = line
                l.replaceSubrange(r, with: major.rawValue)
                return l
            }
            if changed {
                issues.append(ReviewIssue(cueSeq: cue.seq, category: .consistency, severity: .suggestion,
                                          message: "Dialogstrecket skrivs annars ”\(major.rawValue.trimmingCharacters(in: .whitespaces))\(major.rawValue.hasSuffix(" ") ? " + mellanslag" : " utan mellanslag")” i filen.",
                                          fix: .text(lines.joined(separator: "\n"))))
            }
        }
        return issues
    }

    // MARK: - Hjälpare

    static func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: #"<[^>]+>|\{[^}]*\}"#, with: "", options: .regularExpression)
    }

    private static func matches(_ s: String, _ pattern: String) -> Bool {
        s.range(of: pattern, options: .regularExpression) != nil
    }

    private static func count(_ s: String, _ pattern: String) -> Int {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return re.numberOfMatches(in: s, range: NSRange(s.startIndex..., in: s))
    }

    private static func firstMatch(_ s: String, _ pattern: String, group: Int) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range(at: group), in: s) else { return nil }
        return String(s[r])
    }

    /// Första bokstaven utanför taggar.
    private static func firstLetterIndex(_ s: String) -> String.Index? {
        var inTag = false
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "<" { inTag = true } else if c == ">" { inTag = false } else if !inTag && c.isLetter { return i }
            i = s.index(after: i)
        }
        return nil
    }

    private static func startsWithEllipsis(_ s: String) -> Bool {
        let t = stripTags(s).trimmingCharacters(in: CharacterSet(charactersIn: "-– \"'"))
        return t.hasPrefix("...") || t.hasPrefix("…")
    }
}
