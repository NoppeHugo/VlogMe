import SwiftUI
import AVFoundation

struct CameraPreviewLayerView: UIViewRepresentable {

    let session: AVCaptureSession
    var onTapFocus: ((CGPoint) -> Void)?
    var onPinchZoom: ((CGFloat) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinch)

        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.videoPreviewLayer.session = session
        context.coordinator.parent = self
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject {
        var parent: CameraPreviewLayerView
        private var zoomAtGestureStart: CGFloat = 1.0
        private var currentZoom: CGFloat = 1.0

        init(_ parent: CameraPreviewLayerView) { self.parent = parent }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? PreviewUIView else { return }
            let point = gesture.location(in: view)
            let devicePoint = view.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: point)
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
