import SwiftData
import SwiftUI

/// The Library: every playlist, then the shows, as a list or as a grid
/// of tiles. New playlists open through `onOpenPlaylist` once
/// their name prompt has dismissed, so their rules can be set.
struct LibraryView: View {
    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var sampleSubscriptionErrorMessage: String?
    @State private var isSubscribingSample = false
    @State private var namePromptRequest: PlaylistNamePromptRequest?
    @State private var pendingOpenPlaylistID: String?
    /// Bumped each time the Library reappears, so a drain that finished
    /// while something was pushed still shows its brief finished state.
    @State private var adDetectionIndicatorAppearance = 0

    let onAdd: () -> Void
    let onOpenPlaylist: (String) -> Void
    let onOpenAdDetectionQueue: () -> Void

    private var displaySettings: LibraryDisplaySettingsStore {
        appModel.libraryDisplaySettings
    }

    private var layout: LibraryLayout {
        displaySettings.layout.resolved(isRegularWidth: horizontalSizeClass == .regular)
    }

    var body: some View {
        // Sorting reads release dates, never progress, so playback cannot
        // reorder the Library.
        let subscriptions = displaySettings.sortOrder.sorted(
            appModel.library.subscriptions,
            latestReleaseDate: appModel.library.latestReleasedEpisodeDate(forPodcastID:)
        )

        content(subscriptions: subscriptions)
            .animation(reduceMotion ? nil : .default, value: appModel.library.state)
            .animation(reduceMotion ? nil : .default, value: subscriptions.map(\.feedURL))
            .animation(reduceMotion ? nil : .default, value: appModel.playlists.playlists.map(\.id))
            .animation(reduceMotion ? nil : .default, value: layout)
            .animation(reduceMotion ? nil : .default, value: appModel.library.lastRefreshWasOffline)
            .safeAreaInset(edge: .top, spacing: 0) {
                SettingsErrorBanner(message: displaySettings.lastErrorMessage)
            }
            .navigationTitle("Library")
            .toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)
            .refreshable {
                await appModel.library.refreshAll(modelContext: modelContext)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AdDetectionQueueToolbarStatus(onOpen: onOpenAdDetectionQueue)
                        .id(adDetectionIndicatorAppearance)
                }

                if !subscriptions.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        LibraryViewOptionsMenu(resolvedLayout: layout)
                    }
                    .visibilityPriority(.low)
                }

                ToolbarItem(placement: .topBarPinnedTrailing) {
                    Menu {
                        Button("Add Podcast", systemImage: "antenna.radiowaves.left.and.right", action: onAdd)
                        Button("New Playlist…", systemImage: "text.badge.plus", action: promptNewPlaylist)
                            .accessibilityIdentifier("New Playlist")
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .playlistNamePrompt($namePromptRequest, onCommit: commitPlaylistName)
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
            .onChange(of: scenePhase) { _, scenePhase in
                if scenePhase == .active {
                    appModel.library.advanceNewEpisodeReferenceDate()
                }
            }
    }

    @ViewBuilder
    private func content(subscriptions: [SubscriptionRecord]) -> some View {
        switch appModel.library.state {
        case .loading where subscriptions.isEmpty:
            List {
                ProgressView()
            }
        case .failed(let message) where subscriptions.isEmpty:
            List {
                ContentUnavailableView(
                    "Library Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            }
        default:
            if subscriptions.isEmpty {
                List {
                    // Playlists outlive their shows, so they stay while
                    // there are no shows.
                    playlistsSection

                    LibraryEmptyStateView(
                        syncActivity: appModel.syncStatus.libraryActivity,
                        isSubscribingSample: isSubscribingSample,
                        sampleSubscriptionErrorMessage: sampleSubscriptionErrorMessage,
                        onAdd: onAdd,
                        onSubscribeSample: subscribeToSample
                    )
                }
            } else if layout == .grid {
                LibrarySubscriptionGridView(
                    subscriptions: subscriptions,
                    showsNewEpisodeCount: displaySettings.showsNewEpisodeBadges
                ) { metrics in
                    if appModel.library.lastRefreshWasOffline {
                        LibraryOfflineNotice()
                    }
                    playlistsGridHeader(metrics: metrics)
                    if !appModel.playlists.playlists.isEmpty {
                        sectionTitle("Shows")
                    }
                }
                .transition(.opacity)
            } else {
                List {
                    offlineNoticeSection

                    playlistsSection

                    Section {
                        ForEach(subscriptions) { subscription in
                            LibrarySubscriptionRowView(
                                subscription: subscription,
                                showsNewEpisodeCount: displaySettings.showsNewEpisodeBadges
                            )
                        }
                    } header: {
                        Text("Shows")
                    }
                }
                .listSectionSpacing(12)
                .accessibilityIdentifier("Library List")
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var offlineNoticeSection: some View {
        if appModel.library.lastRefreshWasOffline {
            Section {
                LibraryOfflineNotice()
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
    }

    @ViewBuilder
    private var playlistsSection: some View {
        let playlists = appModel.playlists.playlists
        if !playlists.isEmpty {
            Section {
                ForEach(playlists) { summary in
                    PlaylistRowView(summary: summary)
                        .modifier(PlaylistCollectionActionsModifier(summary: summary, onRename: requestRename))
                }
            } header: {
                Text("Playlists")
            }
        }
    }

    /// The grid has no list sections, so the playlists sit above the shows
    /// as tiles in the same columns, under the same titles.
    @ViewBuilder
    private func playlistsGridHeader(metrics: LibraryGridMetrics) -> some View {
        let playlists = appModel.playlists.playlists
        if !playlists.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionTitle("Playlists")
                LazyVGrid(columns: metrics.columns, spacing: metrics.rowSpacing) {
                    ForEach(playlists) { summary in
                        LibraryPlaylistTileView(summary: summary, metrics: metrics)
                            .modifier(PlaylistCollectionActionsModifier(summary: summary, onRename: requestRename))
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.headline)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func promptNewPlaylist() {
        namePromptRequest = .create()
    }

    private func requestRename(_ summary: PlaylistSummary) {
        namePromptRequest = .rename(summary)
    }

    private func commitPlaylistName(_ request: PlaylistNamePromptRequest, name: String) {
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
    /// new playlist opens once the prompt's request has cleared. Both orders
    /// of the two state changes end here.
    private func openPendingPlaylistAfterPrompt() {
        guard namePromptRequest == nil, let playlistID = pendingOpenPlaylistID else {
            return
        }
        pendingOpenPlaylistID = nil
        onOpenPlaylist(playlistID)
    }

    private func subscribeToSample() {
        guard !isSubscribingSample else {
            return
        }

        Task {
            await performSampleSubscription()
        }
    }

    private func performSampleSubscription() async {
        sampleSubscriptionErrorMessage = nil
        isSubscribingSample = true
        defer {
            isSubscribingSample = false
        }

        do {
            try await appModel.library.subscribe(
                to: OpenCastConstants.thisAmericanLifeFeedURL,
                modelContext: modelContext
            )
        } catch is CancellationError {
        } catch {
            sampleSubscriptionErrorMessage = error.localizedDescription
        }
    }
}
