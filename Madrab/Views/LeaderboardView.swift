import SwiftUI

enum LeaderboardAccessibility {
    static func summary(for entry: LeaderboardEntry) -> String {
        "Rank \(entry.rank), \(entry.displayName), \(entry.stats.totalPoints) points, " +
        "\(entry.stats.wins) wins, \(entry.stats.losses) losses, " +
        "\(entry.stats.matchesPlayed) matches played"
    }
}

struct LeaderboardView: View {
    let viewModel: LeaderboardViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(viewModel.entries) { entry in
                            row(for: entry)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Leaderboard")
        }
        .task {
            viewModel.reload()
        }
    }

    private func row(for entry: LeaderboardEntry) -> some View {
        HStack(spacing: 12) {
            rankBadge(entry.rank)

            ProfileAvatarView(displayName: entry.displayName, imageData: entry.avatarImageData, diameter: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text("\(entry.stats.matchesPlayed) played")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.stats.totalPoints)")
                    .font(.title3.bold())
                    .foregroundStyle(Color.accentColor)
                Text("\(entry.stats.wins)W – \(entry.stats.losses)L")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LeaderboardAccessibility.summary(for: entry))
    }

    private func rankBadge(_ rank: Int) -> some View {
        Text("\(rank)")
            .font(.headline.weight(.bold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 28, height: 28)
            .background(Color.accentColor.opacity(0.16))
            .clipShape(Circle())
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "trophy")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
            Text("No Matches Yet")
                .font(.title3.bold())
            Text("Finish a match to start building the leaderboard.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    LeaderboardView(viewModel: LeaderboardViewModel(
        leaderboardStore: LeaderboardStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("preview-leaderboard.json")
        ),
        profileStore: ProfileStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("preview-profiles.json")
        )
    ))
}
