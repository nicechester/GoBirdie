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
    private let distanceEngine = DistanceEngine()

    var body: some View {
        VStack(spacing: 10) {
            // Row 1: Mark Shot + Penalty / Undo
            HStack(spacing: 12) {
                Button {
                    let currentHoleNumber = session.currentHoleNumber
                    var distanceToGreen: Int? = nil
                    if let hole = course.holes.first(where: { $0.number == currentHoleNumber }),
                       let greenCenter = hole.greenCenter,
                       let playerLoc = locationService.currentLocation {
                        let yards = distanceEngine.distanceYards(from: playerLoc, to: greenCenter)
                        distanceToGreen = Int(yards.rounded())
                    }
                    selectedClub = defaultClubForDistance(distanceToGreen, shotNumber: (session.currentHole?.shots.count ?? 0) + 1)
                    showMarkShotSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                        Text("Mark Shot")
                    }
                    .font(.subheadline).fontWeight(.semibold)
                    .frame(maxWidth: .infinity).padding(10)
                    .background(Color.green).foregroundStyle(.white)
                    .cornerRadius(8)
                }
                .accessibilityIdentifier("markShotButton")

                Button {
                    session.addPenalty()
                    appState.resetIdleTimer()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption)
                        Text("Penalty").font(.system(size: 9, weight: .semibold))
                    }
                    .frame(width: 52, height: 42)
                    .background(Color.orange).foregroundStyle(.white)
                    .cornerRadius(8)
                }

                Button {
                    session.undoLastAction()
                    appState.resetIdleTimer()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.uturn.backward").font(.caption)
                        Text("Undo").font(.system(size: 9, weight: .semibold))
                    }
                    .frame(width: 52, height: 42)
                    .background(Color(.systemGray6)).foregroundStyle(.primary)
                    .cornerRadius(8)
                }
                .disabled((session.currentHole?.strokes ?? 0) == 0)
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
                        appState.endActiveRound()
                    } else {
                        session.navigateTo(holeNumber: session.currentHoleNumber + 1, course: course)
                        appState.resetIdleTimer()
                    }
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
                .accessibilityIdentifier("nextHoleButton")
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

    private func defaultClubForDistance(_ yards: Int?, shotNumber: Int = 1) -> ClubType {
        let enabledClubs = ClubBag.shared.enabledClubs
        guard let y = yards, !enabledClubs.isEmpty else {
            return enabledClubs.first ?? .unknown
        }
        // Don't recommend driver from 2nd shot onwards
        let excludeDriver = shotNumber > 1
        let table: [(ClubType, Int)] = [
            (.driver, 230), (.wood3, 210), (.wood5, 195),
            (.hybrid3, 190), (.hybrid4, 180), (.hybrid5, 170),
            (.iron4, 170), (.iron5, 160), (.iron6, 150),
            (.iron7, 140), (.iron8, 130), (.iron9, 120),
            (.pitchingWedge, 110), (.gapWedge, 95), (.sandWedge, 80),
            (.lobWedge, 60),
        ]
        for (club, minDist) in table {
            if club == .driver && excludeDriver { continue }
            if enabledClubs.contains(club) && y >= minDist {
                return club
            }
        }
        return enabledClubs.last ?? .unknown
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
                .accessibilityIdentifier("puttMinus")
                .disabled(putts == 0)

                Text("\(putts)")
                    .font(.title2).fontWeight(.bold).monospacedDigit()
                    .frame(minWidth: 32, alignment: .center)
                    .accessibilityIdentifier("puttCount")

                Button {
                    session.setPutts(putts + 1)
                    appState.resetIdleTimer()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
                .accessibilityIdentifier("puttPlus")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Mark Shot Sheet

struct MarkShotSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedClub: ClubType
    @ObservedObject private var bag = ClubBag.shared
    let onConfirm: (ClubType) -> Void
    var onCancel: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Club", selection: $selectedClub) {
                    ForEach(bag.enabledClubs, id: \.self) { club in
                        Text(club.displayName).tag(club)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxHeight: 220)

                Button {
                    onConfirm(selectedClub)
                    dismiss()
                } label: {
                    Text("Confirm")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            .navigationTitle("Select Club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel?()
                        dismiss()
                    }
                }
            }
        }
    }
}
