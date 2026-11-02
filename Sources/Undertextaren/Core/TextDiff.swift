import Foundation
import SwiftUI

/// Ordvis jämförelse av två texter – markerar vad som tas bort och läggs till.
enum TextDiff {
    private enum Op { case same(String), removed(String), added(String) }

    static func tokens(_ s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"\s+|[\p{L}\p{N}']+|[^\s\p{L}\p{N}]"#) else { return [s] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap {
            Range($0.range, in: s).map { String(s[$0]) }
        }
    }

    private static func ops(_ a: [String], _ b: [String]) -> [Op] {
        let n = a.count, m = b.count
        // LCS-tabell
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }
        var out: [Op] = []
        var i = 0, j = 0
        while i < n && j < m {
            if a[i] == b[j] { out.append(.same(a[i])); i += 1; j += 1 }
            else if lcs[i + 1][j] >= lcs[i][j + 1] { out.append(.removed(a[i])); i += 1 }
            else { out.append(.added(b[j])); j += 1 }
        }
        while i < n { out.append(.removed(a[i])); i += 1 }
        while j < m { out.append(.added(b[j])); j += 1 }
        return out
    }

    /// (gammal text med borttaget markerat, ny text med tillagt markerat)
    static func highlight(old: String, new: String) -> (old: AttributedString, new: AttributedString) {
        var o = AttributedString(), n = AttributedString()
        for op in ops(tokens(old), tokens(new)) {
            switch op {
            case .same(let t):
                o += AttributedString(t)
                n += AttributedString(t)
            case .removed(let t):
                var a = AttributedString(t)
                a.foregroundColor = Color.red
                a.backgroundColor = Color.red.opacity(0.15)
                a.strikethroughStyle = Text.LineStyle.single
                o += a
            case .added(let t):
                var a = AttributedString(t)
                a.foregroundColor = Color.green
                a.backgroundColor = Color.green.opacity(0.18)
                n += a
            }
        }
        return (o, n)
    }
}
