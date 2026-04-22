//
//  ContentView.swift
//  GoBirdie
//
//  Created by Kim, Chester on 4/8/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            ScorecardsTab()
                .tabItem { Label("Scorecards", systemImage: "list.bullet.clipboard") }
                .tag(0)

            RoundTab()
                .tabItem { Label("Round", systemImage: "figure.golf") }
                .tag(1)

            MapTab()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(2)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(3)
        }
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
            Text("Scorecards")
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
            Text("Course Map")
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
                Section("Tee") {
                    Picker("Tee Color", selection: $appState.teeColor) {
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
