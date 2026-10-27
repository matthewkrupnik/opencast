import SwiftUI

/// Names a new playlist and picks its color. Create stays disabled until the
/// trimmed name has a character, and `onCreate` receives the trimmed name.
struct NewPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var name = ""
    @State private var tint: PlaylistTint

    let onCreate: (String, PlaylistTint) -> Void

    init(initialTint: PlaylistTint, onCreate: @escaping (String, PlaylistTint) -> Void) {
        _tint = State(initialValue: initialTint)
        self.onCreate = onCreate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        PlaylistCoverView(tint: tint, size: 44, cornerRadius: 6)
                        TextField("Name", text: $name)
                            .textInputAutocapitalization(.words)
                            .focused($isNameFocused)
                            .submitLabel(.done)
                            .onSubmit(create)
                            .accessibilityIdentifier("New Playlist Name")
                    }
                }

                Section("Color") {
                    PlaylistTintPicker(selection: $tint)
                }
            }
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear { isNameFocused = true }
        }
        .presentationDetents([.medium])
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func create() {
        let trimmedName = trimmedName
        guard !trimmedName.isEmpty else {
            return
        }
        onCreate(trimmedName, tint)
        dismiss()
    }
}

#Preview {
    NewPlaylistSheet(initialTint: .teal) { _, _ in }
}
