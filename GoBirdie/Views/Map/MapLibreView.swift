//
//  MapLibreView.swift
//  GoBirdie
//
//  Created by Kim, Chester on 4/8/26.
//

import SwiftUI
import MapLibre
import CoreLocation
import Combine
import GoBirdieCore

struct MapLibreView: UIViewRepresentable {
    let viewModel: MapViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero)
        mapView.delegate = context.coordinator

        let styleJSON = """
        {
            "version": 8,
            "sources": {
                "osm": {
                    "type": "raster",
                    "tiles": ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
                    "tileSize": 256,
                    "attribution": "© OpenStreetMap contributors"
                }
            },
            "layers": [{"id": "osm", "type": "raster", "source": "osm"}]
        }
        """
        if let data = styleJSON.data(using: .utf8),
           let url = try? writeStyleToTemp(data: data) {
            mapView.styleURL = url
        }

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tapGesture)

        context.coordinator.mapView = mapView
        return mapView
    }

    private func writeStyleToTemp(data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gobirdie-style.json")
        try data.write(to: url)
        return url
    }

    func updateUIView(_ uiView: MLNMapView, context: Context) {
        context.coordinator.viewModel = viewModel

        // Satellite toggle
        updateTileSource(uiView, context: context, isSatellite: viewModel.isSatellite)

        // Camera on hole change
        let newHoleIndex = viewModel.currentHoleIndex
        if context.coordinator.lastHoleIndex != newHoleIndex {
            context.coordinator.lastHoleIndex = newHoleIndex
            context.coordinator.zoomToHole(uiView, animated: true)
        }

        // Golf geometry layers
        if let style = uiView.style {
            updateGolfLayers(style, hole: viewModel.currentHole)
        }

        // Project GPS → screen for SwiftUI overlay
        context.coordinator.updateScreenPoints()
    }

    // MARK: - Tile Source

    private func updateTileSource(_ mapView: MLNMapView, context: Context, isSatellite: Bool) {
        guard context.coordinator.lastSatelliteState != isSatellite else { return }
        context.coordinator.lastSatelliteState = isSatellite

        let tileURL = isSatellite
            ? "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
            : "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
        let attribution = isSatellite ? "Esri" : "OpenStreetMap contributors"
        let styleJSON = """
        {
            "version": 8,
            "sources": {
                "osm": {
                    "type": "raster",
                    "tiles": ["\(tileURL)"],
                    "tileSize": 256,
                    "attribution": "\(attribution)"
                }
            },
            "layers": [{"id": "osm", "type": "raster", "source": "osm"}]
        }
        """
        if let data = styleJSON.data(using: .utf8),
           let url = try? writeStyleToTemp(data: data) {
            mapView.styleURL = url
        }
    }

    // MARK: - Golf Layers

    private func updateGolfLayers(_ style: MLNStyle, hole: Hole?) {
        guard let geometry = hole?.geometry else {
            removeGolfLayers(from: style)
            return
        }

        let sourceID = "golf-geometry"
        if let existing = style.source(withIdentifier: sourceID) {
            style.removeSource(existing)
        }
        removeGolfLayers(from: style)

        let source = HoleGeoJSONBuilder.makeSource(for: geometry, sourceID: sourceID)
        style.addSource(source)

        addGolfLayer(to: style, sourceID: sourceID, type: "water", color: UIColor(hex: "#4A90D9"), opacity: 0.6)
        addGolfLayer(to: style, sourceID: sourceID, type: "rough", color: UIColor(hex: "#7CB87C"), opacity: 0.5)
        addGolfLayer(to: style, sourceID: sourceID, type: "bunker", color: UIColor(hex: "#D4B96A"), opacity: 0.7)
        addGolfLayer(to: style, sourceID: sourceID, type: "fairway", color: UIColor(hex: "#2E7D32"), opacity: 0.5)
    }

    private func addGolfLayer(to style: MLNStyle, sourceID: String, type: String, color: UIColor, opacity: CGFloat) {
        guard let source = style.source(withIdentifier: sourceID) else { return }
        let layerID = "golf-\(type)"
        let layer = MLNFillStyleLayer(identifier: layerID, source: source)
        layer.predicate = NSPredicate(format: "featureType == %@", type)
        layer.fillColor = NSExpression(forConstantValue: color)
        layer.fillOpacity = NSExpression(forConstantValue: opacity)
        style.addLayer(layer)
    }

    private func removeGolfLayers(from style: MLNStyle) {
        for layerID in ["golf-water", "golf-rough", "golf-bunker", "golf-fairway"] {
            if let layer = style.layer(withIdentifier: layerID) { style.removeLayer(layer) }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var viewModel: MapViewModel
        var lastHoleIndex: Int = -1
        var lastSatelliteState: Bool? = nil
        weak var mapView: MLNMapView?
        private var cancellables = Set<AnyCancellable>()

        init(viewModel: MapViewModel) {
            self.viewModel = viewModel
            super.init()
            viewModel.$currentHoleIndex
                .receive(on: DispatchQueue.main)
                .sink { [weak self] index in
                    guard let self, let mapView = self.mapView, self.lastHoleIndex != index else { return }
                    self.lastHoleIndex = index
                    self.zoomToHole(mapView, animated: true)
                    self.updateScreenPoints()
                }
                .store(in: &cancellables)
            viewModel.$playerLocation
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.updateScreenPoints() }
                .store(in: &cancellables)

            viewModel.session.$round
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.updateScreenPoints() }
                .store(in: &cancellables)
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            let parent = MapLibreView(viewModel: viewModel)
            parent.updateGolfLayers(style, hole: viewModel.currentHole)
            zoomToHole(mapView, animated: lastHoleIndex == -1 ? false : true)
            lastHoleIndex = viewModel.currentHoleIndex
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            updateScreenPoints()
        }

        func updateScreenPoints() {
            guard let mapView else { return }

            if let loc = viewModel.playerLocation ?? viewModel.mockLocation {
                let coord = CLLocationCoordinate2D(latitude: loc.lat, longitude: loc.lon)
                let pt = mapView.convert(coord, toPointTo: mapView)
                viewModel.playerScreenPoint = pt
            } else {
                viewModel.playerScreenPoint = nil
            }

            if let green = viewModel.resolvedGreenCenter ?? viewModel.currentHole?.greenCenter {
                let coord = CLLocationCoordinate2D(latitude: green.lat, longitude: green.lon)
                let pt = mapView.convert(coord, toPointTo: mapView)
                viewModel.flagScreenPoint = pt
            } else {
                viewModel.flagScreenPoint = nil
            }

            if let tap = viewModel.selectedTapPoint {
                let coord = CLLocationCoordinate2D(latitude: tap.lat, longitude: tap.lon)
                let pt = mapView.convert(coord, toPointTo: mapView)
                viewModel.tapScreenPoint = pt
            } else {
                viewModel.tapScreenPoint = nil
            }

            viewModel.shotScreenPoints = viewModel.currentHoleShots.compactMap { shot in
                let coord = CLLocationCoordinate2D(latitude: shot.location.lat, longitude: shot.location.lon)
                let pt = mapView.convert(coord, toPointTo: mapView)
                return (point: pt, shot: shot)
            }
        }

        func zoomToHole(_ mapView: MLNMapView, animated: Bool) {
            if let bounds = viewModel.holeBounds {
                let sw = CLLocationCoordinate2D(latitude: bounds.sw.lat, longitude: bounds.sw.lon)
                let ne = CLLocationCoordinate2D(latitude: bounds.ne.lat, longitude: bounds.ne.lon)
                let coordinateBounds = MLNCoordinateBounds(sw: sw, ne: ne)
                let heading = viewModel.teeToPinBearing ?? 0
                let camera = mapView.cameraThatFitsCoordinateBounds(
                    coordinateBounds,
                    edgePadding: UIEdgeInsets(top: 5, left: 1, bottom: 5, right: 1)
                )
                camera.heading = heading
                mapView.setCamera(camera, animated: animated)
            } else {
                let target = viewModel.cameraBounds
                guard target.lat != 0 || target.lon != 0 else { return }
                let camera = MLNMapCamera(
                    lookingAtCenter: CLLocationCoordinate2D(latitude: target.lat, longitude: target.lon),
                    altitude: 400, pitch: 0, heading: 0
                )
                mapView.setCamera(camera, animated: animated)
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MLNMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            let tapPoint = GpsPoint(lat: coordinate.latitude, lon: coordinate.longitude)

            Task { @MainActor in
                guard self.viewModel.locationService.currentLocation != nil || self.viewModel.mockLocation != nil else {
                    self.viewModel.selectedTapPoint = tapPoint
                    self.viewModel.tapDistanceYards = nil
                    return
                }
                self.viewModel.handleTap(at: tapPoint)
                self.updateScreenPoints()
            }
        }
    }
}

// MARK: - UIColor Hex

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        self.init(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: 1.0
        )
    }
}
