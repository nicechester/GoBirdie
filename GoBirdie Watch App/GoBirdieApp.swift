//
//  GoBirdieApp.swift
//  GoBirdie Watch App

import SwiftUI

@main
struct GoBirdie_Watch_AppApp: App {
    @StateObject private var session = WatchRoundSession()

    var body: some Scene {
        WindowGroup {
            WatchRoundView()
                .environmentObject(session)
        }
    }
}
