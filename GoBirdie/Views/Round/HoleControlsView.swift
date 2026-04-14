//
//  HoleControlsView.swift
//  GoBirdie

import SwiftUI
import GoBirdieCore

struct HoleControlsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var session: RoundSession
    let course: Course
    let locationService: LocationService
    let viewModel: RoundViewModel
    @State private var showMarkShotSheet = false
    @State private var selectedClub: ClubType = .unknown

    var body: some View {
        VStack(spacing: 10) {
            // Row 1: Mark Shot + +Stroke
            HStack(spacing: 12) {
                Button { showMarkShotSheet = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                        Text("Mark Shot")
                    }
                    .font(.subheadline).fontWeight(.semibold)
                    .frame(maxWidth: .infinity).padding(10)
                    .background(Color.green).foregroundStyle(.white)
                    .cornerRadius(8)
                }

                Button {
                    session.addStroke()
                    appState.resetIdleTimer()
                } label: {
                    Text("+Stroke")
                        .font(.subheadline).fontWeight(.semibold)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color(.systemGray6)).foregroundStyle(.primary)
                        .cornerRadius(8)
                }
            }

            // Row 2: Putts stepper
            PuttStepper(session: session)

            // Row 3: Prev | Next (Next saves putts and advances)
            HStack(spacing: 12) {
                Button {
                    session.navigateTo(holeNumber: session.currentHoleNumber - 1, course: course)
                    appState.resetIdleTimer()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Prev")
                    }
                    .font(.subheadline).fontWeight(.semibold)
                    .frame(maxWidth: .infinity).padding(10)
                    .background(Color(.systemGray6)).foregroundStyle(.primary)
                    .cornerRadius(8)
                }
                .disabled(session.currentHoleNumber <= 1)

                Button {
                    if session.currentHoleNumber == session.round.holes.count {
                        session.endRound()
                    } else {
                        session.navigateTo(holeNumber: session.currentHoleNumber + 1, course: course)
                    }
                    appState.resetIdleTimer()
                } label: {
                    let isLast = session.currentHoleNumber == session.round.holes.count
                    HStack(spacing: 4) {
                        Text(isLast ? "Finish" : "Next")
                        Image(systemName: isLast ? "flag.checkered" : "chevron.right")
                    }
                    .font(.subheadline).fontWeight(.semibold)
                    .frame(maxWidth: .infinity).padding(10)
                    .background(isLast ? Color.orange : Color(.systemGray6))
                    .foregroundStyle(isLast ? .white : .primary)
                    .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .sheet(isPresented: $showMarkShotSheet) {
            MarkShotSheet(selectedClub: $selectedClub) { club in
                let loc = locationService.currentLocation ?? GpsPoint(lat: 0, lon: 0)
                let alt = locationService.currentAltitude
                session.markShot(at: loc, club: club, altitudeMeters: alt)
                selectedClub = .unknown
                appState.resetIdleTimer()
            }
        }
    }
}

// MARK: - Putt Stepper

private struct PuttStepper: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var session: RoundSession

    var putts: Int { session.currentHole?.putts ?? 0 }

    var body: some View {
        HStack(spacing: 0) {
            Text("Putts")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                Button {
                    if putts > 0 {
                        session.setPutts(putts - 1)
                        appState.resetIdleTimer()
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(putts > 0 ? .green : Color(.systemGray4))
                }
                .disabled(putts == 0)

                Text("\(putts)")
                    .font(.title2).fontWeight(.bold).monospacedDigit()
                    .frame(minWidth: 32, alignment: .center)

                Button {
                    session.setPutts(putts + 1)
                    appState.resetIdleTimer()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Mark Shot Sheet

private struct MarkShotSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedClub: ClubType
    let onConfirm: (ClubType) -> Void

    var body: some View {
        NavigationStack {
            List(ClubType.allCases, id: \.self) { club in
                Button {
                    selectedClub = club
                    onConfirm(club)
                    dismiss()
                } label: {
                    HStack {
                        Text(club.displayName).foregroundStyle(.primary)
                        Spacer()
                        if selectedClub == club {
                            Image(systemName: "checkmark").foregroundStyle(.green)
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
            .navigationTitle("Select Club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { onConfirm(.unknown); dismiss() }
                }
            }
        }
    }
}
