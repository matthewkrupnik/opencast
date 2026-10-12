import Foundation

/// The parts of a `generateContent` response the analysis clients read.
nonisolated struct GeminiResponse: Decodable, Sendable {
    struct Candidate: Decodable, Sendable {
        var content: Content?
        var finishReason: String?
    }

    struct Content: Decodable, Sendable {
        var parts: [Part]?
    }

    struct Part: Decodable, Sendable {
        var text: String?
        /// Thinking models return reasoning as `thought: true` parts ahead of
        /// the answer; those are never the model JSON.
        var thought: Bool?
    }

    struct UsageMetadata: Decodable, Sendable {
        var promptTokenCount: Int?
        var candidatesTokenCount: Int?
        var thoughtsTokenCount: Int?
        var totalTokenCount: Int?

        var total: Int {
            max(totalTokenCount ?? 0, (promptTokenCount ?? 0) + (candidatesTokenCount ?? 0) + (thoughtsTokenCount ?? 0))
        }
    }

    var candidates: [Candidate]?
    var usageMetadata: UsageMetadata?

    static let maximumAnswerByteCount = 100_000

    /// Strict extraction (ad analysis): exactly one candidate that finished
    /// with STOP and exactly one non-empty answer part. A truncated answer is
    /// never accepted, even when it happens to parse.
    func strictAnswerText() -> Result<String, GeminiParseIssue> {
        guard let candidates, candidates.count == 1 else {
            return .failure(.candidateCount)
        }
        guard candidates[0].finishReason == "STOP" else {
            return .failure(.incompleteGeneration)
        }
        let texts = answerParts(of: candidates[0])
        guard texts.count == 1, texts[0].utf8.count <= Self.maximumAnswerByteCount else {
            return .failure(.invalidAnswerText)
        }
        return .success(texts[0])
    }

    /// Lenient extraction (chapters): joins the answer parts of the first
    /// candidate; a non-STOP finish is a warning, not a failure.
    func lenientAnswerText() -> Result<(text: String, warning: String?), GeminiParseIssue> {
        guard let candidate = candidates?.first else {
            return .failure(.candidateCount)
        }
        let text = answerParts(of: candidate).joined()
        guard !text.isEmpty else {
            return .failure(.invalidAnswerText)
        }
        let warning = candidate.finishReason.flatMap { $0 == "STOP" ? nil : "gemini_finish_reason:\($0)" }
        return .success((text, warning))
    }

    private func answerParts(of candidate: Candidate) -> [String] {
        (candidate.content?.parts ?? []).compactMap { part in
            guard part.thought != true,
                  let text = part.text,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return nil
            }
            return text
        }
    }
}

nonisolated enum GeminiParseIssue: String, Error, Sendable {
    case malformedResponse = "malformed_response"
    case candidateCount = "candidate_count"
    case incompleteGeneration = "incomplete_generation"
    case invalidAnswerText = "invalid_answer_text"
    case malformedModelJSON = "malformed_model_json"
}

/// `{"error": {"code", "message", "status"}}`.
nonisolated struct GeminiErrorEnvelope: Decodable, Sendable {
    struct Body: Decodable, Sendable {
        var code: Int?
        var message: String?
        var status: String?
    }

    var error: Body
}
