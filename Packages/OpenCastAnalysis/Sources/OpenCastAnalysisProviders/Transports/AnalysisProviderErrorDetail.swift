import Foundation
import OpenCastAnalysis

/// What a provider's non-2xx body said, for troubleshooting a failed send.
/// `errorStatus` and `reasons` are closed values (`unknown` for anything
/// outside the known set). `message` is the provider's own text: kept only
/// when it passes the key check, collapsed to one line and capped, and never
/// logged or exported.
public struct AnalysisProviderErrorDetail: Sendable, Hashable, Codable {
    public static let maximumMessageLength = 300

    /// Gemini's `error.status` (`INVALID_ARGUMENT`), OpenAI's `error.type`.
    public var errorStatus: String?
    /// Gemini's `error.details[].reason`, OpenAI's `error.code` and `error.param`.
    public var reasons: [String]
    public var message: String?

    public init(errorStatus: String?, reasons: [String], message: String?) {
        self.errorStatus = errorStatus
        self.reasons = reasons
        self.message = message
    }

    enum CodingKeys: String, CodingKey {
        case errorStatus = "error_status"
        case reasons
        case message
    }

    /// The detail of an error body, or `nil` when it has no readable `error`.
    static func read(_ body: String, provider: AnalysisProvider, verifier: SecretVerifier) -> Self? {
        guard !ProviderJSON.refusesBody(body), let error = ProviderJSON.parse(body)?["error"] else { return nil }
        func known(_ value: JSONValue?, in set: Set<String>) -> String? {
            guard let value, value != .null else { return nil }
            guard let string = value.stringValue, set.contains(string) else { return "unknown" }
            return string
        }
        let errorStatus: String?
        let reasons: [String]
        switch provider {
        case .google:
            errorStatus = known(error["status"], in: AnalysisExchangeRecord.geminiStatuses)
            reasons = (error["details"]?.arrayValue ?? []).compactMap {
                known($0["reason"], in: AnalysisExchangeRecord.geminiReasons)
            }
        case .openai:
            errorStatus = known(error["type"], in: AnalysisExchangeRecord.openAITypes)
            reasons = [
                known(error["code"], in: AnalysisExchangeRecord.openAICodes),
                known(error["param"], in: AnalysisExchangeRecord.openAIParams).map { "param.\($0)" },
            ].compactMap { $0 }
        }
        let message = error["message"]?.stringValue.flatMap { Self.message($0, verifier: verifier) }
        guard errorStatus != nil || !reasons.isEmpty || message != nil else { return nil }
        return Self(errorStatus: errorStatus, reasons: reasons, message: message)
    }

    /// One line of at most ``maximumMessageLength`` characters, or `nil`
    /// when empty or when the text fails the key check.
    static func message(_ text: String, verifier: SecretVerifier) -> String? {
        let line = text.split(whereSeparator: { $0.isNewline || $0 == "\t" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty,
              verifier.verifyRecordedText(text) == .clean,
              verifier.verifyAppText(line) == .clean
        else {
            return nil
        }
        guard line.count > maximumMessageLength else { return line }
        return String(line.prefix(maximumMessageLength - 1)) + "…"
    }
}
