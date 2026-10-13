import SwiftData
import SwiftUI

/// Every playlist, as a grid of covers or a list of rows. It follows the
/// Library's stored layout, except that Automatic always means the grid
/// here: covers are how playlists are told apart. A new playlist opens
/// through `onOpenPlaylist` once its name prompt has dismissed, so its rule
/// can be set.
struct PlaylistsView: View {
    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.modelContext) private var modelContext
    @State private var namePromptRequest: PlaylistNamePromptRequest?
    @State private var pendingOpenPlaylistID: String?
    @State private var selectionFeedbackTrigger = 0
    /// Bumped each time the collection reappears, so a drain that finished
    /// while a playlist was pushed still shows its brief finished state.
    @State private var adDetectionIndicatorAppearance = 0

    var onOpenPlaylist: (String) -> Void = { _ in }
    /// Shows the ad-detection queue indicator; only the Playlists tab root
    /// passes it, so the queue has one entry point.
    var onOpenAdDetectionQueue: (() -> Void)?

    private var layout: LibraryLayout {
        appModel.playlistDisplaySettings.layout.resolved(isRegularWidth: horizontalSizeClass == .regular)
    }

    var body: some View {
        let playlists = appModel.playlists.playlists

        content(playlists: playlists)
            .animation(reduceMotion ? nil : .default, value: playlists.map(\.id))
            .animation(reduceMotion ? nil : .default, value: layout)
            .safeAreaInset(edge: .top, spacing: 0) {
                SettingsErrorBanner(message: appModel.playlistDisplaySettings.lastErrorMessage)
            }
            .navigationTitle("Playlists")
            .navigationBarTitleDisplayMode(.large)
            .toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)
            .toolbar {
                if let onOpenAdDetectionQueue {
                    ToolbarItem(placement: .topBarLeading) {
                        AdDetectionQueueToolbarStatus(onOpen: onOpenAdDetectionQueue)
                            .id(adDetectionIndicatorAppearance)
                    }
                }

                if !playlists.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        optionsMenu
                    }
                    .visibilityPriority(.low)
                }

                ToolbarItem(placement: .topBarPinnedTrailing) {
                    Button("New Playlist…", systemImage: "plus", action: promptNewPlaylist)
                        .accessibilityIdentifier("New Playlist")
                }
            }
            .playlistNamePrompt($namePromptRequest, onCommit: commitName)
            .onChange(of: namePromptRequest) {
                openPendingPlaylistAfterPrompt()
            }
            .onChange(of: pendingOpenPlaylistID) {
                openPendingPlaylistAfterPrompt()
            }
            .onAppear {
                appModel.library.advanceNewEpisodeReferenceDate()
                adDetectionIndicatorAppearance += 1
            }
    }

    @ViewBuilder
    private func content(playlists: [PlaylistSummary]) -> some View {
        if playlists.isEmpty {
            ContentUnavailableView {
                Label("No Playlists", systemImage: "music.note.list")
            } description: {
                Text("A playlist gathers episodes from the shows you choose, show by show in your order.")
            } actions: {
                Button("New Playlist…", action: promptNewPlaylist)
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("Playlists Empty New Playlist")
            }
        } else if layout == .grid {
            grid(playlists: playlists)
                .transition(.opacity)
        } else {
            List {
                ForEach(playlists) { summary in
                    PlaylistRowView(summary: summary)
                        .modifier(
                            PlaylistCollectionActionsModifier(
                                summary: summary,
                                supportsSwipeActions: true,
                                onRename: requestRename
                            )
                        )
                }
            }
            .accessibilityIdentifier("Playlists List")
            .transition(.opacity)
        }
    }

    private func grid(playlists: [PlaylistSummary]) -> some View {
        // Reads the width in the same layout pass, so the first frame
        // already has its final column count.
        GeometryReader { proxy in
            let metrics = LibraryGridMetrics.resolve(
                containerWidth: proxy.size.width,
                isCompact: horizontalSizeClass == .compact || verticalSizeClass == .compact,
                isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
            )

            ScrollView {
                LazyVGrid(columns: metrics.columns, spacing: metrics.rowSpacing) {
                    ForEach(playlists) { summary in
                        PlaylistTileView(summary: summary, metrics: metrics)
                            .modifier(
                                PlaylistCollectionActionsModifier(
                                    summary: summary,
                                    supportsSwipeActions: false,
                                    onRename: requestRename
                                )
                            )
                    }
                }
                .padding(.vertical, 8)
            }
            .accessibilityIdentifier("Playlists Grid")
            .contentMargins(.horizontal, metrics.horizontalMargin, for: .scrollContent)
            .contentMargins(.bottom, 72, for: .scrollContent)
        }
    }

    private var optionsMenu: some View {
        LayoutPickerMenu(layout: layoutBinding, resolvedLayout: layout, title: "Playlist Options") {
            Picker(selection: sortOrderBinding) {
                ForEach(PlaylistSortOrder.allCases) { sortOrder in
                    Text(sortOrder.title)
                        .tag(sortOrder)
                }
            } label: {
                Label("Sort By", systemImage: "arrow.up.arrow.down")
            }
            .pickerStyle(.menu)
        }
        .accessibilityIdentifier("Playlist Options")
        .sensoryFeedback(.selection, trigger: selectionFeedbackTrigger)
    }

    private var layoutBinding: Binding<LibraryLayoutPreference> {
        Binding {
            appModel.playlistDisplaySettings.layout
        } set: { layout in
            guard layout != appModel.playlistDisplaySettings.layout,
                  appModel.playlistDisplaySettings.setLayout(layout, modelContext: modelContext)
            else {
                return
            }
            selectionFeedbackTrigger += 1
        }
    }

    private var sortOrderBinding: Binding<PlaylistSortOrder> {
        Binding {
            appModel.playlistDisplaySettings.sortOrder
        } set: { sortOrder in
            guard sortOrder != appModel.playlistDisplaySettings.sortOrder,
                  appModel.setPlaylistSortOrder(sortOrder, modelContext: modelContext)
            else {
                return
            }
            selectionFeedbackTrigger += 1
        }
    }

    private func promptNewPlaylist() {
        namePromptRequest = PlaylistNamePromptRequest.create()
    }

    private func requestRename(_ summary: PlaylistSummary) {
        namePromptRequest = PlaylistNamePromptRequest.rename(summary)
    }

    private func commitName(_ request: PlaylistNamePromptRequest, name: String) {
        switch request.kind {
        case .create:
            let summary = appModel.performPlaylistMutation {
                appModel.playlists.create(name: name, modelContext: modelContext)
            }
            pendingOpenPlaylistID = summary?.playlistID
        case .rename(let playlistID):
            appModel.renamePlaylist(playlistID, to: name, modelContext: modelContext)
        }
    }

    /// Pushing from the alert's own action would race its dismissal, so the
    /// new playlist opens once the prompt's request has cleared. Both
    /// orders of the two state changes end here.
    private func openPendingPlaylistAfterPrompt() {
        guard namePromptRequest == nil, let playlistID = pendingOpenPlaylistID else {
            return
        }
        pendingOpenPlaylistID = nil
        onOpenPlaylist(playlistID)
    }
}
