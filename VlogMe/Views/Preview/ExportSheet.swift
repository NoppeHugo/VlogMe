import SwiftUI

struct ExportSheet: View {

    @StateObject private var vm: ExportViewModel
    @EnvironmentObject private var store: VlogStore
    @Environment(\.dismiss) private var dismiss

    init(store: VlogStore, entitlements: Entitlements) {
        _vm = StateObject(wrappedValue: ExportViewModel(store: store, entitlements: entitlements))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 28) { content }.padding(32)
        }
        .task {
            if case .idle = vm.state { await vm.export() }
        }
        .sheet(isPresented: $vm.showShareSheet) {
            if let url = vm.exportedURL { ShareSheet(items: [url]) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .idle, .exporting: exportingView
        case .ready:            readyView
        case .failed(let msg):  failedView(msg)
        }
    }

    // MARK: - States

    private var exportingView: some View {
        VStack(spacing: 20) {
            ProgressView(value: progressValue)
                .progressViewStyle(.linear)
                .tint(Color.accentOrange)
            Text("Encodage… \(Int(progressValue * 100)) %")
                .font(.headline)
                .foregroundStyle(.white)
            Text(vm.resolutionLabel)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var readyView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentOrange)
            Text("Vidéo prête")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            VStack(spacing: 12) {
                Button {
                    Task { await vm.saveToPhotos() }
                } label: {
                    Label("Enregistrer dans Photos", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentOrange)

                Button { vm.share() } label: {
                    Label("Partager", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
            .controlSize(.large)

            if let message = vm.saveMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }

            Divider().background(.white.opacity(0.2))

            // New vlog — clears segments and returns to camera
            Button {
                store.clear()
                dismiss()
            } label: {
                Label("Nouveau vlog", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Color.accentOrange)
            .controlSize(.large)

            Button("Fermer") { dismiss() }
                .foregroundStyle(.white.opacity(0.5))
                .font(.footnote)
        }
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.yellow)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Button("Réessayer") { Task { await vm.export() } }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentOrange)
            Button("Fermer") { dismiss() }
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var progressValue: Double {
        if case .exporting(let p) = vm.state { return p }
        return 0
    }
}
