//
//  EditableShotMapView.swift
//  GoBirdie

import SwiftUI
import MapLibre
import GoBirdieCore

/// Interactive shot map that supports selecting, moving, and adding shots.
struct EditableShotMapView: UIViewRepresentable {
    let hole: HoleScore
    let courseHoles: [Hole]
    @Binding var selectedShotId: UUID?
    let onMoveShotTo: (UUID, GpsPoint) -> Void
    let onAddShot: (GpsPoint) -> Void
    let onChangeClub: (UUID, ClubType) -> Void

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
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("editable-shotmap-style.json")
            try? data.write(to: url)
            mapView.styleURL = url
        }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        mapView.addGestureRecognizer(pan)

        context.coordinator.mapView = mapView
        return mapView
    }

    func updateUIView(_ uiView: MLNMapView, context: Context) {
        context.coordinator.selectedShotId = selectedShotId
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            hole: hole,
            courseHoles: courseHoles,
            selectedShotId: $selectedShotId,
            onMoveShotTo: onMoveShotTo,
            onAddShot: onAddShot,
            onChangeClub: onChangeClub
        )
    }

    class Coordinator: NSObject, MLNMapViewDelegate, UIGestureRecognizerDelegate {
        var mapView: MLNMapView?
        let hole: HoleScore
        let courseHoles: [Hole]
        var selectedShotId: UUID?
        let selectedShotIdBinding: Binding<UUID?>
        let onMoveShotTo: (UUID, GpsPoint) -> Void
        let onAddShot: (GpsPoint) -> Void
        let onChangeClub: (UUID, ClubType) -> Void
        private var shotAnnotations: [UUID: MLNPointAnnotation] = [:]
        private var draggingShotId: UUID?

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

        init(hole: HoleScore, courseHoles: [Hole], selectedShotId: Binding<UUID?>,
             onMoveShotTo: @escaping (UUID, GpsPoint) -> Void,
             onAddShot: @escaping (GpsPoint) -> Void,
             onChangeClub: @escaping (UUID, ClubType) -> Void) {
            self.hole = hole
            self.courseHoles = courseHoles
            self.selectedShotIdBinding = selectedShotId
            self.selectedShotId = selectedShotId.wrappedValue
            self.onMoveShotTo = onMoveShotTo
            self.onAddShot = onAddShot
            self.onChangeClub = onChangeClub
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            addOverlays(to: mapView)
        }

        private func addOverlays(to mapView: MLNMapView) {
            let courseHole = courseHoles.first { $0.number == hole.number }
            let sortedShots = hole.shots.sorted { $0.sequence < $1.sequence }
            var allCoords: [CLLocationCoordinate2D] = []

            var prevCoord: CLLocationCoordinate2D? = nil
            if let tee = courseHole?.tee {
                prevCoord = CLLocationCoordinate2D(latitude: tee.lat, longitude: tee.lon)
                allCoords.append(prevCoord!)
            }
            for shot in sortedShots {
                let coord = CLLocationCoordinate2D(latitude: shot.location.lat, longitude: shot.location.lon)
                if let from = prevCoord {
                    var seg = [from, coord]
                    let line = MLNPolyline(coordinates: &seg, count: 2)
                    line.title = "club-\(shot.club.rawValue)"
                    mapView.addAnnotation(line)
                    let dist = GpsPoint(lat: from.latitude, lon: from.longitude).distanceMeters(to: shot.location)
                    let yards = Int((dist * 1.09361).rounded())
                    let mid = MLNPointAnnotation()
                    mid.coordinate = CLLocationCoordinate2D(
                        latitude: (from.latitude + coord.latitude) / 2,
                        longitude: (from.longitude + coord.longitude) / 2
                    )
                    mid.title = "\(yards)y"
                    mid.subtitle = "dist-label"
                    mapView.addAnnotation(mid)
                }
                prevCoord = coord
                allCoords.append(coord)
            }
            if let last = prevCoord, let lastShot = sortedShots.last, let green = courseHole?.greenCenter {
                let greenCoord = CLLocationCoordinate2D(latitude: green.lat, longitude: green.lon)
                var seg = [last, greenCoord]
                let line = MLNPolyline(coordinates: &seg, count: 2)
                line.title = "club-\(lastShot.club.rawValue)"
                mapView.addAnnotation(line)
                let dist = lastShot.location.distanceMeters(to: green)
                let yards = Int((dist * 1.09361).rounded())
                let mid = MLNPointAnnotation()
                mid.coordinate = CLLocationCoordinate2D(
                    latitude: (last.latitude + greenCoord.latitude) / 2,
                    longitude: (last.longitude + greenCoord.longitude) / 2
                )
                mid.title = "\(yards)y"
                mid.subtitle = "dist-label"
                mapView.addAnnotation(mid)
                allCoords.append(greenCoord)
            }

            for shot in sortedShots {
                let point = MLNPointAnnotation()
                point.coordinate = CLLocationCoordinate2D(latitude: shot.location.lat, longitude: shot.location.lon)
                point.title = shot.club.shortName
                point.subtitle = "shot-\(shot.id.uuidString)"
                mapView.addAnnotation(point)
                shotAnnotations[shot.id] = point
            }

            if hole.putts > 0, let green = courseHole?.greenCenter {
                let puttPin = MLNPointAnnotation()
                puttPin.coordinate = CLLocationCoordinate2D(latitude: green.lat, longitude: green.lon)
                puttPin.title = "\(hole.putts) Putts"
                puttPin.subtitle = "putt-label"
                mapView.addAnnotation(puttPin)
            }

            guard allCoords.count >= 2 else {
                if let c = allCoords.first { mapView.setCenter(c, zoomLevel: 17, animated: false) }
                return
            }
            let heading: CLLocationDirection
            let teeGreenDist: Double
            if let ch = courseHole, let tee = ch.tee, let green = ch.greenCenter {
                let dLon = (green.lon - tee.lon) * .pi / 180
                let lat1 = tee.lat * .pi / 180
                let lat2 = green.lat * .pi / 180
                let y = sin(dLon) * cos(lat2)
                let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
                heading = (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
                teeGreenDist = tee.distanceMeters(to: green)
            } else {
                heading = 0
                let latSpan = allCoords.map(\.latitude).max()! - allCoords.map(\.latitude).min()!
                let lonSpan = allCoords.map(\.longitude).max()! - allCoords.map(\.longitude).min()!
                teeGreenDist = max(latSpan, lonSpan) * 111_000
            }
            let center = CLLocationCoordinate2D(
                latitude: (allCoords.map(\.latitude).min()! + allCoords.map(\.latitude).max()!) / 2,
                longitude: (allCoords.map(\.longitude).min()! + allCoords.map(\.longitude).max()!) / 2
            )
            let altitude = max(teeGreenDist * 3.5, 200)
            let camera = MLNMapCamera(lookingAtCenter: center, altitude: altitude, pitch: 0, heading: heading)
            mapView.setCamera(camera, animated: false)
        }

        // MARK: - Gesture recognizer delegate

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // When dragging a shot, don't let map pan simultaneously
            if draggingShotId != nil { return false }
            return true
        }

        // MARK: - Hit test for shot annotations

        private func shotIdAtPoint(_ point: CGPoint, in mapView: MLNMapView) -> UUID? {
            let rect = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
            guard let nearby = mapView.visibleAnnotations(in: rect) else { return nil }
            for ann in nearby {
                guard let pt = ann as? MLNPointAnnotation,
                      let sub = pt.subtitle, sub.hasPrefix("shot-") else { continue }
                let idStr = String(sub.dropFirst(5))
                if let uuid = UUID(uuidString: idStr) { return uuid }
            }
            return nil
        }

        // MARK: - Tap: select or add

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView else { return }
            let point = gesture.location(in: mapView)

            if let shotId = shotIdAtPoint(point, in: mapView) {
                if selectedShotId == shotId {
                    // Already selected — open club picker
                    let currentClub = hole.shots.first { $0.id == shotId }?.club ?? .unknown
                    DispatchQueue.main.async {
                        self.onChangeClub(shotId, currentClub)
                    }
                } else {
                    // Not selected — select it
                    DispatchQueue.main.async {
                        self.selectedShotIdBinding.wrappedValue = shotId
                        self.selectedShotId = shotId
                    }
                    updateSelectionVisuals(mapView: mapView)
                }
                return
            }

            // Tapped empty area — add new shot
            let coord = mapView.convert(point, toCoordinateFrom: mapView)
            DispatchQueue.main.async {
                self.onAddShot(GpsPoint(lat: coord.latitude, lon: coord.longitude))
            }
        }

        // MARK: - Pan: drag selected shot

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let mapView else { return }
            let point = gesture.location(in: mapView)

            switch gesture.state {
            case .began:
                // Only start drag if finger is on a shot pin
                if let shotId = shotIdAtPoint(point, in: mapView) {
                    draggingShotId = shotId
                    // Disable map scrolling while dragging
                    mapView.isScrollEnabled = false
                    DispatchQueue.main.async {
                        self.selectedShotIdBinding.wrappedValue = shotId
                        self.selectedShotId = shotId
                    }
                    updateSelectionVisuals(mapView: mapView)
                }
            case .changed:
                guard let dragId = draggingShotId, let ann = shotAnnotations[dragId] else { return }
                let coord = mapView.convert(point, toCoordinateFrom: mapView)
                ann.coordinate = coord
            case .ended, .cancelled:
                if let dragId = draggingShotId, let ann = shotAnnotations[dragId] {
                    let newLoc = GpsPoint(lat: ann.coordinate.latitude, lon: ann.coordinate.longitude)
                    DispatchQueue.main.async {
                        self.onMoveShotTo(dragId, newLoc)
                    }
                }
                draggingShotId = nil
                mapView.isScrollEnabled = true
            default:
                break
            }
        }

        private func updateSelectionVisuals(mapView: MLNMapView) {
            for (id, ann) in shotAnnotations {
                if let view = mapView.view(for: ann) {
                    let isSelected = id == selectedShotId
                    view.layer.borderWidth = isSelected ? 3 : 0
                    view.layer.borderColor = isSelected ? UIColor.white.cgColor : nil
                }
            }
        }

        // MARK: - MLNMapViewDelegate

        func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            if let title = annotation.title, title.starts(with: "club-") {
                let raw = String(title.dropFirst(5))
                return Self.clubColor(for: ClubType(rawValue: raw) ?? .unknown)
            }
            return .systemGray
        }

        func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat { 3 }

        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            guard let point = annotation as? MLNPointAnnotation else { return nil }

            if point.subtitle == "putt-label" {
                let view = MLNAnnotationView(reuseIdentifier: "putt-edit")
                let label = UILabel()
                label.text = point.title
                label.font = .systemFont(ofSize: 11, weight: .bold)
                label.textColor = .white
                label.backgroundColor = .systemGreen
                label.textAlignment = .center
                label.sizeToFit()
                let w = max(label.frame.width + 10, 28)
                label.frame = CGRect(x: 0, y: 0, width: w, height: 28)
                label.layer.cornerRadius = 14
                label.clipsToBounds = true
                view.subviews.forEach { $0.removeFromSuperview() }
                view.addSubview(label)
                view.frame = label.frame
                return view
            }

            if point.subtitle == "dist-label" {
                let view = MLNAnnotationView(reuseIdentifier: "dist-edit")
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

            guard let subtitle = point.subtitle, subtitle.hasPrefix("shot-") else { return nil }
            let idStr = String(subtitle.dropFirst(5))
            let shotId = UUID(uuidString: idStr)
            let shot = hole.shots.first { $0.id == shotId }
            let club = shot?.club ?? .unknown
            let color = Self.clubColor(for: club)
            let isSelected = shotId == selectedShotId

            let view = MLNAnnotationView(reuseIdentifier: "shot-edit-\(idStr)")
            let label = UILabel()
            label.text = point.title
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
            view.layer.borderWidth = isSelected ? 3 : 0
            view.layer.borderColor = isSelected ? UIColor.white.cgColor : nil
            view.layer.cornerRadius = 12
            return view
        }
    }
}
