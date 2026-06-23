import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct ExportSheet: View {

    @StateObject private var vm: ExportViewModel
    @EnvironmentObject private var store: VlogStore
    @Environment(\.dismiss) private var dismiss

    @State private var baseThumb: UIImage? = nil
    @State private var showMusicPicker = false
    @State private var showReviewPrompt = false
    @AppStorage("hasAskedReview") private var hasAskedReview = false

    init(store: VlogStore, entitlements: Entitlements) {
        _vm = StateObject(wrappedValue: ExportViewModel(store: store, entitlements: entitlements))
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            VStack(spacing: 28) { content }.padding(32)
        }
        .task { await loadThumbnail() }
        .onChange(of: vm.exportedURL) { _, url in
            // Après le tout premier vlog exporté, on propose la review.
            guard url != nil, !hasAskedReview else { return }
            hasAskedReview = true
            Analytics.track(.firstVlogExported)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                showReviewPrompt = true
            }
        }
        .sheet(isPresented: $vm.showShareSheet) {
            if let url = vm.exportedURL { ShareSheet(items: [url]) }
        }
        .sheet(isPresented: $showMusicPicker) {
            MusicPickerView { pickedURL in
                showMusicPicker = false
                if let pickedURL {
                    vm.setMusic(url: pickedURL, volume: vm.musicVolume)
                }
            }
        }
        .sheet(isPresented: $showReviewPrompt) {
            ReviewPromptView()
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
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Préparer l'export")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    // Aperçu du filtre
                    if let thumb = baseThumb {
                        FilterPreviewImage(image: thumb, preset: vm.filterPreset)
                    }

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

                    introSection

                    hookSection

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

                    // Musique de fond
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Musique de fond")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))

                        if let musicURL = vm.musicURL {
                            HStack(spacing: 10) {
                                Image(systemName: "music.note")
                                    .foregroundStyle(Color.accentOrange)
                                Text(musicURL.deletingPathExtension().lastPathComponent)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Spacer()
                                Button { vm.removeMusic() } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                            HStack {
                                Image(systemName: "speaker.fill")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.4))
                                Slider(value: $vm.musicVolume, in: 0...1) { _ in
                                    vm.setMusic(url: musicURL, volume: vm.musicVolume)
                                }
                                .tint(Color.accentOrange)
                                Image(systemName: "speaker.wave.3.fill")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        } else {
                            Button { showMusicPicker = true } label: {
                                Label("Choisir une musique", systemImage: "music.note")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
                .padding(.bottom, 20)
            }

            VStack(spacing: 10) {
                Button {
                    Task { await vm.export() }
                } label: {
                    HStack {
                        Spacer()
                        Label("Exporter · \(vm.resolutionLabel)", systemImage: "square.and.arrow.up")
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
            .padding(.top, 12)
        }
    }

    // MARK: - Intro stylée

    private var introEnabledBinding: Binding<Bool> {
        Binding(
            get: { vm.introStyle.isEnabled },
            set: { on in
                vm.setIntro(
                    style: on ? (lastIntroStyle) : .none,
                    text: vm.introText,
                    subtitle: vm.introSubtitle
                )
            }
        )
    }

    private var lastIntroStyle: IntroStyle {
        vm.introStyle.isEnabled ? vm.introStyle : .minimal
    }

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("Intro stylée")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(Color.accentOrange)
                Spacer()
                Toggle("", isOn: introEnabledBinding)
                    .labelsHidden()
                    .tint(Color.accentOrange)
            }

            if vm.introStyle.isEnabled {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(IntroStyle.selectable) { style in
                            FilterChip(
                                label: style.label,
                                isSelected: vm.introStyle == style
                            ) {
                                vm.setIntro(style: style, text: vm.introText, subtitle: vm.introSubtitle)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }

                TextField("", text: introTextBinding, prompt: Text("Titre (ex : vlog)").foregroundColor(.white.opacity(0.35)))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .submitLabel(.done)

                TextField("", text: introSubtitleBinding, prompt: Text("Sous-titre (ex : day in my life)").foregroundColor(.white.opacity(0.35)))
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .submitLabel(.done)
            }
        }
    }

    private var introTextBinding: Binding<String> {
        Binding(
            get: { vm.introText },
            set: { vm.setIntro(style: vm.introStyle, text: $0, subtitle: vm.introSubtitle) }
        )
    }

    private var introSubtitleBinding: Binding<String> {
        Binding(
            get: { vm.introSubtitle },
            set: { vm.setIntro(style: vm.introStyle, text: vm.introText, subtitle: $0) }
        )
    }

    // MARK: - Hook montage

    private var hookSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { vm.hookEnabled },
                set: { vm.setHook(enabled: $0, gap: vm.hookGap) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hook · clips qui s'enchaînent")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Aperçu rapide des premiers clips au début, façon TikTok")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .tint(Color.accentOrange)

            if vm.hookEnabled {
                HStack {
                    Text("Rythme")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    Slider(
                        value: Binding(
                            get: { vm.hookGap },
                            set: { vm.setHook(enabled: true, gap: $0) }
                        ),
                        in: 0.1...0.2
                    )
                    .tint(Color.accentOrange)
                    Text(String(format: "%.2fs", vm.hookGap))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 44, alignment: .trailing)
                }
            }
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

                HStack(spacing: 12) {
                    Button { vm.shareToInstagram() } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "camera")
                            Text("Instagram")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.83, green: 0.18, blue: 0.53), Color(red: 0.99, green: 0.45, blue: 0.24)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .foregroundStyle(.white)
                    }

                    Button { vm.shareToTikTok() } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "music.note")
                            Text("TikTok")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.15), lineWidth: 1))
                        .foregroundStyle(.white)
                    }
                }
            }
            .controlSize(.large)

            if let message = vm.saveMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }

            Divider().background(.white.opacity(0.2))

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

    private func loadThumbnail() async {
        guard let first = store.segments.first else { return }
        let url = store.url(for: first)
        baseThumb = await ThumbnailGenerator.thumbnail(for: url, maxSize: 600)
    }
}

// MARK: - Aperçu filtre (image animée)

private struct FilterPreviewImage: View {
    let image: UIImage
    let preset: FilterPreset

    var filtered: UIImage {
        guard preset != .none,
              let ci = CIImage(image: image) else { return image }
        let output = preset.apply(to: ci)
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(output, from: ci.extent) else { return image }
        return UIImage(cgImage: cg)
    }

    var body: some View {
        Image(uiImage: filtered)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .animation(.easeInOut(duration: 0.25), value: preset.id)
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
