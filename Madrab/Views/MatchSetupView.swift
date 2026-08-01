import SwiftUI
import MadrabScoringEngine

enum MatchSetupValidation {
    static func canStart(teamAProfile: PlayerProfile?, teamBProfile: PlayerProfile?) -> Bool {
        guard let teamAProfile, let teamBProfile else { return false }
        return teamAProfile.id != teamBProfile.id
    }

    /// Returns `selectedID` unchanged if it still refers to a profile in
    /// `profiles` (even if that profile has since been renamed), or `nil` if
    /// the profile no longer exists.
    static func reconciledSelection(_ selectedID: UUID?, in profiles: [PlayerProfile]) -> UUID? {
        guard let selectedID, profiles.contains(where: { $0.id == selectedID }) else { return nil }
        return selectedID
    }
}

struct MatchSetupView: View {
    let profilesViewModel: ProfilesViewModel
    let onStart: (MatchConfiguration, PlayerProfile, PlayerProfile) -> Void

    @State private var teamAProfileID: UUID?
    @State private var teamBProfileID: UUID?
    @State private var setsToWin = 2
    @State private var deuceRule: DeuceRule = .advantage
    @State private var finalSetIsMatchTiebreak = false

    private var teamAProfile: PlayerProfile? {
        profilesViewModel.profiles.first { $0.id == teamAProfileID }
    }

    private var teamBProfile: PlayerProfile? {
        profilesViewModel.profiles.first { $0.id == teamBProfileID }
    }

    private var canStart: Bool {
        MatchSetupValidation.canStart(teamAProfile: teamAProfile, teamBProfile: teamBProfile)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Madrab")
                    .font(.largeTitle.bold())
                Text("Set up your match and start scoring.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 4)

            if profilesViewModel.profiles.count < 2 {
                insufficientProfilesState
            } else {
                Form {
                    Section("Teams") {
                        profileSelector(title: "Team A", selection: $teamAProfileID, excluding: teamBProfileID)
                        profileSelector(title: "Team B", selection: $teamBProfileID, excluding: teamAProfileID)
                    }

                    Section("Format") {
                        Picker("Best of", selection: $setsToWin) {
                            Text("1 Set").tag(1)
                            Text("3 Sets").tag(2)
                        }
                        .pickerStyle(.segmented)

                        Picker("Deuce rule", selection: $deuceRule) {
                            Text("Advantage").tag(DeuceRule.advantage)
                            Text("Golden Point").tag(DeuceRule.goldenPoint)
                        }
                        .pickerStyle(.segmented)

                        if setsToWin == 2 {
                            Picker("Final set", selection: $finalSetIsMatchTiebreak) {
                                Text("Full Set").tag(false)
                                Text("Match Tiebreak").tag(true)
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    Section {
                        Button {
                            startMatch()
                        } label: {
                            Text("Start Match")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        .controlSize(.large)
                        .disabled(!canStart)
                        .listRowInsets(EdgeInsets())
                        .padding(8)
                    }
                }
                .listSectionSpacing(20)
                .tint(.accentColor)
            }
        }
        .onChange(of: profilesViewModel.profiles) {
            teamAProfileID = MatchSetupValidation.reconciledSelection(teamAProfileID, in: profilesViewModel.profiles)
            teamBProfileID = MatchSetupValidation.reconciledSelection(teamBProfileID, in: profilesViewModel.profiles)
        }
    }

    private func profileSelector(title: String, selection: Binding<UUID?>, excluding excludedID: UUID?) -> some View {
        let selectedProfile = profilesViewModel.profiles.first { $0.id == selection.wrappedValue }
        let availableProfiles = profilesViewModel.profiles.filter { $0.id != excludedID }

        return Menu {
            ForEach(availableProfiles) { profile in
                Button(profile.displayName) {
                    selection.wrappedValue = profile.id
                }
            }
        } label: {
            HStack(spacing: 12) {
                if let selectedProfile {
                    ProfileAvatarView(
                        displayName: selectedProfile.displayName,
                        imageData: selectedProfile.avatarImageData,
                        diameter: 36
                    )
                    Text(selectedProfile.displayName)
                        .foregroundStyle(.primary)
                } else {
                    ZStack {
                        Circle().fill(Color(.tertiarySystemFill))
                        Image(systemName: "person")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 36, height: 36)
                    Text("Select \(title)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .accessibilityLabel("\(title) player")
        .accessibilityValue(selectedProfile?.displayName ?? "Not selected")
    }

    private var insufficientProfilesState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
            Text("Not Enough Profiles")
                .font(.title3.bold())
            Text("You need at least two player profiles before you can start a match. Create profiles, then come back here to start.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func startMatch() {
        guard let teamAProfile, let teamBProfile, canStart else { return }
        guard let configuration = try? MatchConfiguration(
            setsToWin: setsToWin,
            deuceRule: deuceRule,
            finalSetMode: finalSetIsMatchTiebreak
                ? .matchTiebreak(points: 10)
                : .fullSet
        ) else { return }
        onStart(configuration, teamAProfile, teamBProfile)
    }
}

#Preview {
    MatchSetupView(
        profilesViewModel: ProfilesViewModel(
            store: ProfileStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("preview-profiles.json"))
        ),
        onStart: { _, _, _ in }
    )
}
