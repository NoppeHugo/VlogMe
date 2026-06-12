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
        .sheet(isPresented: $vm.showShareSheet) {
            if let url = vm.exportedURL { ShareSheet(items: [url]) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .idle:              configView
        case .exporting:        exportingView
        case .ready:            readyView
        case .failed(let msg):  failedView(msg)
        }
    }

    // MARK: - Configuration (choix filtre + silence)

    private var configView: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Préparer l'export")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            // Filtre
            VStack(alignment: .leading, spacing: 12) {
                Text("Filtre")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FilterPreset.allCases) { preset in
                            FilterChip(
                                label: preset.label,
                                isSelected: vm.filterPreset == preset
                            ) {
                                vm.setFilter(preset)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }

            // Silence automatique
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $vm.cutSilence) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Couper les silences")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Supprime les passages sans son avant l'export")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .tint(Color.accentOrange)
            }

            Spacer()

            Button {
                Task { await vm.export() }
            } label: {
                HStack {
                    Spacer()
                    Label("Exporter  \(vm.resolutionLabel)", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.bold))
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentOrange)
            .controlSize(.large)

            Button("Annuler") { dismiss() }
                .foregroundStyle(.white.opacity(0.5))
                .font(.footnote)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Encodage en cours

    private var exportingView: some View {
        VStack(spacing: 20) {
            ProgressView(value: progressValue)
                .progressViewStyle(.linear)
                .tint(Color.accentOrange)
            Text(progressLabel)
                .font(.headline)
                .foregroundStyle(.white)
            Text(vm.resolutionLabel)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Prêt

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

            // Crée un nouveau brouillon (l'ancien reste dans la bibliothèque)
            Button {
                store.createDraft()
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

    // MARK: - Erreur

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

    // MARK: - Helpers

    private var progressValue: Double {
        if case .exporting(let p) = vm.state { return p }
        return 0
    }

    private var progressLabel: String {
        let pct = Int((progressValue * 100).rounded())
        if vm.cutSilence && progressValue < 0.15 { return "Analyse audio…" }
        if vm.filterPreset != .none && progressValue > 0.60 { return "Application du filtre…" }
        return "Encodage… \(pct) %"
    }
}

// MARK: - Filter chip

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentOrange : Color.white.opacity(0.12), in: Capsule())
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
