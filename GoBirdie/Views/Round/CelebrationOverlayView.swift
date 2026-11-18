//
//  CelebrationOverlayView.swift
//  GoBirdie
//

import SwiftUI
import GoBirdieCore
import UIKit

/// A hole-score moment shown when the user taps Next after scoring eagle, birdie, or par.
enum ScoreCelebration: Hashable {
    case eagle
    case birdie
    case par

    /// Returns nil for bogey or worse, and for holes with no strokes entered yet
    /// (tapping Next on an unscored hole would otherwise read as a false eagle).
    init?(hole: HoleScore) {
        guard hole.strokes > 0 else { return nil }
        switch hole.scoreVsPar {
        case ...(-2): self = .eagle
        case -1: self = .birdie
        case 0: self = .par
        default: return nil
        }
    }

    var message: String {
        switch self {
        case .eagle: return "celebration.eagle".localized
        case .birdie: return "celebration.birdie".localized
        case .par: return "celebration.par".localized
        }
    }

    var color: Color {
        switch self {
        case .eagle: return Color(red: 0.90, green: 0.55, blue: 0.00)
        case .birdie: return Color(red: 0.80, green: 0.62, blue: 0.00)
        case .par: return Color(red: 0.13, green: 0.55, blue: 0.23)
        }
    }
}

/// Brief, non-interactive celebration for a hole score. Removes itself by calling `onFinish`.
struct CelebrationOverlayView: View {
    let celebration: ScoreCelebration
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var faded = false
    @State private var burst = false

    var body: some View {
        ZStack {
            // Confetti only for birdie or better, and never when Reduce Motion is on.
            if celebration != .par && !reduceMotion {
                ConfettiBurst(active: burst, color: celebration.color)
            }

            Text(celebration.message)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(celebration.color)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: Capsule())
                .scaleEffect(appeared ? 1.0 : 0.6)
                .opacity(faded ? 0 : 1)
        }
        .allowsHitTesting(false)
        .task {
            UINotificationFeedbackGenerator().notificationOccurred(.success)

            if reduceMotion {
                withAnimation(.easeOut(duration: 0.2)) { appeared = true }
            } else {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { appeared = true }
                burst = true
            }

            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.easeIn(duration: 0.3)) { faded = true }
            try? await Task.sleep(nanoseconds: 300_000_000)
            onFinish()
        }
    }
}

/// Small shapes that fly outward from the center and fade.
private struct ConfettiBurst: View {
    let active: Bool
    let color: Color

    @State private var particles: [Particle] = (0..<24).map { _ in Particle.random() }

    struct Particle: Identifiable {
        let id = UUID()
        let angle: Double
        let distance: CGFloat
        let rotation: Double
        let size: CGFloat
        let useSparkle: Bool

        static func random() -> Particle {
            Particle(
                angle: Double.random(in: 0..<(2 * .pi)),
                distance: CGFloat.random(in: 90...170),
                rotation: Double.random(in: -270...270),
                size: CGFloat.random(in: 6...11),
                useSparkle: Bool.random()
            )
        }
    }

    var body: some View {
        ZStack {
            ForEach(particles) { p in
                Group {
                    if p.useSparkle {
                        Image(systemName: "sparkle")
                            .font(.system(size: p.size * 1.6, weight: .bold))
                    } else {
                        Circle().frame(width: p.size, height: p.size)
                    }
                }
                .foregroundStyle(color)
                .rotationEffect(.degrees(active ? p.rotation : 0))
                .offset(
                    x: active ? cos(p.angle) * p.distance : 0,
                    y: active ? sin(p.angle) * p.distance : 0
                )
                .opacity(active ? 0 : 1)
            }
        }
        .animation(.easeOut(duration: 0.8), value: active)
    }
}
