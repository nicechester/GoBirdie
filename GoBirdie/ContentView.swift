//
//  ContentView.swift
//  GoBirdie
//
//  Created by Kim, Chester on 4/8/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var localization = LocalizationManager.shared

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            ScorecardsTab()
                .tabItem { Label("tab.scorecards".localized, systemImage: "list.bullet.clipboard") }
                .tag(0)

            RoundTab()
                .tabItem { Label("round.title".localized, systemImage: "figure.golf") }
                .tag(1)

            MapTab()
                .tabItem { Label("tab.map".localized, systemImage: "map") }
                .tag(2)

            SettingsView()
                .tabItem { Label("tab.settings".localized, systemImage: "gearshape") }
                .tag(3)
        }
        .id(localization.currentLanguage) // Force refresh on language change
        .accessibilityIdentifier("mainTabView")
    }
}

// MARK: - Placeholder Views (TODO: implement later)

struct ScorecardsPlaceholder: View {
    var body: some View {
        VStack {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("tab.scorecards".localized)
                .font(.headline)
            Text("Coming soon")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct MapPlaceholder: View {
    var body: some View {
        VStack {
            Image(systemName: "map")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("tab.map".localized)
                .font(.headline)
            Text("Coming soon")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsPlaceholder: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    private let teeColors = ["Black", "Blue", "White", "Yellow", "Red"]
    private let teeColorDots: [String: Color] = [
        "Black": .black, "Blue": .blue, "White": .gray,
        "Yellow": .yellow, "Red": .red
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("settings.tee".localized) {
                    Picker("settings.teeColor".localized, selection: $appState.teeColor) {
                        ForEach(teeColors, id: \.self) { color in
                            HStack {
                                Circle()
                                    .fill(teeColorDots[color] ?? .gray)
                                    .frame(width: 12, height: 12)
                                Text(color)
                            }
                            .tag(color)
                        }
                    }
                }
            }
            .navigationTitle("tab.settings".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done".localized) { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .preferredColorScheme(.light)
}
