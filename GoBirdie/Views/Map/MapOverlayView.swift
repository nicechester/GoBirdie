//
//  MapOverlayView.swift
//  GoBirdie

import SwiftUI
import GoBirdieCore

struct MapOverlayView: View {
    @ObservedObject var viewModel: MapViewModel
    @State private var pulseScale: CGFloat = 0.5
    @State private var pulseOpacity: Double = 0.6

    private var hasTap: Bool { viewModel.selectedTapPoint != nil }

    var body: some View {
        GeometryReader { _ in
            let playerPt = viewModel.playerScreenPoint
            let flagPt = viewModel.flagScreenPoint
            let tapPt = viewModel.tapScreenPoint

            if hasTap {
                // Tapped state: player → tap + tap → green
                if let from = playerPt, let to = tapPt {
                    DottedLineWithLabel(from: from, to: to, yardage: viewModel.tapDistanceYards, color: .white)
                }
                if let from = tapPt, let to = flagPt {
                    DottedLineWithLabel(from: from, to: to, yardage: viewModel.tapToGreenYards, color: .green)
                }
                // Tap point dot
                if let pt = tapPt {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1))
                        .position(pt)
                }
            } else {
                // Default: player → green
                if let from = playerPt, let to = flagPt {
                    DottedLineWithLabel(from: from, to: to, yardage: viewModel.playerToGreenYards, color: .white)
                }
            }

            // Flag dot
            if let pt = flagPt {
                Circle()
                    .fill(Color.green)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    .position(pt)
            }

            // Player glowing dot
            if let pt = playerPt {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.25))
                        .frame(width: 44, height: 44)
                        .scaleEffect(pulseScale)
                        .opacity(pulseOpacity)

                    Circle()
                        .fill(Color.blue)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                        .shadow(color: .blue.opacity(0.6), radius: 6)
                }
                .position(pt)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                        pulseScale = 1.0
                        pulseOpacity = 0.0
                    }
                }
            }
        }
    }
}

private struct DottedLineWithLabel: View {
    let from: CGPoint
    let to: CGPoint
    let yardage: Int?
    let color: Color

    var body: some View {
        ZStack {
            DashedLine(from: from, to: to)
                .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .shadow(color: .black.opacity(0.4), radius: 1)

            if let yds = yardage {
                let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
                Text("\(yds)")
                    .font(.caption2).fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(4)
                    .position(mid)
            }
        }
    }
}

private struct DashedLine: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: from)
        p.addLine(to: to)
        return p
    }
}
