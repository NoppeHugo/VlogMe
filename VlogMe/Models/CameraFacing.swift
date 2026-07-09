import AVFoundation

/// Caméra avant/arrière. Le switch est possible à tout moment, y compris en plein
/// enregistrement : le pipeline multicam change de source sans couper le segment.
enum CameraFacing: String, Codable {
    case back
    case front

    var avPosition: AVCaptureDevice.Position {
        switch self {
        case .back:  return .back
        case .front: return .front
        }
    }

    mutating func toggle() {
        self = (self == .back) ? .front : .back
    }
}
