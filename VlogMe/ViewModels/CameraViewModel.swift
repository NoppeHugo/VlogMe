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
    @Published private(set) var countdown: Int? = nil
    @Published var showGrid = false

    /// Retardateur (en secondes) avant le lancement de l'enregistrement.
    /// 0 = désactivé. Réglable et mémorisé entre les sessions.
    @Published var countdownSeconds: Int = UserDefaults.standard.integer(forKey: "countdownSeconds") {
        didSet { UserDefaults.standard.set(countdownSeconds, forKey: "countdownSeconds") }
    }

    /// Valeurs proposées dans le sélecteur de retardateur.
    let countdownOptions = [0, 3, 5, 10]

    var countdownEnabled: Bool { countdownSeconds > 0 }

    /// Enregistre chaque clip filmé dans la pellicule (en plus du montage final).
    /// Désactivé par défaut, réglable et mémorisé entre les sessions.
    @Published private(set) var saveClipsToCameraRoll: Bool =
        UserDefaults.standard.bool(forKey: "saveClipsToCameraRoll")

    /// Démarre l'enregistrement automatiquement à l'ouverture de la caméra.
    /// Désactivé par défaut, réglable et mémorisé entre les sessions.
    @Published private(set) var autoStartRecording: Bool =
        UserDefaults.standard.bool(forKey: "autoStartRecording")

    /// Message transitoire à afficher (ex. accès Photos refusé).
    @Published var clipSaveNotice: String? = nil

    private var didAutoStart = false
    private var wantsToStart = false

    private var cancellables = Set<AnyCancellable>()
    private var timer: AnyCancellable?
    private var maxDurationTimer: AnyCancellable?
    private var segmentStart: Date?
    private var pendingCameraFlip = false
    private var countdownTask: Task<Void, Never>? = nil

    private let impactHeavy  = UIImpactFeedbackGenerator(style: .heavy)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactLight  = UIImpactFeedbackGenerator(style: .light)
    private let notif        = UINotificationFeedbackGenerator()

    var isRecording: Bool      { camera.isRecording }
    var facing: CameraFacing   { camera.facing }
    var isTorchOn: Bool        { camera.isTorchOn }
    var aspectRatio: AspectRatio { store.aspectRatio }
    var segments: [VideoSegment] { store.segments }
    var hasSegments: Bool      { store.hasSegments }
    var canFinish: Bool        { store.hasSegments && !camera.isRecording }
    var controlsLocked: Bool   { camera.isRecording }
    var draftName: String      { store.activeDraft?.name ?? "Vlog" }
    var draftCount: Int        { store.drafts.count }
    var zoomPreset: ZoomPreset { camera.zoomPreset }
    var hasUltraWide: Bool     { camera.hasUltraWide }

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
                Task { @MainActor [weak self] in self?.requestStartRecording() }
            }
            .store(in: &cancellables)

        // Prépare les générateurs pour réduire la latence haptique
        impactHeavy.prepare()
        impactMedium.prepare()
        impactLight.prepare()
        notif.prepare()
    }

    // MARK: - Lifecycle

    func onAppear() {
        camera.configure()
        camera.start()
        // Re-prépare après un retour en premier plan
        impactHeavy.prepare()
        impactMedium.prepare()
        impactLight.prepare()

        // Démarrage à la volée : demande explicite (widget / bouton Action) en priorité,
        // sinon l'option « filmer dès l'ouverture » si c'est la première apparition.
        if LaunchRouter.shared.consumePendingRecord() {
            requestStartRecording()
        } else if autoStartRecording, !didAutoStart, !hasSegments {
            didAutoStart = true
            requestStartRecording()
        }
    }

    /// Lance l'enregistrement dès que la caméra est prête (gère le lancement à froid).
    /// Respecte le retardateur s'il est réglé.
    func requestStartRecording() {
        guard !camera.isRecording, countdown == nil, !wantsToStart else { return }
        wantsToStart = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Attend que la session soit configurée (max ~4 s) puis qu'elle tourne.
            for _ in 0..<80 {
                if self.camera.isConfigured { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard self.wantsToStart, !self.camera.isRecording, self.countdown == nil else {
                self.wantsToStart = false
                return
            }
            self.wantsToStart = false
            self.toggleRecording()
        }
    }

    func onDisappear() {
        if !camera.isRecording { camera.stop() }
    }

    // MARK: - Actions

    func toggleRecording() {
        if camera.isRecording || countdown != nil {
            // Arrêt (annule aussi le compte à rebours en cours)
            countdownTask?.cancel()
            countdownTask = nil
            countdown = nil
            if camera.isRecording {
                stopTimer()
                camera.stopRecording()
                impactMedium.impactOccurred()
                impactMedium.prepare()
            }
        } else if countdownEnabled {
            countdownTask = Task { await runCountdownThenRecord() }
        } else {
            startRecordingNow()
        }
    }

    private func runCountdownThenRecord() async {
        for n in stride(from: countdownSeconds, through: 1, by: -1) {
            guard !Task.isCancelled else { return }
            countdown = n
            impactLight.impactOccurred()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        guard !Task.isCancelled else { countdown = nil; return }
        countdown = nil
        startRecordingNow()
    }

    private func startRecordingNow() {
        let url = store.newSegmentURL()
        camera.startRecording(to: url)
        startTimer()
        impactHeavy.impactOccurred()
        impactHeavy.prepare()
        Analytics.track(.recordingStarted, ["segment_index": segments.count])
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
            impactLight.prepare()
        }
    }

    func setZoomPreset(_ preset: ZoomPreset) {
        guard !camera.isRecording else { return }
        camera.setZoomPreset(preset)
        zoomFactor = 1.0
        impactLight.impactOccurred()
        impactLight.prepare()
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
        impactHeavy.impactOccurred()
        impactHeavy.prepare()
    }

    func toggleTorch() { camera.toggleTorch() }

    /// Active/désactive la sauvegarde des clips bruts dans la pellicule.
    /// À l'activation, demande l'autorisation Photos ; si refusée, on revient à off.
    func setSaveClipsToCameraRoll(_ on: Bool) {
        guard on else {
            saveClipsToCameraRoll = false
            UserDefaults.standard.set(false, forKey: "saveClipsToCameraRoll")
            return
        }
        Task { @MainActor in
            if await PhotoSaver.ensureAuthorized() {
                saveClipsToCameraRoll = true
                UserDefaults.standard.set(true, forKey: "saveClipsToCameraRoll")
                impactLight.impactOccurred()
            } else {
                saveClipsToCameraRoll = false
                UserDefaults.standard.set(false, forKey: "saveClipsToCameraRoll")
                clipSaveNotice = "Autorise l'accès à Photos dans les Réglages pour enregistrer les clips dans la pellicule."
            }
        }
    }

    /// Active/désactive le démarrage automatique de l'enregistrement à l'ouverture.
    func setAutoStartRecording(_ on: Bool) {
        autoStartRecording = on
        UserDefaults.standard.set(on, forKey: "autoStartRecording")
        impactLight.impactOccurred()
    }

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
        let segment  = VideoSegment(fileName: url.lastPathComponent, durationSeconds: duration, facing: camera.facing)
        store.append(segment)
        elapsedInCurrentSegment = 0

        // Enregistre le clip brut dans la pellicule si l'option est active.
        if saveClipsToCameraRoll {
            Task { [weak self] in
                do {
                    try await PhotoSaver.save(url)
                } catch {
                    await MainActor.run {
                        self?.clipSaveNotice = "Ce clip n'a pas pu être enregistré dans la pellicule."
                    }
                }
            }
        }

        if pendingCameraFlip {
            pendingCameraFlip = false
            zoomFactor = 1.0
            camera.switchCamera()
            impactLight.impactOccurred()
            impactLight.prepare()
            try? await Task.sleep(nanoseconds: 200_000_000)
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
        // Auto-stop si durée max définie
        if let maxDur = store.activeDraft?.maxSegmentDuration {
            maxDurationTimer = Timer.publish(every: maxDur, on: .main, in: .common)
                .autoconnect()
                .prefix(1)
                .sink { [weak self] _ in
                    guard let self, self.camera.isRecording else { return }
                    self.stopTimer()
                    self.camera.stopRecording()
                    self.impactMedium.impactOccurred()
                    self.impactMedium.prepare()
                }
        }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
        maxDurationTimer?.cancel()
        maxDurationTimer = nil
        segmentStart = nil
    }
}

// MARK: - Notification

extension Notification.Name {
    static let vlogmeStartRecording = Notification.Name("pro.vlogme.startRecording")
}
