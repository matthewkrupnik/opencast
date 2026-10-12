import Foundation
import OpenCastCore
import Testing
@testable import OpenCast

@MainActor
@Suite("Help content store")
struct HelpContentStoreTests {
    private static let futureUpdatedAt = "2099-01-01T00:00:00Z"

    @Test("The bundled document decodes with every help topic ID present")
    func bundledDocumentContainsEveryTopicID() throws {
        let store = HelpContentStore(currentBuild: 1_000)

        #expect(store.loadErrorMessage == nil)
        let ids = Set(store.document.topics.map(\.id))
        for id in HelpTopicID.all {
            #expect(ids.contains(id), "Missing bundled help topic \(id)")
        }
        #expect(store.visibleTopics.map(\.id) == store.document.topics.map(\.id))
    }

    @Test("Unknown block types decode as unsupported and leave the other blocks intact")
    func unknownBlockTypeDecodesAsUnsupported() throws {
        let data = Self.documentData(
            updatedAt: Self.futureUpdatedAt,
            blocks: """
            {"type":"heading","text":"Heading"},
            {"type":"video","url":"https://support.opencast.mobile/clip"},
            {"type":"paragraph","text":"Body with **bold**"}
            """
        )

        let document = try HelpDocument.decode(data)

        let blocks = try #require(document.topics.first).identifiedBlocks.map(\.block)
        #expect(blocks.count == 3)
        #expect(blocks[0] == .heading("Heading"))
        #expect(blocks[1] == .unsupported(type: "video"))
        guard case .paragraph(let text) = blocks[2] else {
            Issue.record("Expected a paragraph block, got \(blocks[2])")
            return
        }
        #expect(String(text.characters) == "Body with bold")
    }

    @Test("Topics above the current build are hidden but keep the document")
    func topicsAboveCurrentBuildAreHidden() throws {
        let document = try HelpDocument.decode(Self.documentData(updatedAt: Self.futureUpdatedAt, minAppBuild: 2_000))
        let store = HelpContentStore(document: document, currentBuild: 1_000)

        #expect(store.document.topics.contains { $0.id == "remote-topic" })
        #expect(store.topic("remote-topic") == nil)
        #expect(!store.visibleTopics.contains { $0.id == "remote-topic" })
    }

    private static func documentData(
        updatedAt: String,
        schemaVersion: Int = HelpDocument.supportedSchemaVersion,
        minAppBuild: Int? = nil,
        blocks: String = #"{"type":"paragraph","text":"Body"}"#
    ) -> Data {
        let minAppBuildField = minAppBuild.map { ",\"minAppBuild\":\($0)" } ?? ""
        return Data(
            """
            {"schemaVersion":\(schemaVersion),"updatedAt":"\(updatedAt)","topics":[{"id":"remote-topic","title":"Remote","symbol":"star","summary":"Remote summary","updatedAt":"\(updatedAt)"\(minAppBuildField),"related":[],"blocks":[\(blocks)]}]}
            """.utf8
        )
    }
}
