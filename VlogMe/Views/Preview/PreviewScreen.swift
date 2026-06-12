import SwiftUI
import AVKit

/// Écran 2 — Prévisualisation (cf. §4). Lecture de la vidéo assemblée, contrôles minimaux.
/// PAS de timeline d'édition. « Retour caméra » conserve tous les segments.
struct PreviewScreen: View {

    @StateObject private var vm: PreviewViewModel
    @EnvironmentObject private var store: VlogStore
    @EnvironmentObject private var entitlements: Entitlements
    @Environment(\.dismiss) private var dismiss
    @State private var showExport = false

    init(store: VlogStore) {
        _vm = StateObject(wrappedValue: PreviewViewModel(store: store))
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            switch vm.state {
            case .loading:
                ProgressView("Assemblage…")
                    .tint(.white)
                    .foregroundStyle(.white)

            case .ready(let player):
                VideoPlayer(player: player)
                    .ignoresSafeArea(edges: .top)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
                    .task {
                        guard let item = player.currentItem else { return }
                        for await status in item.publisher(for: \.status).values {
                            if status == .readyToPlay { player.play(); break }
                        }
                    }

            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                    Text(message)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .padding()
            }

            VStack {
                Spacer()
                bottomBar
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await vm.build() }
        .fullScreenCover(isPresented: $showExport) {
            ExportSheet(store: store, entitlements: entitlements)
        }
    }

    private var bottomBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Label("Retour caméra", systemImage: "camera.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(.black.opacity(0.5), in: Capsule())
            }

            Spacer()

            Button {
                showExport = true
            } label: {
                Label("Exporter", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(.white, in: Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}
