//
//  ClubBag.swift
//  GoBirdie

import Foundation
import Combine
import GoBirdieCore

/// Persists the user's club selection in UserDefaults.
/// Clubs in the bag appear in the Mark Shot picker.
@MainActor
final class ClubBag: ObservableObject {
    static let shared = ClubBag()

    @Published var enabledClubs: [ClubType] {
        didSet { save() }
    }

    private let key = "clubBag"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let rawValues = try? JSONDecoder().decode([String].self, from: data) {
            // Load from storage, filtering out putter
            enabledClubs = rawValues.compactMap { ClubType(rawValue: $0) }.filter { $0 != .putter }
        } else {
            enabledClubs = ClubType.defaultBag
        }
    }

    func isEnabled(_ club: ClubType) -> Bool {
        enabledClubs.contains(club)
    }

    func toggle(_ club: ClubType) {
        guard club != .putter else { return }  // Prevent putter from being toggled

        if let idx = enabledClubs.firstIndex(of: club) {
            enabledClubs.remove(at: idx)
        } else {
            // Insert in canonical order
            let allOrder = ClubType.allSelectable
            let insertIndex = enabledClubs.firstIndex(where: {
                (allOrder.firstIndex(of: $0) ?? 0) > (allOrder.firstIndex(of: club) ?? 0)
            }) ?? enabledClubs.endIndex
            enabledClubs.insert(club, at: insertIndex)
        }
    }

    func resetToDefault() {
        enabledClubs = ClubType.defaultBag
    }

    private func save() {
        let rawValues = enabledClubs.map(\.rawValue)
        if let data = try? JSONEncoder().encode(rawValues) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
