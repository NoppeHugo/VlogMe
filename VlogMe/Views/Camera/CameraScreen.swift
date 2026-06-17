import SwiftUI

struct CameraScreen: View {

    @EnvironmentObject private var entitlements: Entitlements
    @StateObject private var vm: CameraViewModel
    @Binding private var showPreview: Bool
    @State private var showLibrary      = false
    @State private var showReorder      = false
    @State private var showPaywall      = false
    @State private var segmentToTrim: VideoSegment? = nil

    init(camera: CameraService, store: VlogStore, showPreview: Binding<Bool>) {
        _vm = StateObject(wrappedValue: CameraViewModel(camera: camera, store: store))
        _showPreview = showPreview
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            CameraPreviewLayerView(
                session: vm.camera.session,
                onTapFocus: { vm.handleTapFocus($0) },
                onPinchZoom: { vm.handlePinchZoom($0) }
            )
            .ignoresSafeArea()

            // Grille de composition
            if vm.showGrid {
                GridOverlayView()
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                topBar
                if let progress = vm.targetProgress {
                    targetBar(progress: progress)
                }
                Spacer()
                zoomIndicator
                zoomPresetButtons
                if vm.hasSegments {
                    SegmentStackView(
                        segments: vm.segments,
                        urlFor: { vm.store.url(for: $0) },
                        onRedoLast: vm.redoLastSegment,
                        onDeleteLast: vm.deleteLastSegment,
                        onTrim: { segmentToTrim = $0 },
                        onReorder: { showReorder = true }
                    )
                    .padding(.bottom, 8)
                }
                bottomControls
            }
            .padding(.vertical, 12)

            // Overlay compte à rebours
            if let n = vm.countdown {
                CountdownOverlayView(value: n)
                    .transition(.opacity)
            }
        }
        .statusBarHidden(true)
        .animation(.easeInOut(duration: 0.2), value: vm.showGrid)
        .animation(.easeInOut(duration: 0.15), value: vm.countdown)
        .onAppear { vm.onAppear() }
        .onDisappear { vm.onDisappear() }
        .sheet(isPresented: $showLibrary) {
            VlogLibraryScreen()
                .environmentObject(vm.store)
        }
        .sheet(isPresented: $showReorder) {
            SegmentReorderSheet()
                .environmentObject(vm.store)
        }
        .sheet(item: $segmentToTrim) { seg in
            TrimSheet(segment: seg, url: vm.store.url(for: seg)) { start, end in
                vm.store.setSegmentTrim(seg.id, start: start, end: end)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(entitlements)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            // Bibliothèque
            Button { showLibrary = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "rectangle.stack")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.45), in: Capsule())
                    if vm.draftCount > 1 {
                        Text("\(vm.draftCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(3)
                            .background(Color.accentOrange, in: Circle())
                            .offset(x: 4, y: -4)
                    }
                }
            }
            .disabled(vm.controlsLocked)
            .opacity(vm.controlsLocked ? 0.35 : 1)

            // Durée
            VStack(alignment: .leading, spacing: 0) {
                DurationLabel(seconds: vm.totalDuration, isRecording: vm.isRecording)
                if let remaining = vm.remainingDuration {
                    Text("→ \(formatDuration(remaining)) restantes")
                        .font(.system(size: 10, design: .monospaced).weight(.medium))
                        .foregroundStyle(remaining < 10 ? Color.red.opacity(0.9) : .white.opacity(0.6))
                        .padding(.leading, 12)
                } else if !entitlements.isPro, let limit = entitlements.maxVlogDuration {
                    let remaining = max(0, limit - vm.totalDuration)
                    Button { showPaywall = true } label: {
                        Text(remaining <= 0 ? "Limite atteinte · Pro" : "→ \(formatDuration(remaining)) gratuites")
                            .font(.system(size: 10, design: .monospaced).weight(.medium))
                            .foregroundStyle(remaining < 20 ? Color.accentOrange : .white.opacity(0.5))
                            .padding(.leading, 12)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Grille
            Button { vm.showGrid.toggle() } label: {
                Image(systemName: vm.showGrid ? "grid" : "grid")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(vm.showGrid ? Color.accentOrange : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
            }

            // Compte à rebours
            Button { vm.countdownEnabled.toggle() } label: {
                Text("3s")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(vm.countdownEnabled ? Color.accentOrange : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
            }
            .disabled(vm.controlsLocked)
            .opacity(vm.controlsLocked ? 0.35 : 1)

            // Torche
            if vm.facing == .back {
                Button { vm.toggleTorch() } label: {
                    Image(systemName: vm.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(vm.isTorchOn ? Color.accentOrange : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.45), in: Capsule())
                }
            }

            // Format
            Button { vm.toggleAspect() } label: {
                Text(vm.aspectRatio.label)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
            }
            .opacity(vm.controlsLocked ? 0.35 : 1)
            .disabled(vm.controlsLocked)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Progress bar durée cible

    private func targetBar(progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12)).frame(height: 3)
                Capsule()
                    .fill(progress >= 1 ? Color.green : Color.accentOrange)
                    .frame(width: geo.size.width * progress, height: 3)
                    .animation(.linear(duration: 0.1), value: progress)
            }
        }
        .frame(height: 3)
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    // MARK: - Zoom indicator

    @ViewBuilder
    private var zoomIndicator: some View {
        if vm.zoomFactor > 1.05 {
            Text(String(format: "%.1f×", vm.zoomFactor))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.black.opacity(0.5), in: Capsule())
                .padding(.bottom, 8)
                .transition(.opacity)
        }
    }

    // MARK: - Zoom preset buttons

    private var zoomPresetButtons: some View {
        HStack(spacing: 6) {
            if vm.hasUltraWide { zoomButton(.ultraWide) }
            zoomButton(.standard)
            zoomButton(.tele)
        }
        .padding(.bottom, 8)
    }

    private func zoomButton(_ preset: ZoomPreset) -> some View {
        let selected = vm.zoomPreset == preset
        return Button { vm.setZoomPreset(preset) } label: {
            Text(preset.label)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(selected ? .black : .white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selected ? Color.accentOrange : Color.black.opacity(0.45), in: Capsule())
        }
        .disabled(vm.isRecording)
        .opacity(vm.isRecording ? 0.4 : 1)
        .animation(.easeInOut(duration: 0.15), value: selected)
        .sensoryFeedback(.selection, trigger: selected)
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        HStack {
            controlButton(
                systemImage: vm.isSwitchingCamera
                    ? "arrow.triangle.2.circlepath.camera.fill"
                    : "arrow.triangle.2.circlepath.camera",
                label: "Changer de caméra",
                disabled: false,
                action: vm.switchCamera
            )

            Spacer()

            RecordButton(isRecording: vm.isRecording || vm.countdown != nil) {
                if !entitlements.isPro,
                   let limit = entitlements.maxVlogDuration,
                   vm.totalDuration >= limit,
                   !vm.isRecording {
                    Analytics.track(.freeLimitReached, ["total_duration": vm.totalDuration])
                    showPaywall = true
                } else {
                    vm.toggleRecording()
                }
            }

            Spacer()

            Button { showPreview = true } label: {
                Text("Terminer")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.white, in: Capsule())
            }
            .frame(width: 96)
            .opacity(vm.canFinish ? 1 : 0)
            .disabled(!vm.canFinish)
            .accessibilityHidden(!vm.canFinish)
        }
        .padding(.horizontal, 24)
    }

    private func controlButton(systemImage: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(.black.opacity(0.35), in: Circle())
        }
        .frame(width: 96)
        .opacity(disabled ? 0.35 : 1)
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    private func formatDuration(_ s: Double) -> String {
        let t = Int(s.rounded())
        return t < 60 ? "\(t) s" : String(format: "%d:%02d", t / 60, t % 60)
    }
}
