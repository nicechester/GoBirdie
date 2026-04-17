//
//  WatchRoundView.swift
//  GoBirdie Watch App

import SwiftUI

struct WatchRoundView: View {
    @EnvironmentObject var session: WatchRoundSession

    var body: some View {
        ZStack {
            if session.isRoundEnded {
                RoundEndedView()
            } else if session.hasHoleData {
                TabView {
                    ActiveRoundView()
                    EndRoundPage()
                }
                .tabViewStyle(.verticalPage)
            } else {
                StartView()
            }

            if session.showClubPicker {
                ClubPickerOverlay()
            }
        }
    }
}

// MARK: - Start View

private struct StartView: View {
    @EnvironmentObject var session: WatchRoundSession

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "flag.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)

            if session.courseName.isEmpty {
                Text("Waiting for\niPhone...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text(session.courseName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Active Round

private struct ActiveRoundView: View {
    @EnvironmentObject var session: WatchRoundSession
    @State private var crownHole: Int = 1

    private var onGreen: Bool {
        guard let pin = session.pinYards else { return false }
        return pin <= 30
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Hole \(session.holeNumber)")
                    .font(.caption).fontWeight(.bold)
                Spacer()
                Text("Par \(session.par)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)

            if onGreen {
                PuttModeView()
            } else {
                DistanceModeView()
            }
        }
        .focusable()
        .digitalCrownRotation(
            detent: $crownHole,
            from: 1, through: session.totalHoles, by: 1,
            sensitivity: .low
        ) { _ in
        } onIdle: {
        }
        .onAppear { crownHole = session.holeNumber }
        .onChange(of: crownHole) { _, newValue in
            if newValue != session.holeNumber {
                session.navigateToHole(newValue)
            }
        }
        .onChange(of: session.holeNumber) { _, newValue in
            crownHole = newValue
        }
    }
}

// MARK: - Distance Mode

private struct DistanceModeView: View {
    @EnvironmentObject var session: WatchRoundSession

    var body: some View {
        VStack(spacing: 2) {
            DistanceRow(label: "F", yards: session.frontYards, style: .secondary)
            DistanceRow(label: "PIN", yards: session.pinYards, style: .primary)
            DistanceRow(label: "B", yards: session.backYards, style: .secondary)
        }

        Spacer(minLength: 4)

        Text("\(session.strokes)")
            .font(.caption).fontWeight(.bold)
            .foregroundStyle(.secondary)

        HStack(spacing: 8) {
            Button {
                session.markShot()
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "location.fill")
                        .font(.body)
                    Text("Shot")
                        .font(.system(size: 10))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Button {
                session.addStroke()
            } label: {
                VStack(spacing: 2) {
                    Text("+1")
                        .font(.body).fontWeight(.bold)
                    Text("Stroke")
                        .font(.system(size: 10))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Putt Mode

private struct PuttModeView: View {
    @EnvironmentObject var session: WatchRoundSession

    var body: some View {
        Spacer(minLength: 4)

        Text("\(session.pinYards ?? 0) yds")
            .font(.caption).foregroundStyle(.secondary)

        Text("\(session.putts)")
            .font(.system(size: 40, weight: .bold, design: .rounded))
            .foregroundStyle(.green)

        Text("Putts")
            .font(.caption).foregroundStyle(.secondary)

        Spacer(minLength: 4)

        HStack(spacing: 8) {
            Button {
                session.removePutt()
            } label: {
                Image(systemName: "minus")
                    .font(.title3).fontWeight(.bold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(session.putts == 0)

            Button {
                session.addPutt()
            } label: {
                Image(systemName: "plus")
                    .font(.title3).fontWeight(.bold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                session.confirmHole()
            } label: {
                Image(systemName: "checkmark")
                    .font(.title3).fontWeight(.bold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - End Round Page

private struct EndRoundPage: View {
    @EnvironmentObject var session: WatchRoundSession

    var body: some View {
        VStack(spacing: 12) {
            Text("\(session.totalStrokes)")
                .font(.system(size: 44, weight: .bold, design: .rounded))

            Text("Hole \(session.holeNumber) of \(session.totalHoles)")
                .font(.caption).foregroundStyle(.secondary)

            Button(role: .destructive) {
                session.finishRound()
            } label: {
                Label("End Round", systemImage: "flag.checkered")
                    .font(.caption).fontWeight(.semibold)
            }

            Button {
                session.cancelRound()
            } label: {
                Text("Cancel Round")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Round Ended

private struct RoundEndedView: View {
    @EnvironmentObject var session: WatchRoundSession

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "flag.fill")
                .font(.title2)
                .foregroundStyle(.green)

            Text(session.courseName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text("\(session.totalStrokes)")
                .font(.system(size: 48, weight: .bold, design: .rounded))

            Text("Round Saved")
                .font(.caption).foregroundStyle(.secondary)

            Button {
                session.resetToWaiting()
            } label: {
                Text("Done")
                    .font(.caption).fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
    }
}

// MARK: - Club Picker Overlay

private struct ClubPickerOverlay: View {
    @EnvironmentObject var session: WatchRoundSession
    @State private var crownIndex: Int = 0

    private var clubDisplayName: String {
        guard !session.clubBag.isEmpty else { return "?" }
        let raw = session.selectedClub
        // Map raw values to short display names
        let names: [String: String] = [
            "driver": "Driver", "3w": "3W", "5w": "5W",
            "3h": "3H", "4h": "4H", "5h": "5H",
            "4i": "4i", "5i": "5i", "6i": "6i",
            "7i": "7i", "8i": "8i", "9i": "9i",
            "pw": "PW", "gw": "GW", "sw": "SW",
            "lw": "LW", "putter": "Putter",
        ]
        return names[raw] ?? raw
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("Club")
                .font(.caption2).foregroundStyle(.secondary)

            Text(clubDisplayName)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.green)

            Button {
                session.confirmClub()
            } label: {
                Image(systemName: "checkmark")
                    .font(.title3).fontWeight(.bold)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.92))
        .focusable()
        .digitalCrownRotation(
            detent: $crownIndex,
            from: 0, through: max(session.clubBag.count - 1, 0), by: 1,
            sensitivity: .low
        ) { _ in } onIdle: { }
        .onAppear {
            crownIndex = session.clubBag.firstIndex(of: session.selectedClub) ?? 0
        }
        .onChange(of: crownIndex) { _, newValue in
            guard session.clubBag.indices.contains(newValue) else { return }
            session.selectedClub = session.clubBag[newValue]
        }
    }
}

// MARK: - Distance Row

private struct DistanceRow: View {
    let label: String
    let yards: Int?
    let style: DistanceStyle

    enum DistanceStyle { case primary, secondary }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: style == .primary ? 14 : 11))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            Text(yards.map { "\($0)" } ?? "—")
                .font(.system(size: style == .primary ? 36 : 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(style == .primary ? .green : .white)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
