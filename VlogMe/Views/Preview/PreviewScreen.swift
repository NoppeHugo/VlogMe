import SwiftUI
import AVKit

struct PreviewScreen: View {

    @StateObject private var vm: PreviewViewModel
    @EnvironmentObject private var store: VlogStore
    @EnvironmentObject private var entitlements: Entitlements
    @Environment(\.dismiss) private var dismiss
    @State private var showExport   = false

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

            // Aperçu du sticker (l'incrustation Core Animation n'apparaît pas
            // pendant la lecture AVPlayer — on la simule ici).
            if let draft = store.activeDraft, draft.stickerEnabled {
                let text = StickerRenderer.displayText(
                    text: draft.stickerText,
                    showDate: draft.stickerShowDate,
                    date: draft.createdAt
                )
                StickerOverlayView(text: text, position: draft.stickerPosition, style: draft.stickerStyle)
                    .ignoresSafeArea(edges: .top)
            }

            // Filigrane VlogMe pour les utilisateurs gratuits (retiré en Pro).
            if !entitlements.isPro {
                WatermarkOverlayView()
                    .ignoresSafeArea(edges: .top)
            }

            VStack {
                Spacer()
                bottomBar
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await vm.build(isPro: entitlements.isPro) }
        // Le filigrane disparaît immédiatement après l'achat.
        .onChange(of: entitlements.isPro) { _, _ in
            Task { await vm.build(isPro: entitlements.isPro) }
        }
        .fullScreenCover(isPresented: $showExport) {
            ExportSheet(store: store, entitlements: entitlements)
                .environmentObject(entitlements)
                .environmentObject(store)
        }
    }

    private var bottomBar: some View {
        HStack {
            Button { dismiss() } label: {
                Label("Retour caméra", systemImage: "camera.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(.black.opacity(0.5), in: Capsule())
            }

            Spacer()

            Button { handleExportTap() } label: {
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

    private func handleExportTap() {
        // Tout le monde peut ouvrir la feuille d'export pour voir les options.
        // Le mur (paywall) intervient au moment de lancer l'export, à l'intérieur.
        showExport = true
    }
}
