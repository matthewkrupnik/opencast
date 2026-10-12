import Foundation
import Observation
import OpenCastCore

/// Help topics rendered natively from the versioned JSON document bundled
/// with the app.
@Observable
final class HelpContentStore {
    nonisolated static let bundledResourceName = "HelpContent"

    private(set) var document: HelpDocument
    /// Set only when the bundled document itself cannot be used; the Help hub
    /// shows it instead of an empty list.
    private(set) var loadErrorMessage: String?

    @ObservationIgnored private let currentBuild: Int

    init(
        bundle: Bundle = .main,
        currentBuild: Int = OpenCastAppVersion.buildNumber ?? 0
    ) {
        self.currentBuild = currentBuild
        do {
            document = try Self.loadBundledDocument(from: bundle)
        } catch {
            document = .empty
            loadErrorMessage = error.localizedDescription
        }
    }

    init(document: HelpDocument, currentBuild: Int) {
        self.document = document
        self.currentBuild = currentBuild
    }

    var visibleTopics: [HelpTopic] {
        document.topics.filter { ($0.minAppBuild ?? 0) <= currentBuild }
    }

    func topic(_ id: String) -> HelpTopic? {
        visibleTopics.first { $0.id == id }
    }

    private nonisolated static func loadBundledDocument(from bundle: Bundle) throws -> HelpDocument {
        guard let url = bundle.url(forResource: bundledResourceName, withExtension: "json") else {
            throw HelpContentError.missingBundledDocument
        }
        let document = try HelpDocument.decode(try Data(contentsOf: url))
        guard document.schemaVersion == HelpDocument.supportedSchemaVersion else {
            throw HelpContentError.unsupportedSchema(document.schemaVersion)
        }
        return document
    }
}
