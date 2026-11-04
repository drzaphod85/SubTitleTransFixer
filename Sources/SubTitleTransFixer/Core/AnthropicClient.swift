import Foundation

/// Thin client for the Claude Messages API (raw HTTP – there is no official
/// Swift SDK). Corresponds to callApi() in translate-srt.mjs, with retry/backoff.
struct AnthropicClient: Sendable {
    let apiKey: String
    let model: String
    /// "low" | "medium" | "high" | "xhigh" | "max", or empty for the model's default.
    let effort: String
    /// Let the API re-run a declined request on another model (server-side fallback).
    let useFallbacks: Bool

    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2023-06-01"

    struct APIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct RetryableError: Error { let description: String }

    /// Models that accept `fallbacks: "default"`.
    static func supportsDefaultFallback(_ model: String) -> Bool {
        ["claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5", "claude-fable-5-1", "claude-fable-5"].contains(model)
    }

    /// Models that support the web_search_20260209 tool.
    static func supportsWebSearch(_ model: String) -> Bool {
        model.hasPrefix("claude-opus") || model.hasPrefix("claude-sonnet") || model.hasPrefix("claude-fable")
    }

    /// Sends a prompt and returns the text of the response.
    /// - Parameter webSearch: enables Claude's web search (used when creating prompts).
    func complete(system: String, user: String, maxTokens: Int = 16000, webSearch: Bool = false) async throws -> String {
        var messages: [[String: Any]] = [["role": "user", "content": user]]
        var collected = ""

        // Server tools may pause the turn (pause_turn) – then we send the response
        // back and let Claude continue.
        for _ in 0..<6 {
            var body: [String: Any] = [
                "model": model,
                "max_tokens": maxTokens,
                "system": [["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]],
                "messages": messages,
            ]
            if !effort.isEmpty { body["output_config"] = ["effort": effort] }
            if webSearch && Self.supportsWebSearch(model) {
                body["tools"] = [["type": "web_search_20260209", "name": "web_search", "max_uses": 5]]
            }
            var betas: [String] = []
            if useFallbacks && Self.supportsDefaultFallback(model) {
                body["fallbacks"] = "default"
                betas.append("server-side-fallback-2026-07-01")
            }

            let json = try await send(body: body, betas: betas)
            let content = json["content"] as? [[String: Any]] ?? []
            let text = content
                .filter { ($0["type"] as? String) == "text" }
                .compactMap { $0["text"] as? String }
                .joined()
            let stop = json["stop_reason"] as? String

            switch stop {
            case "refusal":
                let details = json["stop_details"] as? [String: Any]
                let why = details?["explanation"] as? String ?? L("no explanation given")
                throw APIError(message: L("Claude declined the request ({0}).", why))
            case "pause_turn":
                collected += text
                messages.append(["role": "assistant", "content": content])
                continue
            case "max_tokens":
                throw APIError(message: L("The response was too long and was cut off. Reduce the batch size in Settings."))
            default:
                return collected + text
            }
        }
        return collected
    }

    private func send(body: [String: Any], betas: [String]) async throws -> [String: Any] {
        let payload = try JSONSerialization.data(withJSONObject: body)
        var attempt = 1
        while true {
            do {
                var req = URLRequest(url: Self.endpoint)
                req.httpMethod = "POST"
                req.timeoutInterval = 600
                req.setValue("application/json", forHTTPHeaderField: "content-type")
                req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                req.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
                if !betas.isEmpty { req.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta") }
                req.httpBody = payload

                let (data, response) = try await URLSession.shared.data(for: req)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0

                if status == 429 || status >= 500 {
                    throw RetryableError(description: "HTTP \(status)")
                }
                guard (200..<300).contains(status) else {
                    throw APIError(message: "HTTP \(status): \(Self.errorMessage(from: data))")
                }
                guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw APIError(message: L("Unexpected response from the API."))
                }
                return obj
            } catch let error as RetryableError where attempt <= 5 {
                try await backoff(attempt, reason: error.description)
            } catch let error as URLError where attempt <= 5 && error.code != .cancelled {
                try await backoff(attempt, reason: error.localizedDescription)
            }
            attempt += 1
        }
    }

    private func backoff(_ attempt: Int, reason: String) async throws {
        let ms = min(Int(pow(2.0, Double(attempt))) * 500, 15_000)
        print("⚠ attempt \(attempt) failed (\(reason)), waiting \(ms) ms…")
        try await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
    }

    private static func errorMessage(from data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? [String: Any],
           let msg = err["message"] as? String {
            return msg
        }
        return String(data: data, encoding: .utf8) ?? L("unknown error")
    }
}

// MARK: - JSON from model responses

enum JSONExtract {
    /// Extracts JSON from the response (tolerates ``` fences, preamble and broken escapes).
    static func value(from text: String) throws -> Any {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```JSON", with: "")
                .replacingOccurrences(of: "```", with: "")
        }
        let objStart = t.firstIndex(of: "{")
        let arrStart = t.firstIndex(of: "[")
        // Pick whichever comes first – object or array
        if let o = objStart, arrStart == nil || o < arrStart!, let end = t.lastIndex(of: "}") , end > o {
            t = String(t[o...end])
        } else if let a = arrStart, let end = t.lastIndex(of: "]"), end > a {
            t = String(t[a...end])
        }

        if let v = try? JSONSerialization.jsonObject(with: Data(t.utf8), options: [.fragmentsAllowed]) {
            return v
        }
        // Remove backslashes that don't start a valid JSON escape (e.g. \')
        let re = try NSRegularExpression(pattern: #"\\(?!["\\/bfnrtu])"#)
        let repaired = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
        do {
            return try JSONSerialization.jsonObject(with: Data(repaired.utf8), options: [.fragmentsAllowed])
        } catch {
            throw AnthropicClient.APIError(message: L("Could not parse the JSON in Claude's response."))
        }
    }

    static func int(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func string(_ any: Any?) -> String {
        if let s = any as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = any as? NSNumber { return n.stringValue }
        return ""
    }

    static func strings(_ any: Any?) -> [String] {
        (any as? [Any] ?? []).map { string($0) }.filter { !$0.isEmpty }
    }
}
