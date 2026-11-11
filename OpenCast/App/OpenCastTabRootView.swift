import SwiftUI

struct OpenCastTabRootView: View {
    @Environment(OpenCastAppModel.self) private var appModel
    /// The scene's fold mark as the root layer publishes it; nil until it
    /// does.
    @Environment(SceneLibraryLayouts.self) private var inheritedSceneLayouts: SceneLibraryLayouts?

    @State private var isSearchPresented = false
    /// The window as the two-pane root's reader last reported it.
    @State private var rootWindow = TwoPaneRootWindow.unmeasured
    /// `TwoPaneRootRule`'s answer for the window and the fold latch: the
    /// container the Library root uses.
    @State private var rootContainer = TwoPaneRootContainer.stack

    @Binding var selectedTab: AppSection
    @Binding var navigationPaths: AppNavigationPaths
    let onAdd: () -> Void
    let onPresentNowPlaying: () -> Void

    var body: some View {
        ZStack {
            // A sibling of the tab view, above every tab's container, so the
            // two-pane rule reads the window without Now Playing open.
            TwoPaneRootWindowReader { window in
                rootWindow = window
            }
            tabView
        }
        .onChange(of: rootWindow, initial: true) {
            updateRootContainer()
        }
        .onChange(of: inheritedSceneLayouts?.isFoldable == true) {
            updateRootContainer()
        }
    }

    // The fork has four tabs, which fit the iPhone Duo's bottom bar with
    // their titles, so it keeps titled tabs everywhere.
    private var tabView: some View {
        TabView(selection: $selectedTab) {
            Tab(AppSection.library.title, systemImage: AppSection.library.systemImage, value: AppSection.library) {
                TwoPaneRoot(
                    section: .library,
                    container: $rootContainer,
                    path: $navigationPaths[.library],
                    placeholder: .library,
                    openFromRoot: openFromRoot(on: .library),
                    onOpenEpisode: openEpisode(on: .library),
                    onOpenPlaylist: openPlaylist(on: .library)
                ) {
                    LibraryView(
                        onAdd: onAdd,
                        onOpenPlaylist: { openFromRoot(on: .library)(.playlistDetail(id: $0)) },
                        onOpenAdDetectionQueue: openAdDetection,
                        onOpenNotes: { openFromRoot(on: .library)(.notes) }
                    )
                }
                .publishesActiveTabBarPlacement()
            }

            Tab(
                AppSection.downloads.title,
                systemImage: AppSection.downloads.systemImage,
                value: AppSection.downloads
            ) {
                NavigationStack(path: $navigationPaths[.downloads]) {
                    DownloadsView(
                        onOpenEpisode: openEpisode(on: .downloads),
                        onOpenStorage: {
                            navigationPaths[.downloads].append(.downloadStorage)
                        },
                        onOpenDownloadSettings: {
                            navigationPaths[.downloads].append(.downloadSettings)
                        }
                    )
                    .withOpenCastDestinations(
                        onOpenEpisode: openEpisode(on: .downloads)
                    )
                }
                .publishesActiveTabBarPlacement()
            }
            .badge(appModel.downloads.activeDownloadCount)

            Tab(AppSection.settings.title, systemImage: AppSection.settings.systemImage, value: AppSection.settings) {
                NavigationStack(path: $navigationPaths[.settings]) {
                    SettingsView()
                        .withOpenCastDestinations()
                }
                .publishesActiveTabBarPlacement()
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
                .publishesActiveTabBarPlacement()
            }
        }
        .environment(\.openDownloadSettings, OpenDownloadSettingsAction(perform: openDownloadSettings))
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

    private func openDownloadSettings() {
        selectedTab = .downloads
        navigationPaths[.downloads] = [.downloadSettings]
    }

    /// The Ad Detection queue lives in its section at the root of Downloads.
    private func openAdDetection() {
        selectedTab = .downloads
        navigationPaths[.downloads] = []
    }

    /// The rule's container for the current window and latch; every change
    /// is logged with the inputs that made it.
    private func updateRootContainer() {
        let isFoldableScene = inheritedSceneLayouts?.isFoldable == true
        let container = TwoPaneRootRule.container(
            pose: rootWindow.pose,
            isFoldableScene: isFoldableScene,
            windowSize: rootWindow.size
        )
        TwoPaneRootLog.inputs(rootWindow, isFoldableScene: isFoldableScene, container: container)
        guard container != rootContainer else {
            return
        }
        TwoPaneRootLog.containerChange(from: rootContainer, to: container)
        rootContainer = container
    }

    /// A route opened from a two-pane root's own content (its rows, tiles,
    /// collection entries, callbacks and context menus): the detail's new
    /// root in the split, a push in the stack (`TwoPaneRootPath`).
    private func openFromRoot(on section: AppSection) -> (AppRoute) -> Void {
        { route in
            navigationPaths[section] = TwoPaneRootPath.openingFromRoot(
                route,
                in: navigationPaths[section],
                container: rootContainer
            )
        }
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

    /// Off unless chosen in Look & Feel: minimizing moves the bottom accessory
    /// inline, and every minimize or expand re-lays out the navigation stack
    /// inside the scroll callback, 40–55 ms main-thread stalls on an iPhone
    /// SE, felt as a stutter when a scroll starts or reaches the top.
    private var tabBarMinimizeBehavior: TabBarMinimizeBehavior {
        appModel.appearanceSettings.minimizesTabBarOnScroll && selectedTab != .settings ? .onScrollDown : .never
    }
}
