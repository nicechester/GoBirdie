//
//  GoBirdieApp.swift
//  GoBirdie
//
//  Created by Kim, Chester on 4/8/26.
//

import SwiftUI

@main
struct GoBirdieApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    appState.getLocationService().requestPermission()
                }
        }
    }
}
