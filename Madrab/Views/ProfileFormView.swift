import SwiftUI

struct ProfileFormView: View {
    let viewModel: ProfilesViewModel
    let editingProfile: PlayerProfile?

    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var validationMessage: String?

    init(viewModel: ProfilesViewModel, editingProfile: PlayerProfile?) {
        self.viewModel = viewModel
        self.editingProfile = editingProfile
        _displayName = State(initialValue: editingProfile?.displayName ?? "")
    }

    private var isEditing: Bool { editingProfile != nil }

    private var trimmedNameIsBlank: Bool {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Display name", text: $displayName)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel("Display name")
                }

                if let editingProfile {
                    Section("Avatar") {
                        HStack(spacing: 12) {
                            ProfileAvatarView(
                                displayName: displayName.isEmpty ? editingProfile.displayName : displayName,
                                imageData: editingProfile.avatarImageData,
                                diameter: 56
                            )
                            Text(editingProfile.avatarImageData == nil ? "Using generated initials" : "Custom photo")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Error: \(validationMessage)")
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Profile" : "New Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(trimmedNameIsBlank)
                }
            }
        }
    }

    private func save() {
        let success: Bool
        if let editingProfile {
            success = viewModel.updateProfile(
                id: editingProfile.id,
                displayName: displayName,
                avatarImageData: editingProfile.avatarImageData
            )
        } else {
            success = viewModel.createProfile(displayName: displayName) != nil
        }

        if success {
            dismiss()
        } else if let error = viewModel.lastError as? ProfileValidationError {
            validationMessage = error.errorDescription
        } else {
            validationMessage = "Couldn't save this profile. Please try again."
        }
    }
}
