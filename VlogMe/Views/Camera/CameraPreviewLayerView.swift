import SwiftUI
import AVFoundation

/// Affiche la ou les couches de prévisualisation de `CameraService` :
/// - la caméra principale en plein écran ;
/// - en mode Duo, la caméra opposée incrustée en haut à gauche (comme dans la vidéo écrite) ;
/// - transitions animées lors du flip et de l'activation du mode Duo ;
/// - tap-to-focus et pinch-to-zoom.
struct CameraPreviewLayerView: UIViewRepresentable {

    let camera: CameraService
    let facing: CameraFacing
    let isPiP: Bool
    var onTapFocus: ((CGPoint) -> Void)?
    var onPinchZoom: ((CGFloat) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.install(back: camera.backPreviewLayer, front: camera.frontPreviewLayer)
        view.apply(facing: facing, pip: isPiP, animated: false)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinch)

        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        context.coordinator.parent = self
        uiView.apply(facing: facing, pip: isPiP, animated: true)
    }

    // MARK: - Vue conteneur

    final class PreviewContainerView: UIView {

        private var backLayer: AVCaptureVideoPreviewLayer?
        private var frontLayer: AVCaptureVideoPreviewLayer?
        private var facing: CameraFacing = .back
        private var pip = false

        func install(back: AVCaptureVideoPreviewLayer, front: AVCaptureVideoPreviewLayer?) {
            backLayer = back
            frontLayer = front
            layer.addSublayer(back)
            if let front { layer.addSublayer(front) }
        }

        /// Couche affichée en plein écran — sert de référence aux gestes.
        var fullscreenLayer: AVCaptureVideoPreviewLayer? {
            (facing == .front && frontLayer != nil) ? frontLayer : backLayer
        }

        func apply(facing: CameraFacing, pip: Bool, animated: Bool) {
            let changed = facing != self.facing || (pip && frontLayer != nil) != self.pip
            self.facing = facing
            self.pip = pip && frontLayer != nil
            guard changed || !animated else { return }
            CATransaction.begin()
            if animated {
                CATransaction.setAnimationDuration(0.3)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            } else {
                CATransaction.setDisableActions(true)
            }
            layoutLayers()
            CATransaction.commit()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layoutLayers()
            CATransaction.commit()
        }

        private func layoutLayers() {
            guard let backLayer, bounds.width > 0 else { return }
            let full = bounds

            // Cadre de l'incrustation : 40 % de la largeur, sous la barre de contrôles du haut.
            let pipRect = CGRect(
                x: 14,
                y: safeAreaInsets.top + 58,
                width: full.width * 0.40,
                height: full.height * 0.40
            )

            let mainLayer: AVCaptureVideoPreviewLayer
            let overlayLayer: AVCaptureVideoPreviewLayer?
            if facing == .front, let frontLayer {
                mainLayer = frontLayer
                overlayLayer = backLayer
            } else {
                mainLayer = backLayer
                overlayLayer = frontLayer
            }

            mainLayer.zPosition = 0
            mainLayer.opacity = 1
            mainLayer.frame = full
            mainLayer.cornerRadius = 0
            mainLayer.borderWidth = 0
            mainLayer.masksToBounds = true

            if let overlayLayer {
                overlayLayer.zPosition = 1
                overlayLayer.opacity = pip ? 1 : 0
                overlayLayer.frame = pip ? pipRect : full
                overlayLayer.cornerRadius = pip ? 18 : 0
                overlayLayer.borderWidth = pip ? 1.5 : 0
                overlayLayer.borderColor = UIColor.white.withAlphaComponent(0.75).cgColor
                overlayLayer.masksToBounds = true
            }
        }
    }

    // MARK: - Gestes

    final class Coordinator: NSObject {
        var parent: CameraPreviewLayerView
        private var zoomAtGestureStart: CGFloat = 1.0
        private var currentZoom: CGFloat = 1.0

        init(_ parent: CameraPreviewLayerView) { self.parent = parent }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? PreviewContainerView,
                  let layer = view.fullscreenLayer else { return }
            let point = gesture.location(in: view)
            let devicePoint = layer.captureDevicePointConverted(fromLayerPoint: point)
            parent.onTapFocus?(devicePoint)
            showFocusIndicator(at: point, in: view)
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                zoomAtGestureStart = currentZoom
            case .changed:
                let newZoom = zoomAtGestureStart * gesture.scale
                currentZoom = newZoom
                parent.onPinchZoom?(newZoom)
            default:
                break
            }
        }

        private func showFocusIndicator(at point: CGPoint, in view: UIView) {
            let size: CGFloat = 70
            let indicator = UIView(frame: CGRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size))
            indicator.layer.borderColor = UIColor(red: 1, green: 0.42, blue: 0.29, alpha: 1).cgColor
            indicator.layer.borderWidth = 1.5
            indicator.alpha = 0
            view.addSubview(indicator)
            UIView.animate(withDuration: 0.15, animations: { indicator.alpha = 1 }) { _ in
                UIView.animate(withDuration: 0.5, delay: 0.5, animations: { indicator.alpha = 0 }) { _ in
                    indicator.removeFromSuperview()
                }
            }
        }
    }
}
