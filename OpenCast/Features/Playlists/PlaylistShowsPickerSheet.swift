import SwiftUI

/// Picks the shows a playlist draws from, and their order. All Shows is on
/// only while the rule names no shows, so new subscriptions join it; picking
/// a show narrows the rule to the listed shows, adding it last, and
/// unchecking the last listed show returns to All Shows. With two or more
/// picked, Reorder swaps the checklist for the picked shows alone, to drag
/// into the order their episodes play in; the checklist itself never gains
/// rows above a pick, so picking far down the list never moves it. Each
/// change reports the new rule at once through `onChange`, and the rows read
/// the rule the sheet is handed, so the list updates in place and keeps its
/// scroll position.
struct PlaylistShowsPickerSheet: View {
    /// Above this many shows the search field stays in view.
    private static let searchThreshold = 10

    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var isReordering = false

    let rule: PlaylistRule
    let onChange: (PlaylistRule) -> Void

    var body: some View {
        @Bindable var appModel = appModel
        let shows = subscribedShows
        let ordered = orderedShows(shows)

        NavigationStack {
            // Always attached: removing a conditional `.searchable` mid-update
            // can strand the system's search dismissal. A short list only
            // tucks the field away until the listener pulls down.
            Group {
                if isReordering {
                    orderList(ordered)
                } else {
                    showList(shows, pickedCount: ordered.count)
                }
            }
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(
                        displayMode: shows.count > Self.searchThreshold ? .always : .automatic
                    ),
                    prompt: "Search Shows"
                )
                .navigationTitle(isReordering ? "Play Order" : "Shows")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if isReordering || (searchText.isEmpty && ordered.count > 1) {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(isReordering ? "Pick Shows" : "Reorder", action: toggleReordering)
                                .accessibilityIdentifier("Shows Picker Reorder")
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: dismiss.callAsFunction)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: rule.podcastIDs)
        // The root's playlist alert cannot present over a sheet, so a save
        // that fails while the picker is up surfaces here.
        .alert("Playlist Error", item: $appModel.lastPlaylistError) { _ in
        } message: { message in
            Text(message)
        }
    }

    private func showList(_ shows: [SubscriptionRecord], pickedCount: Int) -> some View {
        let matches = searchText.isEmpty
            ? shows
            : shows.filter { $0.title.localizedStandardContains(searchText) }
        let pickedIDs = Set(rule.podcastIDs ?? [])

        return List {
            if searchText.isEmpty {
                Section {
                    PlaylistShowsPickerRow(
                        title: "All Shows",
                        isSelected: rule.podcastIDs == nil,
                        identifier: "all",
                        action: pickAllShows
                    ) {
                        Image(systemName: "books.vertical")
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.tint.quaternary, in: .rect(cornerRadius: 8))
                    }
                } footer: {
                    Text("Shows you subscribe to later join All Shows.")
                }
            }

            Section {
                ForEach(matches, id: \.feedURL) { show in
                    PlaylistShowsPickerRow(
                        title: show.title,
                        isSelected: pickedIDs.contains(show.feedURL),
                        identifier: show.feedURL,
                        action: { toggle(show.feedURL) }
                    ) {
                        artwork(for: show)
                    }
                }
            } header: {
                Text("From Shows")
            } footer: {
                if pickedCount > 1, searchText.isEmpty {
                    Text("Episodes play show by show, in the order you picked them. Tap Reorder to change it.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if matches.isEmpty, !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .accessibilityIdentifier("Shows Picker")
    }

    private func artwork(for show: SubscriptionRecord) -> some View {
        let podcastCache = appModel.library.podcastCache(for: show.feedURL)
        return ArtworkPlaceholder(
            title: show.title,
            imageURL: podcastCache?.artworkURL ?? show.artworkURL,
            size: 40,
            preview: podcastCache.flatMap { appModel.library.artworkPreview(for: $0) }
        )
        .clipShape(.rect(cornerRadius: 8))
    }

    /// Subscribed shows in the Library's title order, one row per feed even
    /// while sync twins of a subscription are waiting for repair.
    private var subscribedShows: [SubscriptionRecord] {
        var seenFeedURLs = Set<String>()
        return appModel.library.subscriptions.filter { subscription in
            seenFeedURLs.insert(subscription.feedURL).inserted
        }
    }

    /// The picked shows alone, in play order, always in edit mode so each
    /// row shows its drag handle.
    private func orderList(_ ordered: [SubscriptionRecord]) -> some View {
        List {
            Section {
                ForEach(ordered, id: \.feedURL) { show in
                    HStack(spacing: 12) {
                        artwork(for: show)
                            .frame(width: 40, height: 40)
                            .accessibilityHidden(true)
                        Text(show.title)
                            .lineLimit(2)
                    }
                    .accessibilityIdentifier("shows-order-row-\(show.feedURL)")
                }
                .onMove { source, destination in
                    move(ordered, fromOffsets: source, toOffset: destination)
                }
                .deleteDisabled(true)
            } footer: {
                Text("Episodes play show by show, in this order.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("Shows Order")
    }

    private func toggleReordering() {
        searchText = ""
        isReordering.toggle()
    }

    /// The picked shows that are still subscribed, in the rule's order.
    private func orderedShows(_ shows: [SubscriptionRecord]) -> [SubscriptionRecord] {
        let showsByID = Dictionary(shows.map { ($0.feedURL, $0) }, uniquingKeysWith: { first, _ in first })
        return (rule.podcastIDs ?? []).compactMap { showsByID[$0] }
    }

    /// Shows no longer subscribed drop out, as they do when a show is
    /// unchecked.
    private func move(_ ordered: [SubscriptionRecord], fromOffsets source: IndexSet, toOffset destination: Int) {
        var podcastIDs = ordered.map(\.feedURL)
        podcastIDs.move(fromOffsets: source, toOffset: destination)
        var updated = rule
        updated.podcastIDs = podcastIDs
        onChange(updated.normalized())
    }

    private func pickAllShows() {
        guard rule.podcastIDs != nil else {
            return
        }
        var updated = rule
        updated.podcastIDs = nil
        onChange(updated.normalized())
    }

    private func toggle(_ feedURL: String) {
        var updated = rule
        if rule.podcastIDs?.contains(feedURL) == true {
            let subscribedIDs = appModel.library.activePodcastIDs
            let remaining = (rule.podcastIDs ?? []).filter { podcastID in
                podcastID != feedURL && subscribedIDs.contains(podcastID)
            }
            updated.podcastIDs = remaining.isEmpty ? nil : remaining
        } else {
            updated.podcastIDs = (rule.podcastIDs ?? []) + [feedURL]
        }
        onChange(updated.normalized())
    }
}
