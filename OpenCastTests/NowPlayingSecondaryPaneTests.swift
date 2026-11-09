import CoreGraphics
import Testing
@testable import OpenCast

/// The secondary pane's model: its three modes, the remembered selection
/// (scene storage holds the raw value), how each arrangement offers it, and
/// how an embedded destination behaves against its sheet.
@Suite("Now Playing secondary pane")
struct NowPlayingSecondaryPaneTests {
    static let bookBand = CGRect(x: 455.5, y: 0, width: 40, height: 669)
    static let laptopBand = CGRect(x: 0, y: 455.5, width: 669, height: 40)

    @Test("Three modes in picker order (the fork has no Up Next), stored under the scene key the plan names")
    func modes() {
        #expect(NowPlayingSecondaryPane.allCases == [.transcript, .chapters, .showNotes])
        #expect(NowPlayingSecondaryPane.allCases.map(\.title) == ["Transcript", "Chapters", "Show Notes"])
        #expect(NowPlayingSecondaryPane.sceneStorageKey == "nowPlayingSecondaryPane")
        #expect(NowPlayingSecondaryPane.pickerAccessibilityIdentifier == "Now Playing Secondary Pane")
    }

    @Test("A stored selection restores; a missing or unrecognized one is Transcript")
    func restoreAndDefault() {
        for pane in NowPlayingSecondaryPane.allCases {
            #expect(NowPlayingSecondaryPane(storedValue: pane.rawValue) == pane)
        }
        #expect(NowPlayingSecondaryPane(storedValue: nil) == .transcript)
        #expect(NowPlayingSecondaryPane(storedValue: "") == .transcript)
        #expect(NowPlayingSecondaryPane(storedValue: "lyrics") == .transcript)
        #expect(NowPlayingSecondaryPane(storedValue: "Chapters") == .transcript)
        #expect(NowPlayingSecondaryPane(storedValue: "upNext") == .transcript)
    }

    @Test("Chapters and Transcript sheets show a pane mode; Speed, Sleep, Private Notes and History do not")
    func sheetsThatShowAMode() {
        #expect(NowPlayingSecondaryPane(sheet: .history) == nil)
        #expect(NowPlayingSecondaryPane(sheet: .chapters) == .chapters)
        #expect(NowPlayingSecondaryPane(sheet: .transcript) == .transcript)
        #expect(NowPlayingSecondaryPane(sheet: .audio) == nil)
        #expect(NowPlayingSecondaryPane(sheet: .sleep) == nil)
        #expect(NowPlayingSecondaryPane(sheet: .notes) == nil)
    }

    static func presentation(
        _ arrangement: NowPlayingArrangement,
        _ selection: NowPlayingSecondaryPane,
        expanded: Bool = false,
        sheet: PlayerUtilitySheet? = nil
    ) -> NowPlayingSecondaryPanePresentation {
        NowPlayingSecondaryPanePresentation(
            arrangement: arrangement,
            selection: selection,
            isDisclosureExpanded: expanded,
            presentedSheet: sheet
        )
    }

    @Test("The selection is kept across split, single and compact; only how it is offered changes")
    func retentionAcrossArrangements() {
        let stored = NowPlayingSecondaryPane.chapters.rawValue
        let sequence: [NowPlayingArrangement] = [
            .split(band: Self.bookBand), .split(band: nil), .single(band: nil),
            .single(band: Self.laptopBand), .card, .split(band: Self.bookBand),
        ]
        let presentations = sequence.map { Self.presentation($0, NowPlayingSecondaryPane(storedValue: stored)) }
        #expect(presentations.allSatisfy { $0.selection == .chapters })
        #expect(presentations.map(\.style) == [.beside, .beside, .disclosure, .disclosure, .entryPointsOnly, .beside])
        #expect(presentations.map(\.content) == [.chapters, .chapters, nil, nil, nil, .chapters])
    }

    @Test("Beside the player the pane always shows its selection")
    func besideShowsTheSelection() {
        for pane in NowPlayingSecondaryPane.allCases {
            let shown = Self.presentation(.split(band: nil), pane)
            #expect(shown.showsPane)
            #expect(shown.content == pane)
            #expect(!shown.isExpanded)
        }
    }

    @Test("The disclosure row collapses and expands without touching the selection")
    func disclosureCollapse() {
        let collapsed = Self.presentation(.single(band: Self.laptopBand), .transcript)
        #expect(collapsed.style == .disclosure)
        #expect(!collapsed.isExpanded)
        #expect(!collapsed.showsPane)
        #expect(collapsed.content == nil)
        #expect(collapsed.selection == .transcript)

        let expanded = Self.presentation(.single(band: Self.laptopBand), .transcript, expanded: true)
        #expect(expanded.isExpanded)
        #expect(expanded.showsPane)
        #expect(expanded.content == .transcript)
        #expect(expanded.selection == .transcript)
    }

    @Test("Compact and non-foldable cards show no pane and no row, whatever the expansion state")
    func cardHasNoPane() {
        for expanded in [false, true] {
            let card = Self.presentation(.card, .showNotes, expanded: expanded)
            #expect(card.style == .entryPointsOnly)
            #expect(!card.showsPane)
            #expect(!card.isExpanded)
            #expect(card.content == nil)
            #expect(card.selection == .showNotes)
        }
    }

    @Test("While an open sheet shows the selected destination, the inline copy is suppressed; another sheet leaves it")
    func duplicateSuppression() {
        let duplicated = Self.presentation(.split(band: Self.bookBand), .transcript, sheet: .transcript)
        #expect(duplicated.showsPane)
        #expect(duplicated.content == nil)
        #expect(Self.presentation(.split(band: nil), .chapters, sheet: .chapters).content == nil)
        #expect(Self.presentation(.single(band: nil), .transcript, expanded: true, sheet: .transcript).content == nil)
        #expect(Self.presentation(.split(band: nil), .transcript, sheet: .chapters).content == .transcript)
        #expect(Self.presentation(.split(band: nil), .transcript, sheet: .audio).content == .transcript)
        #expect(Self.presentation(.split(band: nil), .showNotes, sheet: .notes).content == .showNotes)
        // The sheet closes: the selected pane returns.
        #expect(Self.presentation(.split(band: Self.bookBand), .transcript, sheet: nil).content == .transcript)
    }

    @Test("Embedded in the pane, a destination keeps the player and itself on screen; its sheet still closes")
    func embeddedBehaviour() {
        #expect(NowPlayingSecondaryHost.sheet.dismissesAfterSelection)
        #expect(NowPlayingSecondaryHost.sheet.showsDoneButton)
        #expect(!NowPlayingSecondaryHost.pane.dismissesAfterSelection)
        #expect(!NowPlayingSecondaryHost.pane.showsDoneButton)
    }
}
