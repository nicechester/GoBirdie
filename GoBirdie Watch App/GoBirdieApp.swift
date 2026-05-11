//
//  GoBirdieApp.swift
//  GoBirdie Watch App

import SwiftUI

@main
struct GoBirdie_Watch_AppApp: App {
    @StateObject private var session = WatchRoundSession()
    @StateObject private var snapshotStore = WatchSnapshotStore.shared

    var body: some Scene {
        WindowGroup {
            WatchRoundView()
                .environmentObject(session)
                .environmentObject(snapshotStore)
                #if targetEnvironment(simulator)
                .task {
                    snapshotStore.loadBundledSnapshots()
                }
                #endif
        }
    }
}
