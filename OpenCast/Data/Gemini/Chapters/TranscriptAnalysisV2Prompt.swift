import Foundation

/// Byte-exact port of the worker's `prompt.rs`: the pinned
/// `transcript_analysis_v2` rules, header and `[id | start-end] text` lines.
/// The rules text was validated at temperature 0 and is not robust to edits;
/// `TranscriptAnalysisV2Rules.txt` is pinned to the server source by tests.
nonisolated enum TranscriptAnalysisV2Prompt {
    static let policy = "transcript_analysis_v2"
    static let model = "gemini-3.5-flash"
    static let maxOutputTokens = 32_768
    static let thinkingEscalationSegmentCount = 1_399

    static let rules: String = {
        guard let url = Bundle.main.url(forResource: "TranscriptAnalysisV2Rules", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            preconditionFailure("TranscriptAnalysisV2Rules.txt is missing from the app bundle.")
        }
        return text
    }()

    static var responseSchema: [String: Any] {
            [
            "type": "object",
            "properties": [
                "chapters": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "title": ["type": "string"],
                            "start_segment_id": ["type": "integer"],
                            "end_segment_id": ["type": "integer"],
                            "confidence": ["type": "number"]
                        ],
                        "required": ["title", "start_segment_id", "end_segment_id", "confidence"]
                    ]
                ],
                "summary": [
                    "type": "object",
                    "properties": [
                        "summary": ["type": "string"],
                        "one_line_description": ["type": "string"],
                        "claims": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "text": ["type": "string"],
                                    "evidence_segment_id": ["type": "integer"]
                                ],
                                "required": ["text", "evidence_segment_id"]
                            ]
                        ]
                    ],
                    "required": ["summary", "one_line_description", "claims"]
                ]
            ],
            "required": ["chapters", "summary"]
        ]
    }

    /// Medium below the id-discipline threshold, high above it.
    static func thinkingLevel(forSegmentCount count: Int) -> String {
        count > thinkingEscalationSegmentCount ? "high" : "medium"
    }

    static func build(_ request: EpisodeTranscriptAnalysisAPIRequest, segments: [EpisodeTranscriptAnalysisAPISegment]) -> String {
        var text = rules
        text += "\n\n"
        text += "Policy: \(policy)\n"
        text += "Episode: \(titleOrID(request.episodeTitle, request.episodeID))\n"
        text += "Podcast: \(titleOrID(request.podcastTitle, request.podcastID))\n"
        text += "Language: \(request.transcript.languageCode)\n"
        text += "Audio duration: \(fixed3(request.transcript.audioDuration))s\n\n"
        text += "Segments:\n"
        for segment in segments {
            text += "[\(segment.id) | \(fixed3(segment.start))-\(fixed3(segment.end))] \(segment.text)\n"
        }
        return text
    }

    static func payload(prompt: String, thinkingLevel: String) throws -> Data {
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": [
                "temperature": 0,
                "topP": 0.95,
                "maxOutputTokens": maxOutputTokens,
                "responseMimeType": "application/json",
                "responseJsonSchema": responseSchema,
                "thinkingConfig": ["thinkingLevel": thinkingLevel]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    /// An absent or empty title falls back to the id, like the worker.
    private static func titleOrID(_ title: String?, _ id: String) -> String {
        guard let title, !title.isEmpty else {
            return id
        }
        return title
    }

    /// Rust's `{:.3}`: correctly rounded, `.` decimal separator.
    static func fixed3(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
