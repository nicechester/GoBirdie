//
//  HoleMapView.swift
//  GoBirdie Watch App
//

import SwiftUI

struct HoleMapView: View {
    @EnvironmentObject var session: WatchRoundSession
    @State private var snapshot: HoleMapSnapshot?

    var body: some View {
        ZStack {
            if let image = snapshot?.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            } else {
                VStack {
                    Image(systemName: "map.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.gray)
                    Text("No map")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Hole \(session.holeNumber)")
                        .font(.caption).fontWeight(.bold)
                    Spacer()
                    Text("Par \(session.par)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.7))

                Spacer()
            }
        }
        .onChange(of: session.holeNumber) { _ in
            loadSnapshot()
        }
        .onAppear {
            loadSnapshot()
        }
    }

    private func loadSnapshot() {
        snapshot = HoleMapSnapshotLoader.shared.loadSnapshot(for: session.holeNumber)
    }
}

#Preview {
    HoleMapView()
        .environmentObject(WatchRoundSession())
}
