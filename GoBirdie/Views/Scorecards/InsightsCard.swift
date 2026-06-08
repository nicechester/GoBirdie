//
//  InsightsCard.swift
//  GoBirdie

import SwiftUI
import GoBirdieCore

struct InsightsCard: View {
    let round: Round
    let courseHoles: [Hole]
    var historicalRounds: [Round] = []
    var baseline: SGBaseline = .bogey

    private var insights: [RoundInsight] {
        RoundInsightsEngine.generate(
            round: round,
            courseHoles: courseHoles,
            historicalRounds: historicalRounds,
            baseline: baseline
        )
    }

    var body: some View {
        let items = insights
        if items.isEmpty { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("Key Insights", systemImage: "lightbulb.fill")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("vs \(baseline.displayName)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 8)

                ForEach(Array(items.enumerated()), id: \.offset) { _, insight in
                    HStack(alignment: .top, spacing: 8) {
                        Text(icon(for: insight.severity))
                            .font(.caption)
                        Text(insight.message)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 5)
                    if insight.code != items.last?.code {
                        Divider()
                    }
                }
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal, 16)
        )
    }

    private func icon(for severity: RoundInsight.Severity) -> String {
        switch severity {
        case .critical: return "🔴"
        case .warning:  return "🟡"
        case .positive: return "🟢"
        case .info:     return "🔵"
        }
    }
}
