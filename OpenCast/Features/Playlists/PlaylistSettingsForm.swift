import SwiftUI

/// A playlist's settings: its color, then its rule — which episodes and
/// shows it draws from, the filters that narrow them and the order they
/// play in. A playlist without a readable rule shows only its color. The
/// form only reports changes through `onTintChange` and `onChange`; the
/// caller saves them.
struct PlaylistSettingsForm: View {
    let tint: PlaylistTint
    let rule: PlaylistRule?
    let onTintChange: (PlaylistTint) -> Void
    let onChange: (PlaylistRule) -> Void

    var body: some View {
        Form {
            Section {
                PlaylistTintPicker(selection: tintBinding)
            } header: {
                Text("Color")
            }

            if let rule {
                PlaylistRuleSections(rule: rule, onChange: onChange)
            }
        }
    }

    private var tintBinding: Binding<PlaylistTint> {
        Binding {
            tint
        } set: { tint in
            guard tint != self.tint else {
                return
            }
            onTintChange(tint)
        }
    }
}

private struct PlaylistRuleSections: View {
    let rule: PlaylistRule
    let onChange: (PlaylistRule) -> Void

    var body: some View {
        Group {
            Section {
                PlaylistShowsRuleRow(rule: rule, onChange: commit)

                Picker("Status", selection: statusBinding) {
                    ForEach(PlaylistRule.statusOptions) { status in
                        Text(status.title)
                            .tag(status)
                    }
                }
                .accessibilityIdentifier("Smart Rule Status")

                Toggle("Downloaded Only", isOn: downloadedOnlyBinding)
                    .accessibilityIdentifier("Smart Rule Downloaded Only")
            } header: {
                Text("Episodes")
            }

            Section {
                Picker("Length", selection: lengthBinding) {
                    ForEach(PlaylistRuleLengthPreset.allCases, id: \.self) { preset in
                        Text(preset.title)
                            .tag(Optional(preset))
                    }
                }
                .accessibilityIdentifier("Smart Rule Length")

                Picker("Published", selection: maximumAgeDaysBinding) {
                    ForEach(PlaylistRule.agePresets, id: \.self) { days in
                        Text(PlaylistRule.ageTitle(maximumAgeDays: days))
                            .tag(days)
                    }
                }
                .accessibilityIdentifier("Smart Rule Age")

                Picker("Limit", selection: limitBinding) {
                    ForEach(PlaylistRule.limitPresets, id: \.self) { limit in
                        Text(PlaylistRule.limitTitle(limit: limit))
                            .tag(limit)
                    }
                }
                .accessibilityIdentifier("Smart Rule Limit")
            } header: {
                Text("Filters")
            }

            Section {
                Picker("Sort By", selection: sortOrderBinding) {
                    ForEach(PlaylistRule.sortOptions, id: \.self) { sortOrder in
                        Text(sortOrder.title)
                            .tag(sortOrder)
                    }
                }
                .accessibilityIdentifier("Smart Rule Sort")
            } header: {
                Text("Order")
            }
        }
    }

    private var statusBinding: Binding<PodcastEpisodeFilter> {
        Binding {
            rule.status
        } set: { status in
            var updated = rule
            updated.status = status
            commit(updated)
        }
    }

    private var downloadedOnlyBinding: Binding<Bool> {
        Binding {
            rule.downloadedOnly
        } set: { downloadedOnly in
            var updated = rule
            updated.downloadedOnly = downloadedOnly
            commit(updated)
        }
    }

    private var sortOrderBinding: Binding<PodcastEpisodeSortOrder> {
        Binding {
            rule.sortOrder
        } set: { sortOrder in
            var updated = rule
            updated.sortOrder = sortOrder
            commit(updated)
        }
    }

    /// Nil while the stored bounds match no preset, so no option is checked.
    private var lengthBinding: Binding<PlaylistRuleLengthPreset?> {
        Binding {
            PlaylistRuleLengthPreset.matching(
                minimumMinutes: rule.minimumMinutes,
                maximumMinutes: rule.maximumMinutes
            )
        } set: { preset in
            guard let preset else {
                return
            }
            var updated = rule
            updated.minimumMinutes = preset.minimumMinutes
            updated.maximumMinutes = preset.maximumMinutes
            commit(updated)
        }
    }

    private var maximumAgeDaysBinding: Binding<Int?> {
        Binding {
            rule.maximumAgeDays
        } set: { maximumAgeDays in
            var updated = rule
            updated.maximumAgeDays = maximumAgeDays
            commit(updated)
        }
    }

    private var limitBinding: Binding<Int?> {
        Binding {
            rule.limit
        } set: { limit in
            var updated = rule
            updated.limit = limit
            commit(updated)
        }
    }

    /// Re-picking the current option calls the binding too; only a real
    /// change reaches the caller.
    private func commit(_ updated: PlaylistRule) {
        let normalized = updated.normalized()
        guard normalized != rule else {
            return
        }
        onChange(normalized)
    }
}

#Preview {
    NavigationStack {
        PlaylistSettingsForm(
            tint: .teal,
            rule: PlaylistRule(
                status: .inProgress,
                downloadedOnly: true,
                maximumMinutes: 45,
                maximumAgeDays: 30,
                sortOrder: .newestFirst
            ),
            onTintChange: { _ in },
            onChange: { _ in }
        )
        .navigationTitle("Playlist Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
    .environment(OpenCastAppModel())
}
