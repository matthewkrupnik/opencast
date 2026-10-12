import Foundation

nonisolated enum HelpContentError: LocalizedError, Equatable {
    case missingBundledDocument
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .missingBundledDocument:
            "The bundled help content is missing."
        case .unsupportedSchema(let version):
            "Help content schema \(version) is not supported by this version of opencast."
        }
    }
}
