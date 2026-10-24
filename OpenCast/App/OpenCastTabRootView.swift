import SwiftUI

struct OpenCastTabRootView: View {
    @Environment(OpenCastAppModel.self) private var appModel

    @State private var isSearchPresented = false

    @Binding var selectedTab: AppSection
    @Binding var navigationPaths: AppNavigationPaths
    let onAdd: () -> Void
    let onPresentNowPlaying: () -> Void

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(AppSection.library.title, systemImage: AppSection.library.systemImage, value: AppSection.library) {
                NavigationStack(path: $navigationPaths[.library]) {
                    LibraryView(
                        onAdd: onAdd,
                        onOpenPlaylist: openPlaylist(on: .library),
                        onOpenAdDetectionQueue: {
                            navigationPaths[.library].append(.adDetectionQueue)
                        }
                    )
                    .sectionShortcutsToolbar(selectedTab: $selectedTab)
                    .withOpenCastDestinations(
                        onOpenEpisode: openEpisode(on: .library),
                        onOpenPlaylist: openPlaylist(on: .library)
                    )
                }
            }

            Tab(
                AppSection.downloads.title,
                systemImage: AppSection.downloads.systemImage,
                value: AppSection.downloads
            ) {
                NavigationStack(path: $navigationPaths[.downloads]) {
                    DownloadsView(
                        onOpenEpisode: openEpisode(on: .downloads)
                    )
                    .withOpenCastDestinations(
                        onOpenEpisode: openEpisode(on: .downloads)
                    )
                }
            }
            .badge(appModel.downloads.activeDownloadCount)

            Tab(AppSection.settings.title, systemImage: AppSection.settings.systemImage, value: AppSection.settings) {
                NavigationStack(path: $navigationPaths[.settings]) {
                    SettingsView()
                        .withOpenCastDestinations()
                }
            }

            Tab(
                AppSection.search.title,
                systemImage: AppSection.search.systemImage,
                value: AppSection.search,
                role: .search
            ) {
                NavigationStack(path: $navigationPaths[.search]) {
                    SearchView(
                        directoryService: appModel.podcastDirectoryService,
                        directoryResolver: appModel.podcastDirectoryResolver,
                        isSearchPresented: $isSearchPresented,
                        onOpenEpisode: openEpisode(on: .search),
                        onOpenPodcast: { feedURL in
                            navigationPaths[.search].append(.podcastDetail(feedURL: feedURL))
                        }
                    )
                    .withOpenCastDestinations(
                        onOpenEpisode: openEpisode(on: .search)
                    )
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(tabBarMinimizeBehavior)
        .tabViewBottomAccessory(isEnabled: showsTabAccessory) {
            tabAccessory
        }
        .sensoryFeedback(.success, trigger: appModel.library.subscriptionAddedToken)
        .sensoryFeedback(trigger: appModel.library.refreshCompletedToken) { _, _ in
            appModel.library.lastRefreshWasOffline ? .warning : .success
        }
        .onChange(of: selectedTab, initial: true) { _, selectedTab in
            isSearchPresented = selectedTab == .search
        }
        .focusedSceneValue(\.openCastCommandActions, commandActions)
    }

    private func openEpisode(on section: AppSection) -> (String) -> Void {
        { episodeID in
            navigationPaths[section].append(.episodeDetail(id: episodeID))
        }
    }

    private func openPlaylist(on section: AppSection) -> (String) -> Void {
        { playlistID in
            navigationPaths[section].append(.playlistDetail(id: playlistID))
        }
    }

    private var showsTabAccessory: Bool {
        appModel.playback.currentEpisode != nil
    }

    private var tabAccessory: some View {
        MiniPlayerView(
            onExpand: onPresentNowPlaying
        )
    }

    private var commandActions: OpenCastCommandActions {
        OpenCastCommandActions.make(
            playback: appModel.playback,
            focusSearch: {
                selectedTab = .search
                isSearchPresented = true
            }
        )
    }

    private var tabBarMinimizeBehavior: TabBarMinimizeBehavior {
        selectedTab == .settings ? .never : .onScrollDown
    }
}
