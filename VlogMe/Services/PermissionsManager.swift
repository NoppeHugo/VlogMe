import AVFoundation
import Combine

/// Gère les autorisations caméra + micro et leurs états (cf. §4 — états à gérer).
@MainActor
final class PermissionsManager: ObservableObject {

    enum Status {
        case unknown    // pas encore demandé
        case authorized
        case denied
    }

    @Published private(set) var camera: Status = .unknown
    @Published private(set) var microphone: Status = .unknown

    var allGranted: Bool { camera == .authorized && microphone == .authorized }
    var anyDenied: Bool { camera == .denied || microphone == .denied }

    /// Met à jour l'état à partir du système (à appeler au lancement / retour foreground).
    func refresh() {
        camera = map(AVCaptureDevice.authorizationStatus(for: .video))
        microphone = map(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    /// Affiche les pop-ups système d'autorisation.
    func request() async {
        let cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        camera = cameraGranted ? .authorized : .denied
        microphone = micGranted ? .authorized : .denied
    }

    private func map(_ status: AVAuthorizationStatus) -> Status {
        switch status {
        case .authorized:    return .authorized
        case .notDetermined: return .unknown
        default:             return .denied   // .denied, .restricted
        }
    }
}
