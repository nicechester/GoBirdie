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
    private weak var appState: AppState?
    private var locationTask: Task<Void, Never>?



    init(session: RoundSession, course: Course, locationService: LocationService, mockLocation: GpsPoint? = nil, appState: AppState? = nil) {
        self.session = session
        self.course = course
        self.locationService = locationService
        self.appState = appState

        session.$currentHoleIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recomputeDistances() }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: .watchNavigateHole, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let holeNumber = notification.userInfo?["holeNumber"] as? Int else { return }
            self.session.navigateTo(holeNumber: holeNumber, course: self.course)
        }

        locationTask = Task {
            while !Task.isCancelled {
                self.recomputeDistances()
                if let loc = locationService.currentLocation {
                    appState?.checkTeeProximity(location: loc, course: course, currentHoleNumber: session.currentHoleNumber)
                }
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


    private func recomputeDistances() {
        guard let location = locationService.currentLocation,
              let holeData = course.holes.first(where: { $0.number == session.currentHoleNumber }) else { return }
        distances = distanceEngine.distances(from: location, hole: holeData)
    }
}
