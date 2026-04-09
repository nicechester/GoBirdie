//
//  DistanceDisplayView.swift
//  GoBirdie

import SwiftUI
import GoBirdieCore

/// Three-column distance display: Front | Flag (center, large, green) | Back
struct DistanceDisplayView: View {
    let distances: DistanceEngine.Distances

    var body: some View {
        HStack(spacing: 0) {
            // Front
            DistanceColumn(
                label: "Front",
                value: distances.frontYards.map { "\($0)" } ?? "—",
                style: .secondary
            )

            // Flag — center, largest, green
            DistanceColumn(
                label: "Flag",
                value: distances.pinYards.map { "\($0)" } ?? "—",
                style: .primary
            )

            // Back
            DistanceColumn(
                label: "Back",
                value: distances.backYards.map { "\($0)" } ?? "—",
                style: .secondary
            )
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

private enum ColumnStyle { case primary, secondary }

private struct DistanceColumn: View {
    let label: String
    let value: String
    let style: ColumnStyle

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(
                    size: style == .primary ? 52 : 36,
                    weight: .bold,
                    design: .default
                ))
                .monospacedDigit()
                .foregroundStyle(style == .primary ? Color.green : Color.primary)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, style == .primary ? 20 : 16)
    }
}

#Preview {
    var distances = DistanceEngine.Distances()
    distances.frontYards = 187
    distances.pinYards = 204
    distances.backYards = 221
    return DistanceDisplayView(distances: distances)
        .padding()
        .background(Color.black)
}
