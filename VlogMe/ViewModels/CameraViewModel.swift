import Foundation
import AVFoundation
import Combine

@MainActor
final class CameraViewModel: ObservableObject {

    let camera: CameraService
    let store: VlogStore

    @Published private(set) var elapsedInCurrentSegment: Double = 0
    @Published private(set) var zoomFactor: CGFloat = 1.0

    private var cancellables = Set<AnyCancellable>()
    private var timer: AnyCancellable?
    private var segmentStart: Date?

    var isRecording: Bool { camera.isRecording }
    var facing: CameraFacing { camera.facing }
    var isTorchOn: Bool { camera.isTorchOn }
    var aspectRatio: AspectRatio { store.aspectRatio }
    var segments: [VideoSegment] { store.segments }
    var hasSegments: Bool { store.hasSegments }
    var canFinish: Bool { store.hasSegments && !camera.isRecording }
    var controlsLocked: Bool { camera.isRecording }

    var totalDuration: Double { store.totalDuration + elapsedInCurrentSegment }

    init(camera: CameraService, store: VlogStore) {
        self.camera = camera
        self.store = store

        camera.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        store.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        camera.onSegmentFinished = { [weak self] url in
            Task { await self?.handleFinishedSegment(at: url) }
        }
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
        } else {
            let url = store.newSegmentURL()
            camera.startRecording(to: url)
            startTimer()
        }
    }

    func switchCamera() {
        guard !camera.isRecording else { return }
        zoomFactor = 1.0
        camera.switchCamera()
    }

    func toggleAspect() {
        guard !camera.isRecording else { return }
        store.aspectRatio.toggle()
    }

    func deleteLastSegment() { store.removeLast() }
    func redoLastSegment() { store.removeLast() }

    func toggleTorch() { camera.toggleTorch() }

    func handlePinchZoom(_ factor: CGFloat) {
        zoomFactor = factor
        camera.setZoom(factor)
    }

    func handleTapFocus(_ devicePoint: CGPoint) {
        camera.focusAndExpose(at: devicePoint)
    }

    // MARK: - Private

    private func handleFinishedSegment(at url: URL) async {
        let asset = AVURLAsset(url: url)
        let measured = (try? await asset.load(.duration).seconds) ?? elapsedInCurrentSegment
        let duration = measured.isFinite ? measured : elapsedInCurrentSegment
        let segment = VideoSegment(fileName: url.lastPathComponent, durationSeconds: duration, facing: camera.facing)
        store.append(segment)
        elapsedInCurrentSegment = 0
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
