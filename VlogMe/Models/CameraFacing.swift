import AVFoundation

/// Caméra avant/arrière. Le switch est autorisé entre les segments uniquement (cf. §4).
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
