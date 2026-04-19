//
//  MapViewModel.swift
//  GoBirdie
//
//  Created by Kim, Chester on 4/8/26.
//

import Foundation
import Combine
import SwiftUI
import GoBirdieCore

/// Manages map view state including hole navigation, tap points, and display modes.
/// Stays synchronized with RoundSession.currentHoleIndex via Combine.
@MainActor
final class MapViewModel: ObservableObject {
    @Published var selectedTapPoint: GpsPoint?
    @Published var tapDistanceYards: Int?
    @Published var tapToGreenYards: Int?
    @Published var playerToGreenYards: Int?
    @Published var isSatellite: Bool = false
    @Published var currentHoleIndex: Int = 0
    @Published var playerLocation: GpsPoint?

    // Screen-space points updated by MapLibreView coordinator
    @Published var playerScreenPoint: CGPoint?
    @Published var flagScreenPoint: CGPoint?
    @Published var tapScreenPoint: CGPoint?
    @Published var shotScreenPoints: [(point: CGPoint, shot: Shot)] = []

    let session: RoundSession?
    let course: Course
    let locationService: LocationService
    let mockLocation: GpsPoint?

    private let distanceEngine = DistanceEngine()
    private var cancellables = Set<AnyCancellable>()
    private var tapPlayerLocation: GpsPoint?
    private let tapClearThresholdYards: Double = 15

    init(
        session: RoundSession?,
        course: Course,
        locationService: LocationService,
        mockLocation: GpsPoint? = nil
    ) {
        self.session = session
        self.course = course
        self.locationService = locationService
        self.mockLocation = mockLocation
        self.currentHoleIndex = session?.currentHoleIndex ?? 0

        if let session {
            session.$currentHoleIndex
                .receive(on: DispatchQueue.main)
                .sink { [weak self] index in
                    self?.currentHoleIndex = index
                    self?.updatePlayerToGreen()
                }
                .store(in: &cancellables)
        }

        locationService.$currentLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loc in
                self?.playerLocation = loc
                self?.updatePlayerToGreen()
                self?.clearTapIfPlayerMoved(loc)
            }
            .store(in: &cancellables)
    }

    init(course: Course, locationService: LocationService, mockLocation: GpsPoint? = nil) {
        self.session = nil
        self.course = course
        self.locationService = locationService
        self.mockLocation = mockLocation
        self.currentHoleIndex = 0

        locationService.$currentLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loc in
                self?.playerLocation = loc
                self?.updatePlayerToGreen()
                self?.clearTapIfPlayerMoved(loc)
            }
            .store(in: &cancellables)
    }

    // MARK: - Computed Properties

    var currentHole: Hole? {
        guard course.holes.indices.contains(currentHoleIndex) else { return nil }
        return course.holes[currentHoleIndex]
    }

    var currentHoleShots: [Shot] {
        guard let session else { return [] }
        return session.round.holes.first(where: { $0.number == currentHoleIndex + 1 })?.shots ?? []
    }

    /// Tee for the current hole.
    var resolvedTee: GpsPoint? {
        currentHole?.tee
    }

    /// Green center for the current hole.
    var resolvedGreenCenter: GpsPoint? {
        currentHole?.greenCenter
    }

    /// Bearing from tee to green in degrees (0 = north, 90 = east).
    var teeToPinBearing: Double? {
        guard let tee = resolvedTee, let green = resolvedGreenCenter else { return nil }
        let dLon = (green.lon - tee.lon) * .pi / 180
        let lat1 = tee.lat * .pi / 180
        let lat2 = green.lat * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }

    var cameraBounds: GpsPoint {
        resolvedTee ?? currentHole?.greenCenter ?? course.location
    }

    /// Bounding box that fits tee and green for the current hole.
    var holeBounds: (sw: GpsPoint, ne: GpsPoint)? {
        var points: [GpsPoint] = []
        if let tee = resolvedTee { points.append(tee) }
        if let green = resolvedGreenCenter { points.append(green) }
        // Fall back to hole data
        if points.count < 2, let hole = currentHole {
            points.append(contentsOf: [hole.tee, hole.greenCenter].compactMap { $0 })
        }
        guard points.count >= 2 else { return nil }
        let minLat = points.map(\.lat).min()!
        let maxLat = points.map(\.lat).max()!
        let minLon = points.map(\.lon).min()!
        let maxLon = points.map(\.lon).max()!
        let pad = 0.0003
        return (
            sw: GpsPoint(lat: minLat - pad, lon: minLon - pad),
            ne: GpsPoint(lat: maxLat + pad, lon: maxLon + pad)
        )
    }

    // MARK: - Public API

    /// Clear tap state back to default (player → green line).
    func clearTap() {
        selectedTapPoint = nil
        tapDistanceYards = nil
        tapToGreenYards = nil
        tapScreenPoint = nil
        tapPlayerLocation = nil
    }

    /// Resets the map's displayed hole to match the round's current hole.
    /// Call this whenever the user navigates back to the map tab.
    func syncToSession() {
        guard let session else { return }
        guard currentHoleIndex != session.currentHoleIndex else { return }
        currentHoleIndex = session.currentHoleIndex
        clearTap()
    }

    private func clearTapIfPlayerMoved(_ newLoc: GpsPoint?) {
        guard let origin = tapPlayerLocation, let loc = newLoc, selectedTapPoint != nil else { return }
        if distanceEngine.distanceYards(from: origin, to: loc) > tapClearThresholdYards {
            clearTap()
        }
    }

    /// Handle a tap on the map.
    func handleTap(at tapPoint: GpsPoint) {
        selectedTapPoint = tapPoint
        tapPlayerLocation = mockLocation ?? locationService.currentLocation

        let playerLocation = mockLocation ?? locationService.currentLocation ?? tapPoint
        let yardage = distanceEngine.distanceYards(from: playerLocation, to: tapPoint)
        tapDistanceYards = Int(yardage.rounded())

        // Distance from tap point to green center
        if let green = resolvedGreenCenter ?? currentHole?.greenCenter {
            let toGreen = distanceEngine.distanceYards(from: tapPoint, to: green)
            tapToGreenYards = Int(toGreen.rounded())
        } else {
            tapToGreenYards = nil
        }
    }

    /// Navigate to the previous hole.
    func navigatePrevious() {
        guard currentHoleIndex > 0 else { return }
        currentHoleIndex -= 1
        clearTap()
    }

    func navigateNext() {
        guard currentHoleIndex < course.holes.count - 1 else { return }
        currentHoleIndex += 1
        clearTap()
    }

    private func updatePlayerToGreen() {
        guard let loc = playerLocation ?? mockLocation,
              let green = resolvedGreenCenter ?? currentHole?.greenCenter else {
            playerToGreenYards = nil
            return
        }
        playerToGreenYards = Int(distanceEngine.distanceYards(from: loc, to: green).rounded())
    }
}
