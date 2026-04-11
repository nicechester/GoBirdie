//
//  RoundTab.swift
//  GoBirdie

import SwiftUI
import GoBirdieCore

struct RoundTab: View {
    @EnvironmentObject var appState: AppState
    @State private var showStartRoundSheet = false
    @State private var showMenu = false

    var body: some View {
        if let session = appState.activeRound,
           let viewModel = appState.activeRoundViewModel {
            ActiveRoundView(
                session: session,
                viewModel: viewModel,
                appState: appState,
                showMenu: $showMenu
            )
        } else {
            EmptyRoundStateView(onStartRound: { showStartRoundSheet = true })
                .sheet(isPresented: $showStartRoundSheet) { StartRoundView() }
        }
    }
}

// Separate view so @ObservedObject works correctly
private struct ActiveRoundView: View {
    @ObservedObject var session: RoundSession
    @ObservedObject var viewModel: RoundViewModel
    let appState: AppState
    @Binding var showMenu: Bool
    @State private var showEndConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Header row with menu button
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Hole \(session.currentHoleNumber)")
                    .font(.title3).fontWeight(.bold)

                if let hole = session.currentHole,
                   let courseHole = viewModel.course.holes.first(where: { $0.number == session.currentHoleNumber }) {
                    let ydsText = courseHole.yardage.map { "\($0) yds" } ?? ""
                    Text("Par \(hole.par)" + (ydsText.isEmpty ? "" : "  ·  \(ydsText)"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()

                Menu {
                    Button { } label: {
                        Label("Change Tee", systemImage: "figure.golf")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showEndConfirm = true
                    } label: {
                        Label("End Round", systemImage: "flag.checkered")
                    }
                    Button(role: .destructive) {
                        appState.cancelActiveRound()
                    } label: {
                        Label("Cancel Round", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)

            DistanceDisplayView(distances: viewModel.distances)
                .padding(.horizontal, 16)

            HoleControlsView(
                session: session,
                course: viewModel.course,
                locationService: appState.getLocationService(),
                viewModel: viewModel
            )
            .padding(.top, 4)

            MiniScorecardView(session: session, onHoleSelect: { holeNumber in
                session.navigateTo(holeNumber: holeNumber, course: viewModel.course)
            })
            .padding(.top, 4)
        }
        .alert("End Round?", isPresented: $showEndConfirm) {
            Button("End", role: .destructive) {
                session.endRound()
                appState.endActiveRound()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Save and finish this round?")
        }
    }
}

private struct EmptyRoundStateView: View {
    var onStartRound: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "flag.fill")
                .font(.system(size: 56)).foregroundStyle(.green)
            Text("No Active Round").font(.title2).fontWeight(.bold)
            Text("Start a round to track distances\nand mark your shots")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button(action: onStartRound) {
                Label("Start Round", systemImage: "plus.circle.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }
}
