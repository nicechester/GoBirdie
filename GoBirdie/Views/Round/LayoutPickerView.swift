//
//  LayoutPickerView.swift
//  GoBirdie
//

import SwiftUI
import GoBirdieCore

/// Picks the layouts of a multi-course complex: one layout for a 9-hole round, two for an 18-hole round.
/// Shared by start round and course explore.
struct LayoutPickerView: View {
    let layouts: [Course]
    /// Called with one or two layouts, in the order they were picked.
    let onPick: ([Course]) -> Void

    @State private var pickedIds: [String] = []

    var body: some View {
        VStack(spacing: 16) {
            Text("layout.pickPrompt".localized)
                .font(.headline)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                ForEach(layouts, id: \.id) { layout in
                    layoutRow(layout)
                }
            }

            Button {
                onPick(pickedLayouts)
            } label: {
                Text(startTitle)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(pickedIds.isEmpty ? Color(.systemGray4) : Color.green)
                    .foregroundStyle(.white)
                    .cornerRadius(10)
            }
            .disabled(pickedIds.isEmpty)
        }
        .padding(.vertical, 16)
    }

    private var pickedLayouts: [Course] {
        pickedIds.compactMap { id in layouts.first { $0.id == id } }
    }

    private var startTitle: String {
        switch pickedIds.count {
        case 2: return "layout.start18".localized
        case 1: return "layout.start9".localized
        default: return "layout.choose".localized
        }
    }

    private func layoutRow(_ layout: Course) -> some View {
        let order = pickedIds.firstIndex(of: layout.id)
        return Button {
            toggle(layout.id)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(CourseLayouts.layoutName(layout.name))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("layout.holes".localized(with: layout.holes.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let order {
                    Text("\(order + 1)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.green))
                }
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ id: String) {
        if let index = pickedIds.firstIndex(of: id) {
            pickedIds.remove(at: index)
        } else if pickedIds.count < 2 {
            pickedIds.append(id)
        }
    }
}
