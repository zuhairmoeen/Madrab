import SwiftUI
import MadrabScoringEngine

struct MatchSetupView: View {
    let onStart: (MatchConfiguration, String, String) -> Void

    @State private var teamALabel = ""
    @State private var teamBLabel = ""
    @State private var setsToWin = 2
    @State private var deuceRule: DeuceRule = .advantage
    @State private var finalSetIsMatchTiebreak = false

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

            Form {
                Section("Teams") {
                    TextField("Team A name", text: $teamALabel)
                    TextField("Team B name", text: $teamBLabel)
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
                    .listRowInsets(EdgeInsets())
                    .padding(8)
                }
            }
            .listSectionSpacing(20)
            .tint(.accentColor)
        }
    }

    private func startMatch() {
        guard let configuration = try? MatchConfiguration(
            setsToWin: setsToWin,
            deuceRule: deuceRule,
            finalSetMode: finalSetIsMatchTiebreak
                ? .matchTiebreak(points: 10)
                : .fullSet
        ) else { return }
        onStart(configuration, teamALabel, teamBLabel)
    }
}

#Preview {
    MatchSetupView(onStart: { _, _, _ in })
}
