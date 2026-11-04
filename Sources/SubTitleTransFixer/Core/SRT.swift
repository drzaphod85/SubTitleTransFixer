import Foundation

/// SRT parser / serializer. Corresponds to parseSrt / serializeSrt /
/// cueDurationSeconds in the original translate-srt.mjs script.
enum SRT {
    static func parse(_ raw: String) -> [Cue] {
        let text = raw
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Split into blocks on blank lines
        var blocks: [[String]] = []
        var current: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !current.isEmpty { blocks.append(current); current = [] }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { blocks.append(current) }

        var cues: [Cue] = []
        for block in blocks {
            guard block.count >= 2 else { continue }
            let number = block[0].trimmingCharacters(in: .whitespaces)
            let timecode = block[1].trimmingCharacters(in: .whitespaces)
            guard timecode.contains("-->") else { continue } // skip broken blocks
            let body = block.dropFirst(2).joined(separator: "\n")
            cues.append(Cue(seq: cues.count + 1, number: number, timecode: timecode, original: body))
        }
        return cues
    }

    static func serialize(_ cues: [Cue]) -> String {
        cues.map { cue in
            let text = cue.translation.isEmpty ? cue.original : cue.translation
            return "\(cue.number)\n\(cue.timecode)\n\(text)"
        }
        .joined(separator: "\n\n") + "\n"
    }

    /// Seconds from "00:00:01,169 --> 00:00:02,736"
    static func duration(of timecode: String) -> Double? {
        let parts = timecode.components(separatedBy: "-->")
        guard parts.count == 2,
              let start = milliseconds(parts[0]),
              let end = milliseconds(parts[1]) else { return nil }
        return max(Double(end - start) / 1000, 0.001)
    }

    /// Start and end in milliseconds.
    static func times(of timecode: String) -> (start: Int, end: Int)? {
        let parts = timecode.components(separatedBy: "-->")
        guard parts.count == 2, let start = milliseconds(parts[0]), let end = milliseconds(parts[1]) else { return nil }
        return (start, end)
    }

    /// 3723004 → "01:02:03,004"
    static func format(ms: Int) -> String {
        let v = max(ms, 0)
        return String(format: "%02d:%02d:%02d,%03d", v / 3_600_000, (v / 60_000) % 60, (v / 1000) % 60, v % 1000)
    }

    /// Replaces the end time but keeps the start time and any position tags.
    static func replacingEnd(in timecode: String, with endMs: Int) -> String {
        let parts = timecode.components(separatedBy: "-->")
        guard parts.count == 2 else { return timecode }
        let after = parts[1].trimmingCharacters(in: .whitespaces)
        let tokens = after.split(separator: " ", maxSplits: 1)
        let rest = tokens.count > 1 ? " " + tokens[1] : ""
        return parts[0].trimmingCharacters(in: .whitespaces) + " --> " + format(ms: endMs) + rest
    }

    private static func milliseconds(_ s: String) -> Int? {
        // Also tolerates position tags after the end time ("... X1:100 ...")
        let token = s.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ").first ?? ""
        let cleaned = token.replacingOccurrences(of: ".", with: ",")
        let hms = cleaned.components(separatedBy: ",")
        guard hms.count == 2, let ms = Int(hms[1]) else { return nil }
        let t = hms[0].components(separatedBy: ":").compactMap { Int($0) }
        guard t.count == 3 else { return nil }
        return ((t[0] * 60 + t[1]) * 60 + t[2]) * 1000 + ms
    }

    /// Replaces the language code in the file name: "Show_en.srt" → "Show_sv.srt",
    /// "Show.eng.srt" → "Show.de.srt", otherwise "Show.srt" → "Show.sv.srt".
    static func outputName(for inputName: String, source: Language?, target: Language) -> String {
        let ns = inputName as NSString
        let ext = ns.pathExtension.isEmpty ? "srt" : ns.pathExtension
        let base = ns.deletingPathExtension
        let lower = base.lowercased()
        // Try the source language's codes first, then every known language.
        let candidates = [source?.fileTokens ?? []] + Language.all.map(\.fileTokens)
        for tokens in candidates {
            for token in tokens.sorted(by: { $0.count > $1.count }) {
                for sep in ["_", ".", "-"] where lower.hasSuffix(sep + token) {
                    return String(base.dropLast(token.count + 1)) + sep + target.code + "." + ext
                }
            }
        }
        return base + "." + target.code + "." + ext
    }

    /// File name without extension and language code, in lower case.
    static func baseName(_ fileName: String) -> String {
        var base = (fileName as NSString).deletingPathExtension.lowercased()
        let tokens = ["forced", "sdh", "hi", "cc"] + Language.all.flatMap { [$0.code] + $0.aliases }
        var changed = true
        while changed {
            changed = false
            for t in tokens {
                for sep in ["_", ".", "-", " "] where base.hasSuffix(sep + t) {
                    base = String(base.dropLast(t.count + 1))
                    changed = true
                }
            }
        }
        return base
    }

    /// Reads text, falling back to common encodings.
    static func readText(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        for enc in [String.Encoding.utf8, .utf16, .windowsCP1252, .isoLatin1] {
            if let s = String(data: data, encoding: enc) { return s }
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
}

// MARK: - Guess the title from the file name and match against saved profiles

struct TitleGuess: Hashable {
    var title: String
    var episode: String?
}

enum TitleMatcher {
    private static let junkTokens: Set<String> = [
        "720p", "1080p", "2160p", "4k", "uhd", "hdr", "web", "webrip", "web-dl", "webdl",
        "bluray", "brrip", "bdrip", "hdtv", "dvdrip", "x264", "x265", "h264", "h265",
        "hevc", "aac", "ac3", "dts", "proper", "repack", "subs", "sub", "itunes", "amzn",
        "nf", "dsnp", "hmax", "atvp", "bbc", "itv",
    ]
    /// Language codes and other markers that may appear at the end of a file name.
    private static let languageSuffixes: [String] =
        ["forced", "sdh", "hi", "cc"] + Language.all.flatMap { [$0.code] + $0.aliases }

    static func guess(fromFileName fileName: String) -> TitleGuess {
        var base = (fileName as NSString).deletingPathExtension

        // Remove language suffixes: _en, .en, -eng, .English, .sdh …
        var changed = true
        while changed {
            changed = false
            for suffix in languageSuffixes {
                for sep in ["_", ".", "-", " "] where base.lowercased().hasSuffix(sep + suffix) {
                    base = String(base.dropLast(suffix.count + 1))
                    changed = true
                }
            }
        }

        let spaced = base
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        let tokens = spaced.split(separator: " ").map(String.init)

        var titleTokens: [String] = []
        var episode: String?
        for (i, token) in tokens.enumerated() {
            let lower = token.lowercased()
            if let ep = episodeCode(in: token) { episode = ep; break }
            if junkTokens.contains(lower) { break }
            let stripped = lower.trimmingCharacters(in: CharacterSet(charactersIn: "()[]"))
            if i > 0, stripped.count == 4, let y = Int(stripped), (1920...2100).contains(y) { break }
            if token.allSatisfy({ $0 == "-" }) { continue }
            titleTokens.append(token)
        }
        let title = titleTokens.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -"))
        return TitleGuess(title: title.isEmpty ? base : title, episode: episode)
    }

    /// Finds S02E01 / s2e1 / 2x01 and normalizes it to S02E01.
    static func episodeCode(in token: String) -> String? {
        let patterns = [#"^[Ss](\d{1,2})[Ee](\d{1,3})"#, #"^(\d{1,2})[xX](\d{2,3})$"#]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            let range = NSRange(token.startIndex..., in: token)
            if let m = re.firstMatch(in: token, range: range),
               let s = Range(m.range(at: 1), in: token), let e = Range(m.range(at: 2), in: token),
               let season = Int(token[s]), let ep = Int(token[e]) {
                return String(format: "S%02dE%02d", season, ep)
            }
        }
        return nil
    }

    static func normalize(_ s: String) -> String {
        var t = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
        t = String(t.map { $0.isLetter || $0.isNumber ? $0 : " " })
        var words = t.split(separator: " ").map(String.init)
        if words.first == "the" && words.count > 1 { words.removeFirst() }
        return words.joined(separator: " ")
    }

    /// 0…1 – how well `query` matches a name.
    static func score(_ query: String, against name: String) -> Double {
        let q = normalize(query), n = normalize(name)
        guard !q.isEmpty, !n.isEmpty else { return 0 }
        if q == n { return 1 }
        if q.replacingOccurrences(of: " ", with: "") == n.replacingOccurrences(of: " ", with: "") { return 0.98 }
        if min(q.count, n.count) >= 5, q.contains(n) || n.contains(q) { return 0.9 }
        let dist = levenshtein(Array(q), Array(n))
        return 1 - Double(dist) / Double(max(q.count, n.count))
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }
}
