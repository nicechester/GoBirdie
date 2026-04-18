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
            case .hybrid3, .hybrid4, .hybrid5:                     return .systemTeal
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
                var prevCoord: CLLocationCoordinate2D? = nil
                for (i, shot) in sortedShots.enumerated() {
                    let shotCoord = CLLocationCoordinate2D(latitude: shot.location.lat, longitude: shot.location.lon)
                    if let from = prevCoord {
                        var seg = [from, shotCoord]
                        let line = MLNPolyline(coordinates: &seg, count: 2)
                        let dist = sortedShots[i - 1].location.distanceMeters(to: shot.location)
                        let yards = Int((dist * 1.09361).rounded())
                        line.title = "club-\(shot.club.rawValue)"
                        mapView.addAnnotation(line)
                        // Distance label at midpoint
                        let mid = MLNPointAnnotation()
                        mid.coordinate = CLLocationCoordinate2D(
                            latitude: (from.latitude + shotCoord.latitude) / 2,
                            longitude: (from.longitude + shotCoord.longitude) / 2
                        )
                        mid.title = "\(yards)y"
                        mid.subtitle = "dist-label"
                        mapView.addAnnotation(mid)
                    }
                    prevCoord = shotCoord
                }
                // Last shot → green
                if let last = prevCoord, let lastShot = sortedShots.last, let green = courseHole?.greenCenter {
                    let greenCoord = CLLocationCoordinate2D(latitude: green.lat, longitude: green.lon)
                    var seg = [last, greenCoord]
                    let line = MLNPolyline(coordinates: &seg, count: 2)
                    let dist = lastShot.location.distanceMeters(to: green)
                    let yards = Int((dist * 1.09361).rounded())
                    line.title = "club-\(lastShot.club.rawValue)"
                    mapView.addAnnotation(line)
                    // Distance label at midpoint
                    let mid = MLNPointAnnotation()
                    mid.coordinate = CLLocationCoordinate2D(
                        latitude: (last.latitude + greenCoord.latitude) / 2,
                        longitude: (last.longitude + greenCoord.longitude) / 2
                    )
                    mid.title = "\(yards)y"
                    mid.subtitle = "dist-label"
                    mapView.addAnnotation(mid)
                }

                // Shot pins — show club abbreviation
                for shot in sortedShots {
                    let point = MLNPointAnnotation()
                    point.coordinate = CLLocationCoordinate2D(latitude: shot.location.lat, longitude: shot.location.lon)
                    point.title = shot.club.shortName
                    point.subtitle = shot.club.rawValue
                    mapView.addAnnotation(point)
                }

                // Putt count at green
                if hole.putts > 0, let green = courseHole?.greenCenter {
                    let puttPin = MLNPointAnnotation()
                    puttPin.coordinate = CLLocationCoordinate2D(latitude: green.lat, longitude: green.lon)
                    puttPin.title = "\(hole.putts) Putts"
                    puttPin.subtitle = "putt-label"
                    mapView.addAnnotation(puttPin)
                }

                allCoords.append(contentsOf: coords)
            }

            // Fit bounds with tee-to-pin rotation
            guard allCoords.count >= 2 else {
                if let c = allCoords.first {
                    mapView.setCenter(c, zoomLevel: 17, animated: false)
                }
                return
            }

            // Compute tee-to-pin bearing and distance for camera
            let heading: CLLocationDirection
            let teeGreenDist: Double // meters
            if let firstHole = holes.first,
               let ch = courseHoles.first(where: { $0.number == firstHole.number }),
               let tee = ch.tee, let green = ch.greenCenter {
                let dLon = (green.lon - tee.lon) * .pi / 180
                let lat1 = tee.lat * .pi / 180
                let lat2 = green.lat * .pi / 180
                let y = sin(dLon) * cos(lat2)
                let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
                heading = (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
                teeGreenDist = tee.distanceMeters(to: green)
            } else {
                heading = 0
                // Estimate from coordinate span
                let latSpan = allCoords.map(\.latitude).max()! - allCoords.map(\.latitude).min()!
                let lonSpan = allCoords.map(\.longitude).max()! - allCoords.map(\.longitude).min()!
                teeGreenDist = max(latSpan, lonSpan) * 111_000
            }

            let center = CLLocationCoordinate2D(
                latitude: (allCoords.map(\.latitude).min()! + allCoords.map(\.latitude).max()!) / 2,
                longitude: (allCoords.map(\.longitude).min()! + allCoords.map(\.longitude).max()!) / 2
            )
            let altitude = max(teeGreenDist * 3.5, 200)
            let camera = MLNMapCamera(
                lookingAtCenter: center, altitude: altitude, pitch: 0, heading: heading
            )
            mapView.setCamera(camera, animated: false)
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
            guard let point = annotation as? MLNPointAnnotation else { return nil }

            // Putt count at green
            if point.subtitle == "putt-label" {
                let id = "putt-\(point.title ?? "")"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) ?? MLNAnnotationView(reuseIdentifier: id)
                let label = UILabel()
                label.text = point.title
                label.font = .systemFont(ofSize: 11, weight: .bold)
                label.textColor = .white
                label.backgroundColor = UIColor.systemGreen
                label.textAlignment = .center
                label.sizeToFit()
                let w = max(label.frame.width + 10, 28)
                let h: CGFloat = 28
                label.frame = CGRect(x: 0, y: 0, width: w, height: h)
                label.layer.cornerRadius = h / 2
                label.clipsToBounds = true
                view.subviews.forEach { $0.removeFromSuperview() }
                view.addSubview(label)
                view.frame = label.frame
                return view
            }

            // Distance label at line midpoint
            if point.subtitle == "dist-label" {
                let id = "dist-\(point.title ?? "")"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) ?? MLNAnnotationView(reuseIdentifier: id)
                let label = UILabel()
                label.text = point.title
                label.font = .systemFont(ofSize: 10, weight: .semibold)
                label.textColor = .white
                label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
                label.textAlignment = .center
                label.layer.cornerRadius = 4
                label.clipsToBounds = true
                label.sizeToFit()
                label.frame.size.width += 8
                label.frame.size.height += 4
                view.subviews.forEach { $0.removeFromSuperview() }
                view.addSubview(label)
                view.frame = label.frame
                return view
            }

            // Shot pin with club abbreviation
            guard let clubRaw = point.subtitle else { return nil }
            let club = ClubType(rawValue: clubRaw) ?? .unknown
            let color = Self.clubColor(for: club)
            let abbr = point.title ?? "?"
            let id = "shot-\(clubRaw)-\(abbr)"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) ?? MLNAnnotationView(reuseIdentifier: id)

            let label = UILabel()
            label.text = abbr
            label.font = .systemFont(ofSize: 10, weight: .bold)
            label.textColor = .white
            label.textAlignment = .center
            label.backgroundColor = color
            label.sizeToFit()
            let size = max(label.frame.width + 8, 24)
            label.frame = CGRect(x: 0, y: 0, width: size, height: 24)
            label.layer.cornerRadius = 12
            label.clipsToBounds = true

            view.subviews.forEach { $0.removeFromSuperview() }
            view.addSubview(label)
            view.frame = CGRect(x: 0, y: 0, width: size, height: 24)
            return view
        }
    }
}
