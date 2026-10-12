import Foundation
@testable import OpenCastTranscription
import Testing

@Suite("OpenCast transcription resources")
struct OpenCastTranscriptionResourceTests {
    @Test("No transcription models are bundled")
    func noTranscriptionModelsAreBundled() {
        #expect(Bundle.module.url(forResource: "Models", withExtension: nil) == nil)
        #expect(Bundle.module.url(forResource: "Tokenizers", withExtension: nil) == nil)
    }

    @Test("License resources remain bundled")
    func licenseResourcesRemainBundled() throws {
        let licenseURL = try #require(Bundle.module.url(
            forResource: "OpenAI-Whisper-LICENSE",
            withExtension: nil,
            subdirectory: "Licenses"
        ))

        #expect(FileManager.default.fileExists(atPath: licenseURL.path))
    }

    @Test("Supported model identities are remote models")
    func supportedModelIdentitiesAreRemoteModels() {
        #expect(OpenCastWhisperModel.allCases == [.largeV3])
        #expect(OpenCastWhisperModel.largeV3.defaultRemoteVersion == "20240930_626MB-v1")
    }

    @Test("Command-line model aliases parse consistently")
    func commandLineModelAliasesParseConsistently() {
        #expect(OpenCastWhisperModel(commandLineValue: "tiny") == nil)
        #expect(OpenCastWhisperModel(commandLineValue: "large") == .largeV3)
        #expect(OpenCastWhisperModel(commandLineValue: "large-v3") == .largeV3)
        #expect(OpenCastWhisperModel(commandLineValue: OpenCastWhisperModel.largeV3.rawValue) == .largeV3)
        #expect(OpenCastWhisperModel(commandLineValue: "medium") == nil)
    }
}
