//
//  LocationService.swift
//  GoBirdie
//
//  Created by Kim, Chester on 4/8/26.
//

import Foundation
import Combine
import CoreLocation
import UIKit
import GoBirdieCore

/// Provides real-time GPS location updates during a round.
/// Uses CLLocationManager with high accuracy for golf tracking.
@MainActor
final class LocationService: NSObject, ObservableObject {
    @Published var currentLocation: GpsPoint?
    @Published var isRunning: Bool = false

    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        setupLocationManager()
    }

    // MARK: - Public API

    /// Request location permission without starting updates.
    /// Call at app launch so iOS shows Location in Settings.
    func requestPermission() {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    /// Start monitoring location updates.
    /// Requests permission if needed.
    func start() {
        guard !isRunning else { return }

        let authStatus = locationManager.authorizationStatus
        switch authStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            return
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
            isRunning = true
        @unknown default:
            break
        }
    }

    /// Returns true if location is fully authorized for continuous use (not just "When Shared").
    var isFullyAuthorized: Bool {
        let status = locationManager.authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    /// Opens the app's Settings page so the user can change to "While Using".
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        Task { @MainActor in
            await UIApplication.shared.open(url)
        }
    }

    /// Stop monitoring location updates.
    func stop() {
        guard isRunning else { return }
        locationManager.stopUpdatingLocation()
        isRunning = false
    }

    // MARK: - Private

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5.0 // Update every 5 meters to reduce CPU usage
        locationManager.activityType = .other // Golf activity
        locationManager.pausesLocationUpdatesAutomatically = false
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }

        let gpsPoint = GpsPoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude)

        Task { @MainActor in
            self.currentLocation = gpsPoint
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        // Location manager encountered an error, but we continue monitoring
        let nsError = error as NSError
        if nsError.code != CLError.locationUnknown.rawValue {
            print("[LocationService] Location error: \(error.localizedDescription)")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let authStatus = manager.authorizationStatus
        Task { @MainActor in
            switch authStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                if !self.isRunning {
                    manager.startUpdatingLocation()
                    self.isRunning = true
                }
            case .restricted, .denied:
                if self.isRunning {
                    manager.stopUpdatingLocation()
                    self.isRunning = false
                }
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }
}
