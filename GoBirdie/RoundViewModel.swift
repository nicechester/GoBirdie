//
//  RoundViewModel.swift
//  GoBirdie

import Foundation
import Combine
import SwiftUI
import GoBirdieCore

@MainActor
final class RoundViewModel: ObservableObject {
    @Published var session: RoundSession
    @Published var distances: DistanceEngine.Distances = DistanceEngine.Distances()
    @Published var course: Course

    let locationService: LocationService
    private let distanceEngine = DistanceEngine()
    private var cancellables = Set<AnyCancellable>()
    private var locationTask: Task<Void, Never>?

    // Resolved green per hole number — set on first distance computation
    private var resolvedGreens: [Int: GreenPolygon] = [:]
    // Resolved nearest tee per hole number — snapped from player GPS
    private var resolvedTees: [Int: GpsPoint] = [:]

    init(session: RoundSession, course: Course, locationService: LocationService, mockLocation: GpsPoint? = nil) {
        self.session = session
        self.course = course
        self.locationService = locationService

        session.$currentHoleIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recomputeDistances() }
            .store(in: &cancellables)

        locationTask = Task {
            while !Task.isCancelled {
                self.recomputeDistances()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        if let mock = mockLocation {
            let holeData = course.holes.first(where: { $0.number == session.currentHoleNumber })
            if let holeData { distances = distanceEngine.distances(from: mock, hole: holeData) }
        }
    }

    deinit { locationTask?.cancel() }

    func startRound() { locationService.start() }
    func stopRound()  { locationService.stop() }


    /// The resolved nearest OSM tee for the active hole, if any.
    var currentResolvedTee: GpsPoint? {
        resolvedTees[session.currentHoleNumber]
    }

    /// Current resolved green for the active hole, if any.
    var currentResolvedGreen: GreenPolygon? {
        resolvedGreens[session.currentHoleNumber]
    }

    private func recomputeDistances() {
        guard let location = locationService.currentLocation else { return }
        let holeNum = session.currentHoleNumber

        // Snap to nearest OSM tee, then resolve green from that tee position
        if resolvedTees[holeNum] == nil {
            resolveClosestTee(playerLocation: location, holeNumber: holeNum)
        }
        if resolvedGreens[holeNum] == nil {
            let teePos = resolvedTees[holeNum] ?? location
            resolveGreenFromTee(tee: teePos, holeNumber: holeNum)
        }

        if let green = resolvedGreens[holeNum] {
            let teePos = resolvedTees[holeNum] ?? location
            let (front, back) = green.frontAndBack(from: teePos)
            var d = DistanceEngine.Distances()
            d.frontYards = Int(distanceEngine.distanceYards(from: location, to: front).rounded())
            d.pinYards   = Int(distanceEngine.distanceYards(from: location, to: green.center).rounded())
            d.backYards  = Int(distanceEngine.distanceYards(from: location, to: back).rounded())
            distances = d
        } else if let holeData = course.holes.first(where: { $0.number == holeNum }) {
            distances = distanceEngine.distances(from: location, hole: holeData)
        }
    }

    /// Snap to the nearest OSM tee from the player's GPS position.
    private func resolveClosestTee(playerLocation: GpsPoint, holeNumber: Int) {
        guard !course.allTees.isEmpty else { return }
        let nearest = course.allTees.min { a, b in
            playerLocation.distanceMeters(to: a) < playerLocation.distanceMeters(to: b)
        }
        if let tee = nearest {
            resolvedTees[holeNumber] = tee
            let dist = Int(playerLocation.distanceMeters(to: tee) * 1.09361)
            print("[Tee] Hole \(holeNumber): snapped to tee at \(tee.lat),\(tee.lon) (\(dist)y from player)")
        }
    }

    /// Resolve the green by finding the green from allGreens whose center
    /// is closest to the target yardage from the tee position.
    private func resolveGreenFromTee(tee: GpsPoint, holeNumber: Int) {
        guard let holeData = course.holes.first(where: { $0.number == holeNumber }),
              let yardageStr = holeData.yardage,
              let targetYards = Int(yardageStr) else { return }

        if let green = GreenPolygon.best(from: course.allGreens, tee: tee, targetYards: targetYards) {
            resolvedGreens[holeNumber] = green
            let actual = Int(tee.distanceMeters(to: green.center) * 1.09361)
            print("[Green] Hole \(holeNumber): resolved from tee (target=\(targetYards)y actual=\(actual)y)")
        }
    }
}
