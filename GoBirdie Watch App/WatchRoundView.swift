//
//  WatchRoundView.swift
//  GoBirdie Watch App

import SwiftUI

struct WatchRoundView: View {
    @EnvironmentObject var session: WatchRoundSession

    var body: some View {
        ZStack {
            if session.isSaving {
                SavingView()
            } else if session.isRoundEnded {
                RoundEndedView()
            } else if session.hasHoleData {
                RoundPagesView()
            } else {
                StartView()
            }

            if session.showClubPicker {
                ClubPickerOverlay()
            }
        }
        .alert("Move to Hole \(session.teeDetectionHole ?? 0)?", isPresented: Binding(
            get: { session.teeDetectionHole != nil },
            set: { if !$0 { session.teeDetectionHole = nil } }
        )) {
            if let hole = session.teeDetectionHole {
                Button("Move to Hole \(hole)") { session.confirmTeeDetection(holeNumber: hole) }
                Button("Stay", role: .cancel) { session.dismissTeeDetection(holeNumber: hole) }
            }
        } message: {
            if let hole = session.teeDetectionHole {
                Text("You're near the Hole \(hole) tee box.")
            }
        }
    }
}

// MARK: - Saving View

private struct SavingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)
            Text("Saving...")
                .font(.caption)
                .foregroundStyle(.secondary)
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

// MARK: - Round Pages

private struct RoundPagesView: View {
    @EnvironmentObject var session: WatchRoundSession
    @State private var showEndPage = false

    var body: some View {
        ZStack {
            if showEndPage {
                EndRoundPage(showEndPage: $showEndPage)
            } else {
                ActiveRoundView(showEndPage: $showEndPage)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showEndPage)
    }
}

// MARK: - Active Round

private struct ActiveRoundView: View {
    @EnvironmentObject var session: WatchRoundSession
    @Binding var showEndPage: Bool
    @State private var crownHole: Int = 1

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

            DistanceModeView()
        }
        .focusable()
        .digitalCrownRotation(
            detent: $crownHole,
            from: 1, through: session.totalHoles, by: 1,
            sensitivity: .low
        ) { _ in
        } onIdle: {
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    let h = value.translation.width
                    let v = value.translation.height
                    if abs(v) > abs(h) {
                        if v < -30 { showEndPage = true }
                    } else {
                        if h > 30, session.holeNumber > 1 {
                            session.navigateToHole(session.holeNumber - 1)
                        } else if h < -30, session.holeNumber < session.totalHoles {
                            session.navigateToHole(session.holeNumber + 1)
                        }
                    }
                }
        )
        .onAppear { crownHole = session.holeNumber }
        .onChange(of: crownHole) { newValue in
            if newValue != session.holeNumber {
                session.navigateToHole(newValue)
            }
        }
        .onChange(of: session.holeNumber) { newValue in
            crownHole = newValue
        }
    }
}

// MARK: - Distance Mode

private struct DistanceModeView: View {
    @EnvironmentObject var session: WatchRoundSession

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 0) {
                // FRONT COLUMN
                VStack(spacing: 0) {
                    Text("F")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("\(session.frontYards ?? 0)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // PIN COLUMN
                VStack(spacing: 0) {
                    Text("PIN")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    Text("\(session.pinYards ?? 0)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .layoutPriority(1)
                .frame(minWidth: 80, alignment: .center)

                // BACK COLUMN
                VStack(spacing: 0) {
                    Text("B")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("\(session.backYards ?? 0)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            
            HStack(spacing: 12) {
                VStack(spacing: 1) {
                    Text("\(session.strokes)")
                        .font(.system(size: 16, weight: .bold))
                    Text("Strokes")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 1) {
                    Text("\(session.putts)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                    Text("Putts")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 6) {
                Button {
                    session.markShot()
                } label: {
                    VStack(spacing: 1) {
                        Image(systemName: "location.fill")
                            .font(.body)
                        Text("Shot")
                            .font(.system(size: 12))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityIdentifier("watch_mark_shot")

                Button {
                    session.addPutt()
                } label: {
                    VStack(spacing: 1) {
                        Text("+1")
                            .font(.body).fontWeight(.bold)
                        Text("Putt")
                            .font(.system(size: 12))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("watch_add_putt")
            }
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
    @Binding var showEndPage: Bool

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
            .accessibilityIdentifier("end_round_menu_item")

            Button {
                session.cancelRound()
            } label: {
                Text("Cancel Round")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .gesture(
            DragGesture().onEnded { value in
                if value.translation.height > 30, abs(value.translation.height) > abs(value.translation.width) {
                    showEndPage = false
                }
            }
        )
    }
}

// MARK: - Round Ended

private struct RoundEndedView: View {
    @EnvironmentObject var session: WatchRoundSession
    @State private var countdown = 10
    @State private var timer: Timer? = nil

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
                dismiss()
            } label: {
                Text("Done (\(countdown)s)")
                    .font(.caption).fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .accessibilityIdentifier("watch_round_ended_done")
        }
        .onAppear { startCountdown() }
        .onDisappear { timer?.invalidate(); timer = nil }
    }

    private func startCountdown() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                countdown -= 1
                if countdown <= 0 { dismiss() }
            }
        }
    }

    private func dismiss() {
        timer?.invalidate(); timer = nil
        session.resetToWaiting()
    }
}

// MARK: - Club Picker Overlay

private struct ClubPickerOverlay: View {
    @EnvironmentObject var session: WatchRoundSession
    @State private var selectedIndex: Int = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 4) {
                Picker(selection: $selectedIndex, label: Text("Club")) {
                    ForEach(0..<session.clubBag.count, id: \.self) { idx in
                        Text(clubName(session.clubBag[idx]))
                            .font(.system(size: 48, weight: .semibold))
                            .tag(idx)
                    }
                }
                .pickerStyle(.wheel)
                .defaultWheelPickerItemHeight(60)
                .onChange(of: selectedIndex) {
                    guard session.clubBag.indices.contains(selectedIndex) else { return }
                    session.selectedClub = session.clubBag[selectedIndex]
                    session.resetClubPickerTimer()
                }
                .simultaneousGesture(TapGesture().onEnded {
                    session.confirmClub()
                })

                Text("\(session.clubPickerCountdown)s")
                    .font(.system(size: 11))
                    .foregroundStyle(.gray)
            }

            // Cancel button
            Button {
                session.cancelClubPicker()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.red)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(6)
            .accessibilityIdentifier("watch_club_cancel")
        }
        .onAppear {
            selectedIndex = session.clubBag.firstIndex(of: session.selectedClub) ?? 0
        }
    }

    private func clubName(_ raw: String) -> String {
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
