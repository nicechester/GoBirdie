//
//  RoundLiveActivityWidget.swift
//  GoBirdie
//

import ActivityKit
import SwiftUI
import WidgetKit

struct RoundLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GoBirdieRoundAttributes.self) { context in
            // Lock Screen / StandBy view
            Link(destination: URL(string: "gobirdie://round")!) {
                HStack(spacing: 16) {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.courseName)
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Hole \(context.state.holeNumber) of \(context.state.totalHoles)")
                            .font(.headline)
                    }
                    Spacer()
                    Text(context.state.scoreLabel)
                        .font(.title2.bold())
                        .foregroundStyle(scoreColor(context.state.scoreVsPar))
                }
                .padding()
                .activityBackgroundTint(.black.opacity(0.8))
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Hole \(context.state.holeNumber)", systemImage: "flag.fill")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.scoreLabel)
                        .font(.title2.bold())
                        .foregroundStyle(scoreColor(context.state.scoreVsPar))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.courseName)
                        .font(.caption).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "flag.fill").foregroundStyle(.green)
            } compactTrailing: {
                Text(context.state.scoreLabel)
                    .font(.caption.bold())
                    .foregroundStyle(scoreColor(context.state.scoreVsPar))
            } minimal: {
                Image(systemName: "flag.fill").foregroundStyle(.green)
            }
            .widgetURL(URL(string: "gobirdie://round"))
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score < 0 { return .red }
        if score == 0 { return .primary }
        return .blue
    }
}
