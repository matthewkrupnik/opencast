import SwiftData
import SwiftUI

/// One playlist: the episodes its rule matches, in rule order (show by show
/// when it lists its shows).
/// Tapping a row plays from there. The rule decides membership and order, so
/// rows cannot be reordered or removed; changing a rule in Playlist Settings
/// re-evaluates the list in place.
///
/// The body reads the evaluation once, through the app model's memo, which
/// recomputes only when a token the rule depends on changes. The body never
/// reads the playing playlist's remainder.
struct SmartPlaylistDetailView: View {
    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @State private var visibleEpisodeCount = EpisodeCatalogContinuation.pageSize
    @State private var isShowingSettings = false

    let summary: PlaylistSummary
    var onOpenEpisode: (String) -> Void = { _ in }

    var body: some View {
        let evaluation = appModel.smartPlaylistEvaluation(for: summary)
        let visibleEpisodes = evaluation.episodes.prefix(visibleEpisodeCount)

        List {
            if summary.hasUnreadableRule {
                ContentUnavailableView(
                    "Rules Unavailable",
                    systemImage: "music.note.list",
                    description: Text("These rules need a newer version of the app.")
                )
            } else if evaluation.episodes.isEmpty {
                ContentUnavailableView(
                    "No Matching Episodes",
                    systemImage: "music.note.list",
                    description: Text("No episodes match these rules. Change a rule in Playlist Settings to include more.")
                )
            } else {
                ForEach(visibleEpisodes) { episode in
                    PlaylistEpisodeRowView(
                        playlistID: summary.playlistID,
                        episode: episode,
                        onOpenEpisode: onOpenEpisode
                    )
                    .modifier(PodcastEpisodeSwipeActionsModifier(episode: episode))
                }
                EpisodeCatalogContinuation(totalCount: evaluation.count, visibleCount: $visibleEpisodeCount)
            }
        }
        .contentMargins(.bottom, 72, for: .scrollContent)
        .animation(listAnimation, value: visibleEpisodes.map(\.episodeID))
        .navigationTitle(summary.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                PlaylistActionsMenu(
                    summary: summary,
                    canDownloadAll: appModel.hasPlaylistDownloadAllCandidates(summary.playlistID),
                    onShowSettings: showSettings
                )
            }
        }
        // On the screen, not the toolbar menu: toolbar items rebuild on every
        // rule change, which tore down the Shows picker mid-pick.
        .sheet(isPresented: $isShowingSettings) {
            settingsSheet
        }
        // The age clause measures from the library's reference date; a
        // playlist opened from the playing-from pill never passes through
        // the Library screen that advances it.
        .onAppear(perform: appModel.library.advanceNewEpisodeReferenceDate)
    }

    private var settingsSheet: some View {
        NavigationStack {
            Group {
                if let rule = summary.rule {
                    PlaylistSettingsForm(rule: rule, onChange: setRule)
                }
            }
            .navigationTitle("Playlist Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isShowingSettings = false }
                }
            }
        }
    }

    private var listAnimation: Animation? {
        reduceMotion ? nil : .default
    }

    private func showSettings() {
        isShowingSettings = true
    }

    private func setRule(_ rule: PlaylistRule) {
        appModel.performPlaylistMutation {
            appModel.playlists.setRule(rule, for: summary.playlistID, modelContext: modelContext)
        }
    }
}
