//
//  UserLocation.swift
//  PopularTimeWidget
//
//  Created by xbox on 10/30/26.
//

import Combine
import CoreLocation
import MapKit
import SwiftUI

@MainActor
final class MapLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
  @Published private(set) var coordinate: CLLocationCoordinate2D?
  @Published private(set) var status = "Finding your location…"
  @Published private(set) var needsSettings = false
  private let manager = CLLocationManager()

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
  }

  func start() {
    switch manager.authorizationStatus {
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .authorizedAlways, .authorizedWhenInUse:
      needsSettings = false
      status = "Finding your location…"
      manager.requestLocation()
    case .denied, .restricted:
      needsSettings = true
      status = "Location access is off"
    @unknown default:
      status = "Location unavailable"
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard manager.authorizationStatus != .notDetermined else { return }
    start()
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last, location.horizontalAccuracy >= 0,
      abs(location.timestamp.timeIntervalSinceNow) < 300
    else {
      status = "Current location unavailable"
      return
    }
    coordinate = location.coordinate
    status = "Location available"
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    status = "Current location unavailable"
  }

  static var savedRegion: MKCoordinateRegion? {
    let values = UserDefaults.standard.array(forKey: "maps.lastRegion") as? [Double]
    if let values, values.count == 4,
      values.allSatisfy({ $0.isFinite }),
      (-90...90).contains(values[0]), (-180...180).contains(values[1]),
      values[2] > 0, values[2] <= 180, values[3] > 0, values[3] <= 360
    {
      return MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: values[0], longitude: values[1]),
        span: MKCoordinateSpan(latitudeDelta: values[2], longitudeDelta: values[3]))
    }
    return nil
  }

  static func region(around coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
    MKCoordinateRegion(center: coordinate, latitudinalMeters: 5_000, longitudinalMeters: 5_000)
  }

  static func save(_ region: MKCoordinateRegion) {
    UserDefaults.standard.set(
      [
        region.center.latitude, region.center.longitude,
        region.span.latitudeDelta, region.span.longitudeDelta,
      ], forKey: "maps.lastRegion")
  }
}
