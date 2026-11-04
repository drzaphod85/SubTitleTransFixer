import Foundation

/// Technical checks of a subtitle file. Runs locally, without Claude.
enum SubtitleChecker {
    struct Options {
        var maxCPS: Double = 17
        var maxLineLength: Int = 42
        var language: Language = .swedish
        var minDuration: Double = 0.7
        var maxDuration: Double = 7.0
        /// Smallest gap left when an overlap is fixed (ms).
        var overlapGap: Int = 40
    }

    static func check(_ cues: [ReviewCue], options o: Options) -> [ReviewIssue] {
        var issues: [ReviewIssue] = []
        issues += numbering(cues)
        issues += timing(cues, o)
        for (i, cue) in cues.enumerated() {
            let nextStart = i + 1 < cues.count ? SRT.times(of: cues[i + 1].timecode)?.start : nil
            issues += text(cue, previous: i > 0 ? cues[i - 1] : nil, nextStart: nextStart, o)
        }
        issues += ellipsisConsistency(cues)
        issues += dashConsistency(cues)
        return issues
    }

    // MARK: - Numbering

    private static func numbering(_ cues: [ReviewCue]) -> [ReviewIssue] {
        // Compare with the position in the file, since subtitles can be removed or sorted.
        guard let position = cues.indices.first(where: { cues[$0].number != String($0 + 1) }) else { return [] }
        let first = cues[position]
        let dupes = Dictionary(grouping: cues, by: \.number).filter { $0.value.count > 1 }.count
        var msg = L("The numbering is off from subtitle {0} (it says “{1}”).", position + 1, first.number)
        if dupes > 0 { msg += " " + L("{0} numbers occur more than once.", dupes) }
        msg += " " + L("Renumber all subtitles 1, 2, 3 …")
        return [ReviewIssue(cueSeq: first.seq, category: .numbering, severity: dupes > 0 ? .warning : .suggestion,
                            message: msg, fix: .renumber)]
    }

    // MARK: - Timecodes

    private static func timing(_ cues: [ReviewCue], _ o: Options) -> [ReviewIssue] {
        var issues: [ReviewIssue] = []
        for (i, cue) in cues.enumerated() {
            guard let t = SRT.times(of: cue.timecode) else {
                issues.append(ReviewIssue(cueSeq: cue.seq, category: .timing, severity: .error,
                                          message: L("The timecode cannot be parsed: “{0}”.", cue.timecode)))
                continue
            }
            let dur = Double(t.end - t.start) / 1000
            let nextStart = i + 1 < cues.count ? SRT.times(of: cues[i + 1].timecode)?.start : nil
            // How long the subtitle needs to be readable at the CPS target.
            let chars = stripTags(cue.text).replacingOccurrences(of: "\n", with: "").count
            let needed = max(Int(o.minDuration * 1000), Int(Double(chars) / o.maxCPS * 1000))
            if t.end <= t.start {
                let fix = extendedEnd(start: t.start, wanted: t.start + needed, currentEnd: t.start, nextStart: nextStart, o)
                    .map { IssueFix.timecode(SRT.replacingEnd(in: cue.timecode, with: $0)) }
                issues.append(ReviewIssue(cueSeq: cue.seq, category: .timing, severity: .error,
                                          message: L("The end time is before or at the start time."), fix: fix))
            } else if dur < o.minDuration {
                let fix = extendedEnd(start: t.start, wanted: t.start + needed, currentEnd: t.end, nextStart: nextStart, o)
                    .map { IssueFix.timecode(SRT.replacingEnd(in: cue.timecode, with: $0)) }
                issues.append(ReviewIssue(cueSeq: cue.seq, category: .timing, severity: .warning,
                                          message: L("Shown for only {0} s – hard to read in time (at least {1} s recommended).", formatNumber(dur, decimals: 2), formatNumber(o.minDuration)),
                                          fix: fix))
            } else if dur > o.maxDuration {
                // Shorten to the maximum, but never below what the text needs.
                let newEnd = t.start + max(Int(o.maxDuration * 1000), needed)
                let fix: IssueFix? = newEnd < t.end - 50 ? .timecode(SRT.replacingEnd(in: cue.timecode, with: newEnd)) : nil
                issues.append(ReviewIssue(cueSeq: cue.seq, category: .timing, severity: .suggestion,
                                          message: L("Shown for {0} s – unusually long (over {1} s).", formatNumber(dur), formatNumber(o.maxDuration, decimals: 0)),
                                          fix: fix))
            }

            if i + 1 < cues.count, let next = SRT.times(of: cues[i + 1].timecode) {
                if next.start < t.start {
                    issues.append(ReviewIssue(cueSeq: cues[i + 1].seq, category: .timing, severity: .error,
                                              message: L("The subtitle starts before the previous one – wrong order."),
                                              fix: .sortByTime))
                } else if next.start < t.end {
                    let newEnd = next.start - o.overlapGap
                    let fix: IssueFix? = newEnd - t.start >= 300
                        ? .timecode(SRT.replacingEnd(in: cue.timecode, with: newEnd)) : nil
                    issues.append(ReviewIssue(cueSeq: cue.seq, category: .timing, severity: .error,
                                              message: L("Overlaps the next subtitle by {0} ms.", t.end - next.start), fix: fix))
                }
            }
        }
        return issues
    }

    /// A later end time, as close to `wanted` as possible without running into
    /// the next subtitle. nil if the end cannot be moved noticeably.
    private static func extendedEnd(start: Int, wanted: Int, currentEnd: Int, nextStart: Int?, _ o: Options) -> Int? {
        var end = wanted
        if let nextStart { end = min(end, nextStart - o.overlapGap) }
        return end > max(currentEnd, start) + 50 ? end : nil
    }

    // MARK: - Text

    private static func text(_ cue: ReviewCue, previous: ReviewCue?, nextStart: Int?, _ o: Options) -> [ReviewIssue] {
        var issues: [ReviewIssue] = []
        let text = cue.text
        func add(_ cat: IssueCategory, _ sev: IssueSeverity, _ msg: String, _ fixed: String? = nil) {
            let fix: IssueFix? = fixed.flatMap { $0 != text ? .text($0) : nil }
            issues.append(ReviewIssue(cueSeq: cue.seq, category: cat, severity: sev, message: msg, fix: fix))
        }

        let visible = stripTags(text).trimmingCharacters(in: .whitespacesAndNewlines)
        if visible.isEmpty {
            issues.append(ReviewIssue(cueSeq: cue.seq, category: .formatting, severity: .error,
                                      message: L("The subtitle is empty."), fix: .deleteCue))
            return issues
        }

        let lines = text.components(separatedBy: "\n")

        // Number of lines and line length
        // Number of lines and line length – fixed by re-wrapping when the text fits on two lines
        let longest = lines.map { stripTags($0).count }.max() ?? 0
        let rewrapped = (lines.count > 2 || longest > o.maxLineLength) ? rewrap(text, maxLength: o.maxLineLength) : nil
        if lines.count > 2 {
            add(.length, .warning, L("{0} lines – at most 2 lines per subtitle are recommended.", lines.count), rewrapped)
        } else if longest > o.maxLineLength {
            add(.length, .warning, L("A line has {0} characters (max {1}).", longest, o.maxLineLength), rewrapped)
        }

        // Reading speed – fixed by showing the subtitle longer when there is room
        if let cps = cue.cps, let t = SRT.times(of: cue.timecode) {
            let chars = visible.replacingOccurrences(of: "\n", with: "").count
            let wanted = t.start + Int(Double(chars) / o.maxCPS * 1000)
            let fix = extendedEnd(start: t.start, wanted: wanted, currentEnd: t.end, nextStart: nextStart, o)
                .map { IssueFix.timecode(SRT.replacingEnd(in: cue.timecode, with: $0)) }
            if cps > o.maxCPS + 3 {
                issues.append(ReviewIssue(cueSeq: cue.seq, category: .readingSpeed, severity: .warning,
                                          message: L("{0} characters/second – too fast to read (target ≤ {1}).", formatNumber(cps), formatNumber(o.maxCPS, decimals: 0)),
                                          fix: fix))
            } else if cps > o.maxCPS {
                issues.append(ReviewIssue(cueSeq: cue.seq, category: .readingSpeed, severity: .suggestion,
                                          message: L("{0} characters/second – slightly over the target of {1}.", formatNumber(cps), formatNumber(o.maxCPS, decimals: 0)),
                                          fix: fix))
            }
        }

        // Spaces
        let tidy = lines
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        if tidy != text {
            add(.formatting, .suggestion, L("Superfluous spaces or empty lines."), tidy)
        }

        // Space before punctuation (French uses it before ! ? : ;)
        let french = o.language.code == "fr"
        let beforePattern = french ? #" +([,]|\.(?!\.))"# : #" +([,!?:;]|\.(?!\.))"#
        if matches(text, beforePattern) {
            add(.punctuation, .warning, L("Space before punctuation."),
                text.replacingOccurrences(of: beforePattern, with: "$1", options: .regularExpression))
        }

        // Missing space after punctuation. A colon inside a word is correct after
        // digits and capitals (Swedish/Finnish 1:a, 2:e, S:t, TV:n, USA:s) and before
        // short endings (d:o), so it is only flagged in cases like "sa:Hej".
        let afterPattern = #"([,;!?])(?=\p{L})"#
        let colonPattern = #"(?<![\p{N}\p{Lu}])(:)(?=\p{L})(?!\p{Ll}{1,3}\b)"#
        if matches(text, afterPattern) || matches(text, colonPattern) {
            let fixed = text
                .replacingOccurrences(of: afterPattern, with: "$1 ", options: .regularExpression)
                .replacingOccurrences(of: colonPattern, with: "$1 ", options: .regularExpression)
            add(.punctuation, .warning, L("Missing space after punctuation."), fixed)
        }

        // A line starting with a character that cannot begin a sentence (! & , …).
        // A leading ... / … (continuation), ¿ ¡, quotation marks and ♪ are correct.
        let leadingPattern = #"(?m)^((?:<[^>]+>)*[ \t]*(?:[-–][ \t]*)?)(?!\.\.\.)([!?,.;:&)\]}%]+)[ \t]*"#
        if let bad = firstMatch(text, leadingPattern, group: 2) {
            add(.punctuation, .warning, L("A line starts with “{0}”, which cannot begin a sentence.", bad),
                text.replacingOccurrences(of: leadingPattern, with: "$1", options: .regularExpression))
        }

        // Repeated words ("the the")
        let repeatPattern = #"(?i)\b(\p{L}+)\s+\1\b"#
        if let word = firstMatch(text, repeatPattern, group: 1) {
            add(.spelling, .warning, L("The word “{0}” appears twice in a row.", word),
                text.replacingOccurrences(of: repeatPattern, with: "$1", options: .regularExpression))
        }

        // Tags and brackets
        for tag in ["i", "b", "u"] {
            let open = count(text, "(?i)<\(tag)>"), close = count(text, "(?i)</\(tag)>")
            if open != close {
                // Add the missing closing tags at the end, or the missing opening tags at the start.
                let fixed = open > close
                    ? text + String(repeating: "</\(tag)>", count: open - close)
                    : String(repeating: "<\(tag)>", count: close - open) + text
                add(.formatting, .error, L("Unbalanced <{0}> tags ({1} opening, {2} closing).", tag, open, close), fixed)
            }
        }
        if text.filter({ $0 == "(" }).count != text.filter({ $0 == ")" }).count {
            add(.punctuation, .warning, L("The parentheses do not match."))
        }
        if text.filter({ $0 == "[" }).count != text.filter({ $0 == "]" }).count {
            add(.punctuation, .warning, L("The square brackets do not match."))
        }
        if text.filter({ $0 == "\"" }).count % 2 == 1 {
            add(.punctuation, .suggestion, L("Odd number of quotation marks – check that the quote is closed (it may continue in the next subtitle)."))
        }

        // Lower-case letter after a finished sentence in the previous subtitle
        if let previous, let last = stripTags(previous.text).trimmingCharacters(in: .whitespacesAndNewlines).last,
           ".!?".contains(last), !previous.text.hasSuffix("..."), !previous.text.hasSuffix("…") {
            if let idx = firstLetterIndex(text), text[idx].isLowercase, !startsWithEllipsis(text) {
                var fixed = text
                fixed.replaceSubrange(idx...idx, with: String(text[idx]).uppercased())
                add(.punctuation, .suggestion, L("Starts with a lower-case letter although the previous subtitle ended a sentence."), fixed)
            }
        }

        return issues
    }

    // MARK: - Consistency across the file

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
                               message: L("The file mostly uses “{0}” but here it says “{1}”.", useEllipsis ? "…" : "...", useEllipsis ? "..." : "…"),
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
                // Only replace the dash itself at the start of the line (after any tags).
                guard let r = line.range(of: s.rawValue) else { return line }
                var l = line
                l.replaceSubrange(r, with: major.rawValue)
                return l
            }
            if changed {
                issues.append(ReviewIssue(cueSeq: cue.seq, category: .consistency, severity: .suggestion,
                                          message: major.rawValue.hasSuffix(" ")
                                              ? L("Elsewhere in the file the dialogue dash is written “{0}” followed by a space.", major.rawValue.trimmingCharacters(in: .whitespaces))
                                              : L("Elsewhere in the file the dialogue dash is written “{0}” without a space.", major.rawValue),
                                          fix: .text(lines.joined(separator: "\n"))))
            }
        }
        return issues
    }

    // MARK: - Comparison with the original

    /// - Parameters:
    ///   - sources: original text per subtitle (seq) in the translation
    ///   - missing: original subtitles without a counterpart, with the subtitle they are closest to
    static func compare(_ cues: [ReviewCue], sources: [Int: String],
                        missing: [(seq: Int, text: String)], sourceLanguage: Language) -> [ReviewIssue] {
        var issues: [ReviewIssue] = []
        let lang = sourceLanguage.displayName

        for m in missing {
            let snippet = stripTags(m.text).replacingOccurrences(of: "\n", with: " ")
            issues.append(ReviewIssue(cueSeq: m.seq, category: .accuracy, severity: .warning,
                                      message: L("A subtitle in the original has no counterpart in the translation: “{0}”", snippet)))
        }

        for cue in cues {
            let visible = stripTags(cue.text).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let source = sources[cue.seq] else {
                if !visible.isEmpty {
                    issues.append(ReviewIssue(cueSeq: cue.seq, category: .accuracy, severity: .suggestion,
                                              message: L("Nothing in the original is shown at the same time as this subtitle.")))
                }
                continue
            }

            // Italic text (e.g. voices off screen, songs) should carry over.
            let srcItalic = isFullyItalic(source), dstItalic = cue.text.range(of: "(?i)<i>", options: .regularExpression) != nil
            if srcItalic && !dstItalic {
                issues.append(ReviewIssue(cueSeq: cue.seq, category: .formatting, severity: .suggestion,
                                          message: L("The original is italic (<i>) but the translation is not."),
                                          fix: visible.isEmpty ? nil : .text(wrapItalic(cue.text))))
            } else if !srcItalic && source.range(of: "(?i)<i>", options: .regularExpression) == nil && dstItalic {
                issues.append(ReviewIssue(cueSeq: cue.seq, category: .formatting, severity: .suggestion,
                                          message: L("The translation is italic but the original is not."),
                                          fix: .text(cue.text.replacingOccurrences(of: "(?i)</?i>", with: "", options: .regularExpression))))
            }

            // Numbers with at least two digits (years, amounts, times) should remain.
            let srcNumbers = numbers(in: source), dstNumbers = Set(numbers(in: cue.text))
            let lost = srcNumbers.filter { !dstNumbers.contains($0) }
            if !lost.isEmpty {
                issues.append(ReviewIssue(cueSeq: cue.seq, category: .accuracy, severity: .warning,
                                          message: L("Numbers in the original ({0}) are missing from the translation: {1}.", lang, lost.joined(separator: ", "))))
            }
        }
        return issues
    }

    private static func isFullyItalic(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t.hasPrefix("<i>") && t.hasSuffix("</i>")
    }

    private static func wrapItalic(_ s: String) -> String {
        let plain = s.replacingOccurrences(of: "(?i)</?i>", with: "", options: .regularExpression)
        return plain.components(separatedBy: "\n").map { "<i>\($0)</i>" }.joined(separator: "\n")
    }

    /// "1942", "3,50", "10:30" → digits without separators ("1942", "350", "1030").
    private static func numbers(in s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"\d+(?:[.,:]\d+)*"#) else { return [] }
        let text = stripTags(s)
        var seen = Set<String>()
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in
            guard let r = Range(m.range, in: text) else { return nil }
            let digits = text[r].filter(\.isNumber)
            guard digits.count >= 2, seen.insert(String(digits)).inserted else { return nil }
            return String(digits)
        }
    }

    // MARK: - Re-wrapping

    /// Splits a subtitle into at most two balanced lines of at most `maxLength`
    /// characters. Dialogue (lines starting with a dash) and text with tags other
    /// than one surrounding <i>…</i> are left alone. nil if it cannot be done.
    static func rewrap(_ text: String, maxLength: Int) -> String? {
        let lines = text.components(separatedBy: "\n")
        if lines.count > 1, lines.allSatisfy({ dashStyle(of: $0) != nil }) { return nil }

        var inner = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var italic = false
        let lower = inner.lowercased()
        let wholeItalic = lower.hasPrefix("<i>") && lower.hasSuffix("</i>") && count(inner, "(?i)</?i>") == 2
        let everyLineItalic = lines.allSatisfy {
            let l = $0.trimmingCharacters(in: .whitespaces).lowercased()
            return l.hasPrefix("<i>") && l.hasSuffix("</i>")
        }
        if wholeItalic || everyLineItalic {
            italic = true
            inner = inner.replacingOccurrences(of: "(?i)</?i>", with: "", options: .regularExpression)
        }
        guard !inner.contains("<") else { return nil }

        let words = inner.replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }
        let single = words.joined(separator: " ")

        var result: String?
        if single.count <= maxLength {
            result = single
        } else {
            // Try every split point; prefer balanced lines and a break after punctuation.
            var best: (score: Double, text: String)?
            for i in 1..<words.count {
                let a = words[..<i].joined(separator: " "), b = words[i...].joined(separator: " ")
                guard a.count <= maxLength, b.count <= maxLength else { continue }
                var score = Double(abs(a.count - b.count))
                if let last = a.last, ",.;:!?–".contains(last) { score -= 8 }
                if best == nil || score < best!.score { best = (score, a + "\n" + b) }
            }
            result = best?.text
        }
        guard var r = result else { return nil }
        if italic { r = r.components(separatedBy: "\n").map { "<i>\($0)</i>" }.joined(separator: "\n") }
        return r == text ? nil : r
    }

    // MARK: - Helpers

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

    /// The first letter outside tags.
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
