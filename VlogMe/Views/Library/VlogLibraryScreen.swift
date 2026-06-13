import SwiftUI

struct VlogLibraryScreen: View {

    @EnvironmentObject private var store: VlogStore
    @Environment(\.dismiss) private var dismiss

    @State private var draftToRename: VlogDraft?
    @State private var newName: String = ""

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.cardBackground.ignoresSafeArea()

                Group {
                    if store.drafts.isEmpty { emptyState } else { draftGrid }
                }

                // Floating action button
                Button {
                    store.createDraft()
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .fontWeight(.bold)
                        Text("Nouveau vlog")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(Color.accentOrange, in: Capsule())
                    .shadow(color: Color.accentOrange.opacity(0.35), radius: 14, y: 6)
                }
                .padding(.bottom, 36)
                .sensoryFeedback(.impact(weight: .light), trigger: store.drafts.count)
            }
            .navigationTitle("Mes vlogs")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .toolbarBackground(Color.cardBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.light)
        .alert("Renommer", isPresented: Binding(
            get: { draftToRename != nil },
            set: { if !$0 { draftToRename = nil } }
        )) {
            TextField("Nom du vlog", text: $newName).autocorrectionDisabled()
            Button("Annuler", role: .cancel) { draftToRename = nil }
            Button("OK") {
                if let d = draftToRename, !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                    store.renameDraft(d.id, name: newName)
                }
                draftToRename = nil
            }
        }
    }

    // MARK: - Grille de cards

    private var draftGrid: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(store.drafts) { draft in
                    DraftCard(
                        draft: draft,
                        isActive: draft.id == store.activeId,
                        isDefault: draft.id == store.defaultId,
                        onTargetChanged: { store.updateTargetDuration($0, for: draft.id) },
                        onRename: { newName = draft.name; draftToRename = draft },
                        onSetDefault: { store.setDefault(draft.id) },
                        onDelete: { store.deleteDraft(draft.id) }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.activateDraft(draft.id)
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 110)
        }
    }

    // MARK: - État vide

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.accentOrange.opacity(0.6))
            Text("Aucun vlog")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.textPrimary)
            Text("Crée ton premier vlog pour commencer.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 80)
    }
}

// MARK: - Card brouillon

private struct DraftCard: View {

    let draft: VlogDraft
    let isActive: Bool
    let isDefault: Bool
    let onTargetChanged: (Double?) -> Void
    let onRename: () -> Void
    let onSetDefault: () -> Void
    let onDelete: () -> Void

    @State private var showTargetPicker = false

    private static let targets: [(label: String, value: Double?)] = [
        ("Aucune", nil), ("30 s", 30), ("1 min", 60),
        ("1:30", 90), ("2 min", 120), ("3 min", 180)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // — Ligne titre + badge actif
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if isDefault {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.accentOrange)
                        }
                        Text(draft.name.isEmpty ? "Sans titre" : draft.name)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                    }
                    Text(relativeDate(draft.createdAt))
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                if isActive {
                    Text("EN COURS")
                        .font(.system(size: 9, weight: .black))
                        .tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentOrange, in: Capsule())
                }
            }

            // — Badges clips + durée + durée cible
            HStack(spacing: 6) {
                metaBadge(
                    icon: "film.stack",
                    text: "\(draft.segments.count) clip\(draft.segments.count == 1 ? "" : "s")"
                )
                if draft.hasSegments {
                    metaBadge(icon: "clock", text: formatDuration(draft.totalDuration))
                }
                Spacer()

                // Bouton durée cible
                Button { showTargetPicker = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "scope")
                            .font(.caption2)
                        Text(draft.targetDuration.map { "/ \(formatDuration($0))" } ?? "Cible")
                            .font(.caption.weight(.semibold).monospacedDigit())
                    }
                    .foregroundStyle(draft.targetDuration != nil ? Color.accentOrange : Color.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        draft.targetDuration != nil
                            ? Color.accentOrange.opacity(0.1)
                            : Color.borderColor,
                        in: Capsule()
                    )
                }
                .confirmationDialog("Durée cible", isPresented: $showTargetPicker) {
                    ForEach(DraftCard.targets, id: \.label) { opt in
                        Button(opt.label) { onTargetChanged(opt.value) }
                    }
                    Button("Annuler", role: .cancel) {}
                }
            }

            // — Barre de progression (si durée cible définie)
            if let target = draft.targetDuration, draft.hasSegments {
                let progress = min(1.0, draft.totalDuration / target)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.borderColor).frame(height: 3)
                        Capsule()
                            .fill(progress >= 1 ? Color.green : Color.accentOrange)
                            .frame(width: geo.size.width * progress, height: 3)
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white)
                .shadow(
                    color: isActive ? Color.accentOrange.opacity(0.18) : .black.opacity(0.07),
                    radius: isActive ? 12 : 6,
                    y: 3
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isActive ? Color.accentOrange.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.2), value: isActive)
        .contextMenu {
            Button { onRename() } label: {
                Label("Renommer", systemImage: "pencil")
            }
            Button { onSetDefault() } label: {
                Label(
                    isDefault ? "Par défaut ✓" : "Définir par défaut",
                    systemImage: "star"
                )
            }
            Divider()
            Button(role: .destructive) { onDelete() } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    private func metaBadge(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(Color.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.borderColor, in: Capsule())
    }

    private func formatDuration(_ s: Double) -> String {
        let t = Int(s.rounded())
        return t < 60 ? "\(t) s" : String(format: "%d:%02d", t / 60, t % 60)
    }

    private func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Aujourd'hui" }
        if cal.isDateInYesterday(date) { return "Hier" }
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.locale = Locale(identifier: "fr_FR")
        return f.string(from: date)
    }
}
