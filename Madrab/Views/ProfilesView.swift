import SwiftUI

struct ProfilesView: View {
    let viewModel: ProfilesViewModel

    @State private var isPresentingNewProfileForm = false
    @State private var editingProfile: PlayerProfile?
    @State private var profilePendingDeletion: PlayerProfile?
    @State private var deletionBlockedMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.profiles.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(viewModel.profiles) { profile in
                            Button {
                                editingProfile = profile
                            } label: {
                                row(for: profile)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    profilePendingDeletion = profile
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Profiles")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingNewProfileForm = true
                    } label: {
                        Label("Add Profile", systemImage: "plus")
                    }
                    .accessibilityLabel("Add Profile")
                }
            }
            .sheet(isPresented: $isPresentingNewProfileForm) {
                ProfileFormView(viewModel: viewModel, editingProfile: nil)
            }
            .sheet(item: $editingProfile) { profile in
                ProfileFormView(viewModel: viewModel, editingProfile: profile)
            }
            .confirmationDialog(
                "Delete this profile?",
                isPresented: Binding(
                    get: { profilePendingDeletion != nil },
                    set: { isPresented in
                        if !isPresented { profilePendingDeletion = nil }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let profile = profilePendingDeletion {
                        attemptDelete(profile)
                    }
                    profilePendingDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    profilePendingDeletion = nil
                }
            } message: {
                Text("This removes the profile and its leaderboard statistics. This cannot be undone.")
            }
            .alert(
                "Can't Delete Profile",
                isPresented: Binding(
                    get: { deletionBlockedMessage != nil },
                    set: { isPresented in
                        if !isPresented { deletionBlockedMessage = nil }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deletionBlockedMessage ?? "")
            }
        }
    }

    private func attemptDelete(_ profile: PlayerProfile) {
        guard !viewModel.deleteProfile(id: profile.id) else { return }

        if let error = viewModel.lastError as? ProfileDeletionError {
            deletionBlockedMessage = error.errorDescription
        } else {
            deletionBlockedMessage = "Couldn't delete this profile. Please try again."
        }
    }

    private func row(for profile: PlayerProfile) -> some View {
        HStack(spacing: 12) {
            ProfileAvatarView(displayName: profile.displayName, imageData: profile.avatarImageData)
            Text(profile.displayName)
                .font(.body.weight(.medium))
            Spacer()
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(profile.displayName)
        .accessibilityAddTraits(.isButton)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
            Text("No Profiles Yet")
                .font(.title3.bold())
            Text("Add players to start tracking matches and the leaderboard.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                isPresentingNewProfileForm = true
            } label: {
                Text("Add Profile")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .controlSize(.large)
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ProfilesView(viewModel: ProfilesViewModel(
        store: ProfileStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("preview-profiles.json"))
    ))
}
