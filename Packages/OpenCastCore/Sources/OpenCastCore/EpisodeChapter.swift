import Foundation

public struct EpisodeChapter: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var title: String
    public var startTime: TimeInterval
    public var endTime: TimeInterval?
    /// Chapter art: a feed document's `img`, or a file holding art embedded
    /// in the audio.
    public var imageURL: URL?
    /// A web page about the chapter's subject.
    public var linkURL: URL?
    /// Left out of chapter lists (`toc: false`); it still changes the art.
    public var isHidden: Bool

    public init(
        id: Int,
        title: String,
        startTime: TimeInterval,
        endTime: TimeInterval? = nil,
        imageURL: URL? = nil,
        linkURL: URL? = nil,
        isHidden: Bool = false
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.imageURL = imageURL
        self.linkURL = linkURL
        self.isHidden = isHidden
    }
}
