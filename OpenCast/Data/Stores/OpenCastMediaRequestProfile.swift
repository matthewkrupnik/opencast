/// Shared media request profile for episode audio: exact bytes, no content
/// negotiation, and a stable, URL-free User-Agent. Matching headers are never
/// proof of matching bytes — only the hash is.
nonisolated enum OpenCastMediaRequestProfile {
    static let version = 2
    static let acceptEncoding = "identity"
    static let userAgent = "OpenCast-Media/2"
}
