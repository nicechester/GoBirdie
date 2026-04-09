//
//  HoleControlsView.swift
//  GoBirdie

import SwiftUI
import GoBirdieCore

struct HoleControlsView: View {
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

                Button { session.addStroke() } label: {
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
                    if session.currentHoleNumber == 18 {
                        session.endRound()
                    } else {
                        session.navigateTo(holeNumber: session.currentHoleNumber + 1, course: course)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(session.currentHoleNumber == 18 ? "Finish" : "Next")
                        Image(systemName: session.currentHoleNumber == 18 ? "flag.checkered" : "chevron.right")
                    }
                    .font(.subheadline).fontWeight(.semibold)
                    .frame(maxWidth: .infinity).padding(10)
                    .background(session.currentHoleNumber == 18 ? Color.orange : Color(.systemGray6))
                    .foregroundStyle(session.currentHoleNumber == 18 ? .white : .primary)
                    .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .sheet(isPresented: $showMarkShotSheet) {
            MarkShotSheet(selectedClub: $selectedClub) { club in
                let loc = locationService.currentLocation ?? GpsPoint(lat: 0, lon: 0)
                session.markShot(at: loc, club: club)
                selectedClub = .unknown
            }
        }
    }
}

// MARK: - Putt Stepper

private struct PuttStepper: View {
    @ObservedObject var session: RoundSession

    var putts: Int { session.currentHole?.putts ?? 0 }

    var body: some View {
        HStack(spacing: 0) {
            Text("Putts")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                Button {
                    if putts > 0 { session.setPutts(putts - 1) }
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
