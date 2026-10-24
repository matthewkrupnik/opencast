import CoreGraphics
import SwiftUI
import Testing
@testable import OpenCast

@MainActor
@Suite("Artwork placeholder visual")
struct ArtworkPlaceholderVisualTests {
    @Test("Transparent loaded artwork leaves parent background visible")
    func transparentLoadedArtworkLeavesParentBackgroundVisible() throws {
        let renderer = ImageRenderer(
            content: ArtworkPlaceholderVisual(
                title: "Transparent",
                image: try artworkTestTransparentImage(width: 24, height: 24),
                preview: try artworkTestPreview()
            )
                .frame(width: 24, height: 24)
                .background(.white)
        )
        renderer.scale = 1
        renderer.isOpaque = true

        let renderedImage = try #require(renderer.uiImage)
        let pixel = try artworkTestPixel(in: renderedImage, x: 12, y: 12)

        #expect(pixel.red > 245)
        #expect(pixel.green > 245)
        #expect(pixel.blue > 245)
        #expect(pixel.alpha == 255)
    }

    @Test("Wide loaded artwork fills the square by default, cropping its sides")
    func wideLoadedArtworkFillsByDefault() throws {
        let renderer = ImageRenderer(
            content: ArtworkPlaceholderVisual(
                title: "Wide",
                image: try artworkTestWideSplitImage(width: 20, height: 10),
                preview: nil
            )
                .frame(width: 20, height: 20)
                .clipped()
                .background(.white)
        )
        renderer.scale = 1
        renderer.isOpaque = true

        let renderedImage = try #require(renderer.uiImage)
        // The top edge is image, not letterbox; the centre seam stays put.
        let topPixel = try artworkTestPixel(in: renderedImage, x: 15, y: 2)
        let leftPixel = try artworkTestPixel(in: renderedImage, x: 2, y: 10)
        let rightPixel = try artworkTestPixel(in: renderedImage, x: 17, y: 10)

        #expect(topPixel.red < 80)
        #expect(topPixel.blue > 200)
        #expect(leftPixel.red > 200)
        #expect(leftPixel.blue < 80)
        #expect(rightPixel.red < 80)
        #expect(rightPixel.blue > 200)
    }

    @Test("Wide loaded artwork keeps letterbox space in fit mode")
    func wideLoadedArtworkKeepsLetterboxSpaceInFitMode() throws {
        let renderer = ImageRenderer(
            content: ArtworkPlaceholderVisual(
                title: "Wide",
                image: try artworkTestWideSplitImage(width: 20, height: 10),
                preview: nil,
                contentMode: .fit
            )
                .frame(width: 20, height: 20)
                .background(.white)
        )
        renderer.scale = 1
        renderer.isOpaque = true

        let renderedImage = try #require(renderer.uiImage)
        let topPixel = try artworkTestPixel(in: renderedImage, x: 10, y: 2)
        let leftPixel = try artworkTestPixel(in: renderedImage, x: 2, y: 10)
        let rightPixel = try artworkTestPixel(in: renderedImage, x: 17, y: 10)

        #expect(topPixel.red > 245)
        #expect(topPixel.green > 245)
        #expect(topPixel.blue > 245)
        #expect(leftPixel.red > 200)
        #expect(leftPixel.blue < 80)
        #expect(rightPixel.red < 80)
        #expect(rightPixel.blue > 200)
    }

    @Test("Preview pixels render when decoded artwork is unavailable")
    func previewPixelsRenderWhenDecodedArtworkIsUnavailable() throws {
        let renderer = ImageRenderer(
            content: ArtworkPlaceholderVisual(title: "Preview", image: nil, preview: try artworkTestPreview())
                .frame(width: 24, height: 24)
        )
        renderer.scale = 1
        renderer.isOpaque = true

        let renderedImage = try #require(renderer.uiImage)
        let pixel = try artworkTestPixel(in: renderedImage, x: 12, y: 12)

        #expect(pixel.red > 220)
        #expect(pixel.green < 80)
        #expect(pixel.blue < 80)
        #expect(pixel.alpha == 255)
    }

    @Test("Wide preview fills the square by default, cropping its sides")
    func widePreviewFillsByDefault() throws {
        let renderer = ImageRenderer(
            content: ArtworkPlaceholderVisual(
                title: "Preview",
                image: nil,
                preview: try artworkTestWideSplitPreview(width: 8, height: 4)
            )
            .frame(width: 20, height: 20)
            .clipped()
            .background(.white)
        )
        renderer.scale = 1
        renderer.isOpaque = true

        let renderedImage = try #require(renderer.uiImage)
        let topPixel = try artworkTestPixel(in: renderedImage, x: 15, y: 2)
        let leftPixel = try artworkTestPixel(in: renderedImage, x: 2, y: 10)
        let rightPixel = try artworkTestPixel(in: renderedImage, x: 17, y: 10)

        #expect(topPixel.red < 80)
        #expect(topPixel.blue > 200)
        #expect(leftPixel.red > 200)
        #expect(leftPixel.blue < 80)
        #expect(rightPixel.red < 80)
        #expect(rightPixel.blue > 200)
    }

    @Test("Wide preview keeps letterbox space in fit mode instead of stretching")
    func widePreviewKeepsLetterboxSpaceInFitMode() throws {
        let renderer = ImageRenderer(
            content: ArtworkPlaceholderVisual(
                title: "Preview",
                image: nil,
                preview: try artworkTestWideSplitPreview(width: 8, height: 4),
                contentMode: .fit
            )
            .frame(width: 20, height: 20)
            .background(.white)
        )
        renderer.scale = 1
        renderer.isOpaque = true

        let renderedImage = try #require(renderer.uiImage)
        let topPixel = try artworkTestPixel(in: renderedImage, x: 10, y: 2)
        let leftPixel = try artworkTestPixel(in: renderedImage, x: 2, y: 10)
        let rightPixel = try artworkTestPixel(in: renderedImage, x: 17, y: 10)

        #expect(topPixel.red > 245)
        #expect(topPixel.green > 245)
        #expect(topPixel.blue > 245)
        #expect(leftPixel.red > 200)
        #expect(leftPixel.blue < 80)
        #expect(rightPixel.red < 80)
        #expect(rightPixel.blue > 200)
    }
}
