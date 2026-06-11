import SwiftUI

struct CameraScreen: View {

    @StateObject private var vm: CameraViewModel
    @Binding private var showPreview: Bool

    init(camera: CameraService, store: VlogStore, showPreview: Binding<Bool>) {
        _vm = StateObject(wrappedValue: CameraViewModel(camera: camera, store: store))
        _showPreview = showPreview
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreviewLayerView(
                session: vm.camera.session,
                onTapFocus: { vm.handleTapFocus($0) },
                onPinchZoom: { vm.handlePinchZoom($0) }
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                zoomIndicator
                if vm.hasSegments {
                    SegmentStackView(
                        segments: vm.segments,
                        urlFor: { vm.store.url(for: $0) },
                        onRedoLast: vm.redoLastSegment,
                        onDeleteLast: vm.deleteLastSegment
                    )
                    .padding(.bottom, 8)
                }
                bottomControls
            }
            .padding(.vertical, 12)
        }
        .statusBarHidden(true)
        .onAppear { vm.onAppear() }
        .onDisappear { vm.onDisappear() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            DurationLabel(seconds: vm.totalDuration, isRecording: vm.isRecording)
            Spacer()

            // Torch (front camera has no torch)
            if vm.facing == .back {
                Button { vm.toggleTorch() } label: {
                    Image(systemName: vm.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(vm.isTorchOn ? Color.accentOrange : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.45), in: Capsule())
                }
                .opacity(vm.controlsLocked ? 1 : 1)
                .accessibilityLabel(vm.isTorchOn ? "Éteindre la lampe" : "Allumer la lampe")
            }

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
            .accessibilityLabel("Changer le format vidéo")
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Zoom indicator (visible only when zoomed)

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

    // MARK: - Bottom controls

    private var bottomControls: some View {
        HStack {
            controlButton(
                systemImage: "arrow.triangle.2.circlepath.camera",
                label: "Changer de caméra",
                disabled: vm.controlsLocked,
                action: vm.switchCamera
            )

            Spacer()

            RecordButton(isRecording: vm.isRecording, action: vm.toggleRecording)

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

    private func controlButton(
        systemImage: String,
        label: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
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
}
