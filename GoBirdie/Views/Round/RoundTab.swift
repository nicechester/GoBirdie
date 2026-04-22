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
        } else if let snapshot = appState.pendingResume {
            ResumeRoundView(snapshot: snapshot, appState: appState)
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
    @ObservedObject var appState: AppState
    @Binding var showMenu: Bool
    @State private var showEndConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Header row with menu button
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Hole \(session.currentHoleNumber)")
                    .font(.title3).fontWeight(.bold)
                    .accessibilityIdentifier("holeLabel")

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
                    .accessibilityIdentifier("endRoundMenu")
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
                .accessibilityIdentifier("roundMenu")
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
            .accessibilityIdentifier("confirmEndRound")
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Save and finish this round?")
        }
        .alert("Are you still playing?", isPresented: $appState.showIdlePrompt) {
            Button("Yes, still playing") {
                appState.resetIdleTimer()
            }
            Button("End Round", role: .destructive) {
                session.endRound()
                appState.endActiveRound()
            }
        } message: {
            Text("No activity for 30 minutes.")
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
            .accessibilityIdentifier("startRoundButton")
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }
}

private struct ResumeRoundView: View {
    let snapshot: InProgressSnapshot
    let appState: AppState

    private var elapsed: String {
        let mins = Int(Date().timeIntervalSince(snapshot.round.startedAt) / 60)
        if mins < 60 { return "\(mins)m ago" }
        return "\(mins / 60)h \(mins % 60)m ago"
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 56)).foregroundStyle(.orange)

            Text("Round In Progress").font(.title2).fontWeight(.bold)

            VStack(spacing: 6) {
                Text(snapshot.round.courseName)
                    .font(.headline)
                Text("Hole \(snapshot.currentHoleIndex + 1)  ·  Started \(elapsed)")
                    .font(.subheadline).foregroundStyle(.secondary)
                if snapshot.round.totalStrokes > 0 {
                    Text("\(snapshot.round.totalStrokes) strokes")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                appState.resumeRound(snapshot: snapshot)
            } label: {
                Label("Resume Round", systemImage: "play.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 32)

            Button {
                appState.discardInProgressRound()
            } label: {
                Text("Discard")
                    .foregroundStyle(.red)
            }
            .padding(.bottom, 32)
        }
    }
}
