//
//  ShotMapView.swift
//  GoBirdie

import SwiftUI
import MapLibre
import GoBirdieCore

/// Read-only map showing shot locations for one or more holes.
struct ShotMapView: UIViewRepresentable {
    let holes: [HoleScore]
    let courseHoles: [Hole]

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false

        let styleJSON = """
        {
            "version": 8,
            "sources": {
                "osm": {
                    "type": "raster",
                    "tiles": ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
                    "tileSize": 256
                }
            },
            "layers": [{"id": "osm", "type": "raster", "source": "osm"}]
        }
        """
        if let data = styleJSON.data(using: .utf8) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("shotmap-style.json")
            try? data.write(to: url)
            mapView.styleURL = url
        }

        context.coordinator.mapView = mapView
        return mapView
    }

    func updateUIView(_ uiView: MLNMapView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(holes: holes, courseHoles: courseHoles)
    }

    class Coordinator: NSObject, MLNMapViewDelegate {
        var mapView: MLNMapView?
        let holes: [HoleScore]
        let courseHoles: [Hole]

        private static func clubColor(for club: ClubType) -> UIColor {
            switch club {
            case .driver:                                          return .systemRed
            case .wood3, .wood5:                                   return .systemOrange
            case .iron4, .iron5, .iron6, .iron7, .iron8, .iron9:  return .systemBlue
            case .pitchingWedge, .gapWedge, .sandWedge, .lobWedge: return .systemPurple
            case .putter:                                         return .systemGreen
            case .unknown:                                        return .systemGray
            }
        }

        init(holes: [HoleScore], courseHoles: [Hole]) {
            self.holes = holes
            self.courseHoles = courseHoles
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            addShotOverlays(to: mapView)
        }

        private func addShotOverlays(to mapView: MLNMapView) {
            var allCoords: [CLLocationCoordinate2D] = []

            for hole in holes {
                guard !hole.shots.isEmpty else { continue }
                let courseHole = courseHoles.first { $0.number == hole.number }
                let sortedShots = hole.shots.sorted(by: { $0.sequence < $1.sequence })

                // Build coordinate list: tee (from course) → shots → green (from course)
                var coords: [CLLocationCoordinate2D] = []
                if let tee = courseHole?.tee {
                    coords.append(CLLocationCoordinate2D(latitude: tee.lat, longitude: tee.lon))
                }
                for shot in sortedShots {
                    coords.append(CLLocationCoordinate2D(latitude: shot.location.lat, longitude: shot.location.lon))
                }
                if let green = courseHole?.greenCenter {
                    coords.append(CLLocationCoordinate2D(latitude: green.lat, longitude: green.lon))
                }

                // Line segments colored by the shot's club
                var prevCoord = coords.first
                for shot in sortedShots {
                    let shotCoord = CLLocationCoordinate2D(latitude: shot.location.lat, longitude: shot.location.lon)
                    if let from = prevCoord {
                        var seg = [from, shotCoord]
                        let line = MLNPolyline(coordinates: &seg, count: 2)
                        line.title = "club-\(shot.club.rawValue)"
                        mapView.addAnnotation(line)
                    }
                    prevCoord = shotCoord
                }
                // Last shot → green
                if let last = prevCoord, let green = courseHole?.greenCenter {
                    let greenCoord = CLLocationCoordinate2D(latitude: green.lat, longitude: green.lon)
                    var seg = [last, greenCoord]
                    let line = MLNPolyline(coordinates: &seg, count: 2)
                    line.title = "club-putter"
                    mapView.addAnnotation(line)
                }

                // Shot pins
                for shot in sortedShots {
                    let point = MLNPointAnnotation()
                    point.coordinate = CLLocationCoordinate2D(latitude: shot.location.lat, longitude: shot.location.lon)
                    point.title = "\(shot.sequence)"
                    point.subtitle = shot.club.rawValue
                    mapView.addAnnotation(point)
                }

                allCoords.append(contentsOf: coords)
            }

            // Fit bounds
            guard allCoords.count >= 2 else {
                if let c = allCoords.first {
                    mapView.setCenter(c, zoomLevel: 17, animated: false)
                }
                return
            }
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(
                    latitude: allCoords.map(\.latitude).min()!,
                    longitude: allCoords.map(\.longitude).min()!
                ),
                ne: CLLocationCoordinate2D(
                    latitude: allCoords.map(\.latitude).max()!,
                    longitude: allCoords.map(\.longitude).max()!
                )
            )
            mapView.setVisibleCoordinateBounds(bounds, edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40), animated: false)
        }

        func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            if let title = annotation.title, title.starts(with: "club-") {
                let raw = String(title.dropFirst(5))
                let club = ClubType(rawValue: raw) ?? .unknown
                return Self.clubColor(for: club)
            }
            return .systemGray
        }

        func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat {
            3
        }

        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            guard let point = annotation as? MLNPointAnnotation,
                  let seq = point.title, let num = Int(seq),
                  let clubRaw = point.subtitle
            else { return nil }

            let club = ClubType(rawValue: clubRaw) ?? .unknown
            let color = Self.clubColor(for: club)
            let id = "shot-\(clubRaw)-\(num)"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) ?? MLNAnnotationView(reuseIdentifier: id)

            let size: CGFloat = 24
            let label = UILabel(frame: CGRect(x: 0, y: 0, width: size, height: size))
            label.text = "\(num)"
            label.font = .systemFont(ofSize: 11, weight: .bold)
            label.textColor = .white
            label.textAlignment = .center
            label.backgroundColor = color
            label.layer.cornerRadius = size / 2
            label.clipsToBounds = true

            view.subviews.forEach { $0.removeFromSuperview() }
            view.addSubview(label)
            view.frame = CGRect(x: 0, y: 0, width: size, height: size)
            return view
        }
    }
}
