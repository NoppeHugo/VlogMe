import CoreLocation

/// Fournit la ville courante, mémorisée sur chaque clip au moment du tournage,
/// pour les cartons « changement de ville » à l'export.
///
/// Précision volontairement grossière (échelle ville) : impact batterie minime.
/// Le géocodage inverse est throttlé (nouvelle requête seulement après ~1 km de
/// déplacement) pour respecter le quota de `CLGeocoder`.
/// Sans autorisation de localisation, `currentCity` reste `nil` et la feature
/// est simplement inactive — rien ne casse.
final class LocationService: NSObject, CLLocationManagerDelegate {

    static let shared = LocationService()

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var lastGeocodedLocation: CLLocation?
    private var isGeocoding = false

    /// Ville actuelle (ex. « Bruxelles »), `nil` tant qu'aucune position géocodée.
    private(set) var currentCity: String?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 500
    }

    /// À appeler à l'ouverture de la caméra : demande l'autorisation au besoin,
    /// puis suit la position à l'échelle de la ville.
    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // Ne re-géocode que si on a bougé d'au moins ~1 km depuis le dernier géocodage.
        if let last = lastGeocodedLocation,
           location.distance(from: last) < 1_000,
           currentCity != nil {
            return
        }
        guard !isGeocoding else { return }
        isGeocoding = true
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self else { return }
            self.isGeocoding = false
            guard let placemark = placemarks?.first else { return }
            if let city = placemark.locality
                ?? placemark.subAdministrativeArea
                ?? placemark.administrativeArea {
                self.currentCity = city
                self.lastGeocodedLocation = location
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silencieux : sans position, les clips n'ont simplement pas de ville.
    }
}
