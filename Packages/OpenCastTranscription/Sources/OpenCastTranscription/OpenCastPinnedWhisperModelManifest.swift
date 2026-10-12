import Foundation

/// The Whisper model files, pinned to exact Hugging Face commits and
/// verified file by file against the hashes compiled in here. Model weights
/// come from argmaxinc/whisperkit-coreml and the tokenizer from
/// openai/whisper-large-v3; a moved branch or a swapped file fails the
/// install instead of changing the model.
enum OpenCastPinnedWhisperModelManifest {
    static let baseURL = URL(string: "https://huggingface.co")!
    static let whisperKitRevision = "0f63a7800b00dd0226abd051b906c246e1907482"
    static let tokenizerRevision = "06f233fe06e710322aca913c1bc4249a0d71fce1"

    private static let whisperKitPrefix =
        "/argmaxinc/whisperkit-coreml/resolve/\(whisperKitRevision)/openai_whisper-large-v3-v20240930_626MB"
    private static let tokenizerPrefix = "/openai/whisper-large-v3/resolve/\(tokenizerRevision)"

    static let current = RemoteWhisperModelManifest(
        schemaVersion: 1,
        generatedAt: "2026-07-12T00:00:00Z",
        models: [largeV3]
    )

    static let largeV3 = RemoteWhisperModel(
        modelID: "openai_whisper-large-v3-v20240930_626MB",
        version: "20240930_626MB-v1",
        modelFolder: "model",
        tokenizerFolder: "tokenizer",
        totalByteCount: 629482970,
        treeSHA256: "20a910bd8ea9f94a3e4438780f6e2f0aa3bbcd3fc1f8e99fccb2d64b68935603",
        files: [
            file(
                "model/AudioEncoder.mlmodelc/analytics/coremldata.bin",
                "\(whisperKitPrefix)/AudioEncoder.mlmodelc/analytics/coremldata.bin",
                byteCount: 243,
                sha256: "56793886ab1adb9ca8a4e335efbe8af6640f40d958ab2d29c3ad2d7d6f712e95",
                contentType: "application/octet-stream"
            ),
            file(
                "model/AudioEncoder.mlmodelc/coremldata.bin",
                "\(whisperKitPrefix)/AudioEncoder.mlmodelc/coremldata.bin",
                byteCount: 348,
                sha256: "ffa9eb76e8e9d9be75a4d527e5249e61d67fd43081c5aa110fd24efa6c8c5ea3",
                contentType: "application/octet-stream"
            ),
            file(
                "model/AudioEncoder.mlmodelc/metadata.json",
                "\(whisperKitPrefix)/AudioEncoder.mlmodelc/metadata.json",
                byteCount: 1922,
                sha256: "a87a3375afe79e88e27af30247e234e706b98679dedfd1b021a74f7ee108c669",
                contentType: "application/json; charset=utf-8"
            ),
            file(
                "model/AudioEncoder.mlmodelc/model.mil",
                "\(whisperKitPrefix)/AudioEncoder.mlmodelc/model.mil",
                byteCount: 934263,
                sha256: "3cec2580fb07b12a88087f0e1586c6ba2982980eb36499561e1ffca2b0950442",
                contentType: "application/octet-stream"
            ),
            file(
                "model/AudioEncoder.mlmodelc/weights/weight.bin",
                "\(whisperKitPrefix)/AudioEncoder.mlmodelc/weights/weight.bin",
                byteCount: 421968768,
                sha256: "e4740fa28ed65907af754af893dfce98473fafb84dd8d718ad346985fe7678c1",
                contentType: "application/octet-stream"
            ),
            file(
                "model/MelSpectrogram.mlmodelc/analytics/coremldata.bin",
                "\(whisperKitPrefix)/MelSpectrogram.mlmodelc/analytics/coremldata.bin",
                byteCount: 243,
                sha256: "c5be419f8622083ac7046306400643539f0e7577c843448c36defc090d41e7ce",
                contentType: "application/octet-stream"
            ),
            file(
                "model/MelSpectrogram.mlmodelc/coremldata.bin",
                "\(whisperKitPrefix)/MelSpectrogram.mlmodelc/coremldata.bin",
                byteCount: 329,
                sha256: "2bfc12cffc2e45e039c7a18f384f09adffb72c182fcd93f9413d405d1a6c1130",
                contentType: "application/octet-stream"
            ),
            file(
                "model/MelSpectrogram.mlmodelc/metadata.json",
                "\(whisperKitPrefix)/MelSpectrogram.mlmodelc/metadata.json",
                byteCount: 1850,
                sha256: "2bc552e09a6f124d9e6c178dd1a6979e010206acb26308b2224887c9dcbeb35f",
                contentType: "application/json; charset=utf-8"
            ),
            file(
                "model/MelSpectrogram.mlmodelc/model.mil",
                "\(whisperKitPrefix)/MelSpectrogram.mlmodelc/model.mil",
                byteCount: 10143,
                sha256: "c270b95b5f81d7f7d0b8a3e8f991d4e5812a37cad29349868a35b91f3a6a4463",
                contentType: "application/octet-stream"
            ),
            file(
                "model/MelSpectrogram.mlmodelc/weights/weight.bin",
                "\(whisperKitPrefix)/MelSpectrogram.mlmodelc/weights/weight.bin",
                byteCount: 373376,
                sha256: "009d9fb8f6b589accfa08cebf1c712ef07c3405229ce3cfb3a57ee033c9d8a49",
                contentType: "application/octet-stream"
            ),
            file(
                "model/TextDecoder.mlmodelc/analytics/coremldata.bin",
                "\(whisperKitPrefix)/TextDecoder.mlmodelc/analytics/coremldata.bin",
                byteCount: 243,
                sha256: "3913b8c9716b284a917cf3744f4d415f2a05e2b910594a14c6cc10092284d3f8",
                contentType: "application/octet-stream"
            ),
            file(
                "model/TextDecoder.mlmodelc/coremldata.bin",
                "\(whisperKitPrefix)/TextDecoder.mlmodelc/coremldata.bin",
                byteCount: 633,
                sha256: "3faabaf66930e66956d8291d0ff485fb382496e30a91a7185548b9b898ce90a9",
                contentType: "application/octet-stream"
            ),
            file(
                "model/TextDecoder.mlmodelc/metadata.json",
                "\(whisperKitPrefix)/TextDecoder.mlmodelc/metadata.json",
                byteCount: 4924,
                sha256: "994f6030d7b1a8be999940444c3cf5d6a57d40ddd4423cf1d1fc93520aa1b052",
                contentType: "application/json; charset=utf-8"
            ),
            file(
                "model/TextDecoder.mlmodelc/model.mil",
                "\(whisperKitPrefix)/TextDecoder.mlmodelc/model.mil",
                byteCount: 217177,
                sha256: "dbe833be9e64348c95b7fa598d0ae4309a91aedce4e82fa500a714b0e4b5d754",
                contentType: "application/octet-stream"
            ),
            file(
                "model/TextDecoder.mlmodelc/weights/weight.bin",
                "\(whisperKitPrefix)/TextDecoder.mlmodelc/weights/weight.bin",
                byteCount: 203199860,
                sha256: "d69700903d518ada33170ab77faaaf464496fb9ff65752c6d5a6109aa2fb02db",
                contentType: "application/octet-stream"
            ),
            file(
                "model/config.json",
                "\(whisperKitPrefix)/config.json",
                byteCount: 1149,
                sha256: "f01d83dd891791d6f12421c05d3ed8ebbe70866f10d6c9a7a7e80b558ce5a0f1",
                contentType: "application/json; charset=utf-8"
            ),
            file(
                "model/generation_config.json",
                "\(whisperKitPrefix)/generation_config.json",
                byteCount: 2767,
                sha256: "7fbb053a023be11fbeccd8421811610308143daa93d9617c52aab4a0fa1491c6",
                contentType: "application/json; charset=utf-8"
            ),
            file(
                "tokenizer/config.json",
                "\(tokenizerPrefix)/config.json",
                byteCount: 1272,
                sha256: "ad0e8d1e46f4d01f7861a21509e5d0f977d6cc1f367a370603c92541d819807b",
                contentType: "application/json; charset=utf-8"
            ),
            file(
                "tokenizer/tokenizer.json",
                "\(tokenizerPrefix)/tokenizer.json",
                byteCount: 2480617,
                sha256: "6d8cbd7cd0d8d5815e478dac67b85a26bbe77c1f5e0c6d76d1ce2abc0e5f21ca",
                contentType: "application/json; charset=utf-8"
            ),
            file(
                "tokenizer/tokenizer_config.json",
                "\(tokenizerPrefix)/tokenizer_config.json",
                byteCount: 282843,
                sha256: "844b642c73a91359722f47b35705f7174686df33d252695d8572cf9ac03a6389",
                contentType: "application/json; charset=utf-8"
            )
        ]
    )

    private static func file(
        _ path: String,
        _ urlPath: String,
        byteCount: Int64,
        sha256: String,
        contentType: String
    ) -> RemoteWhisperModelFile {
        RemoteWhisperModelFile(
            path: path,
            urlPath: urlPath,
            byteCount: byteCount,
            sha256: sha256,
            contentType: contentType
        )
    }
}
