import Foundation
import AVFoundation
import Combine
import UIKit

@MainActor
final class CameraViewModel: ObservableObject {

    let camera: CameraService
    let store: VlogStore

    @Published private(set) var elapsedInCurrentSegment: Double = 0
    @Published private(set) var zoomFactor: CGFloat = 1.0
    @Published private(set) var isSwitchingCamera = false

    private var cancellables = Set<AnyCancellable>()
    private var timer: AnyCancellable?
    private var segmentStart: Date?
    private var pendingCameraFlip = false

    private let impactHeavy  = UIImpactFeedbackGenerator(style: .heavy)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactLight  = UIImpactFeedbackGenerator(style: .light)
    private let notif        = UINotificationFeedbackGenerator()

    var isRecording: Bool    { camera.isRecording }
    var facing: CameraFacing { camera.facing }
    var isTorchOn: Bool      { camera.isTorchOn }
    var aspectRatio: AspectRatio { store.aspectRatio }
    var segments: [VideoSegment] { store.segments }
    var hasSegments: Bool    { store.hasSegments }
    var canFinish: Bool      { store.hasSegments && !camera.isRecording }
    var controlsLocked: Bool { camera.isRecording }
    var draftName: String    { store.activeDraft?.name ?? "Vlog" }
    var draftCount: Int      { store.drafts.count }

    var totalDuration: Double { store.totalDuration + elapsedInCurrentSegment }

    // MARK: - Durée cible

    var targetDuration: Double? { store.targetDuration }

    var targetProgress: Double? {
        guard let t = store.targetDuration, t > 0 else { return nil }
        return min(1.0, totalDuration / t)
    }

    var remainingDuration: Double? {
        guard let t = store.targetDuration else { return nil }
        return max(0, t - totalDuration)
    }

    // MARK: - Init

    init(camera: CameraService, store: VlogStore) {
        self.camera = camera
        self.store  = store

        camera.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        store.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        camera.onSegmentFinished = { [weak self] url in
            Task { await self?.handleFinishedSegment(at: url) }
        }

        NotificationCenter.default.publisher(for: .vlogmeStartRecording)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, !self.camera.isRecording else { return }
                    self.toggleRecording()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    func onAppear() {
        camera.configure()
        camera.start()
    }

    func onDisappear() {
        if !camera.isRecording { camera.stop() }
    }

    // MARK: - Actions

    func toggleRecording() {
        if camera.isRecording {
            stopTimer()
            camera.stopRecording()
            impactMedium.impactOccurred()
        } else {
            let url = store.newSegmentURL()
            camera.startRecording(to: url)
            startTimer()
            impactHeavy.impactOccurred()
        }
    }

    func switchCamera() {
        if camera.isRecording {
            pendingCameraFlip = true
            isSwitchingCamera = true
            stopTimer()
            camera.stopRecording()
        } else {
            zoomFactor = 1.0
            camera.switchCamera()
            impactLight.impactOccurred()
        }
    }

    func toggleAspect() {
        guard !camera.isRecording else { return }
        store.aspectRatio.toggle()
    }

    func deleteLastSegment() { store.removeLast() }

    func redoLastSegment() {
        store.removeLast()
        let url = store.newSegmentURL()
        camera.startRecording(to: url)
        startTimer()
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    func toggleTorch() { camera.toggleTorch() }

    func handlePinchZoom(_ factor: CGFloat) {
        zoomFactor = factor
        camera.setZoom(factor)
    }

    func handleTapFocus(_ devicePoint: CGPoint) {
        camera.focusAndExpose(at: devicePoint)
    }

    // MARK: - Privé

    private func handleFinishedSegment(at url: URL) async {
        let asset = AVURLAsset(url: url)
        let measured = (try? await asset.load(.duration).seconds) ?? elapsedInCurrentSegment
        let duration = measured.isFinite ? measured : elapsedInCurrentSegment
        let segment = VideoSegment(fileName: url.lastPathComponent, durationSeconds: duration, facing: camera.facing)
        store.append(segment)
        elapsedInCurrentSegment = 0

        if pendingCameraFlip {
            pendingCameraFlip = false
            zoomFactor = 1.0
            camera.switchCamera()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // Laisser le temps à la session de basculer avant de relancer l'enregistrement
            try? await Task.sleep(nanoseconds: 350_000_000)
            let newURL = store.newSegmentURL()
            camera.startRecording(to: newURL)
            startTimer()
            isSwitchingCamera = false
        }
    }

    private func startTimer() {
        segmentStart = Date()
        elapsedInCurrentSegment = 0
        timer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let start = self.segmentStart else { return }
                self.elapsedInCurrentSegment = Date().timeIntervalSince(start)
            }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
        segmentStart = nil
    }
}

// MARK: - Notification

extension Notification.Name {
    static let vlogmeStartRecording = Notification.Name("pro.vlogme.startRecording")
}
