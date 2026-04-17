//
//  MyClubsView.swift
//  GoBirdie

import SwiftUI
import GoBirdieCore

struct MyClubsView: View {
    @ObservedObject private var bag = ClubBag.shared

    var body: some View {
        List {
            Section {
                ForEach(ClubType.allSelectable, id: \.self) { club in
                    Button {
                        bag.toggle(club)
                    } label: {
                        HStack {
                            Text(club.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if bag.isEnabled(club) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            } footer: {
                Text("Selected clubs appear in the Mark Shot picker during a round.")
            }

            Section {
                Button("Reset to Default") {
                    bag.resetToDefault()
                }
            }
        }
        .navigationTitle("My Clubs")
        .navigationBarTitleDisplayMode(.inline)
    }
}
