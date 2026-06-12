import SwiftUI

/// Liste des brouillons de vlogs — thème clair (DA §1).
struct VlogLibraryScreen: View {

    @EnvironmentObject private var store: VlogStore
    @Environment(\.dismiss) private var dismiss

    @State private var draftToRename: VlogDraft?
    @State private var newName: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.cardBackground.ignoresSafeArea()
                if store.drafts.isEmpty { emptyState } else { draftList }
            }
            .navigationTitle("Mes vlogs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        store.createDraft()
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Color.accentOrange)
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

    // MARK: - Liste

    private var draftList: some View {
        List {
            ForEach(store.drafts) { draft in
                DraftRow(
                    draft: draft,
                    isActive: draft.id == store.activeId,
                    isDefault: draft.id == store.defaultId,
                    onTargetChanged: { store.updateTargetDuration($0, for: draft.id) }
                )
                .listRowBackground(Color.white)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
                .contentShape(Rectangle())
                .onTapGesture {
                    store.activateDraft(draft.id)
                    dismiss()
                }
                .contextMenu {
                    Button {
                        store.activateDraft(draft.id)
                        dismiss()
                    } label: { Label("Ouvrir", systemImage: "camera.fill") }

                    Button {
                        store.setDefault(draft.id)
                    } label: {
                        Label(
                            draft.id == store.defaultId ? "Par défaut ✓" : "Définir par défaut",
                            systemImage: "star"
                        )
                    }

                    Button {
                        newName = draft.name
                        draftToRename = draft
                    } label: { Label("Renommer", systemImage: "pencil") }

                    Divider()

                    Button(role: .destructive) {
                        store.deleteDraft(draft.id)
                    } label: { Label("Supprimer", systemImage: "trash") }
                }
            }
            .onDelete { indexSet in
                indexSet.forEach { store.deleteDraft(store.drafts[$0].id) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.cardBackground)
    }

    // MARK: - État vide

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Color.textSecondary)
            Text("Aucun vlog")
                .font(.headline)
                .foregroundStyle(Color.textSecondary)
            Button {
                store.createDraft()
                dismiss()
            } label: {
                Text("Nouveau vlog")
            }
            .buttonStyle(OrangeButton())
        }
    }
}

// MARK: - Ligne brouillon

private struct DraftRow: View {

    let draft: VlogDraft
    let isActive: Bool
    let isDefault: Bool
    let onTargetChanged: (Double?) -> Void

    @State private var showTargetPicker = false

    private static let targets: [(label: String, value: Double?)] = [
        ("Aucune", nil), ("30 s", 30), ("1 min", 60),
        ("1:30", 90), ("2 min", 120), ("3 min", 180)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                // Indicateur actif
                Rectangle()
                    .fill(isActive ? Color.accentOrange : Color.clear)
                    .frame(width: 3)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            if isDefault {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(Color.accentOrange)
                            }
                            Text(draft.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                        }

                        HStack(spacing: 6) {
                            Text(relativeDate(draft.createdAt))
                            Text("·")
                            Text("\(draft.segments.count) clip\(draft.segments.count == 1 ? "" : "s")")
                            if draft.hasSegments {
                                Text("·")
                                Text(formatDuration(draft.totalDuration))
                                    .monospacedDigit()
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    }

                    Spacer()

                    // Durée cible
                    Button { showTargetPicker = true } label: {
                        Group {
                            if let t = draft.targetDuration {
                                Text("/ \(formatDuration(t))")
                                    .font(.caption.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(Color.accentOrange)
                            } else {
                                Image(systemName: "scope")
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.borderColor, in: Capsule())
                    }
                    .confirmationDialog("Durée cible", isPresented: $showTargetPicker) {
                        ForEach(DraftRow.targets, id: \.label) { opt in
                            Button(opt.label) { onTargetChanged(opt.value) }
                        }
                        Button("Annuler", role: .cancel) {}
                    }
                    .padding(.trailing, 16)
                }
                .padding(.vertical, 14)
                .padding(.leading, 12)
            }

            Divider()
                .background(Color.borderColor)
                .padding(.leading, 15)
        }
    }

    private func formatDuration(_ s: Double) -> String {
        let t = Int(s.rounded())
        return t < 60 ? "\(t) s" : String(format: "%d:%02d", t / 60, t % 60)
    }

    private func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Aujourd'hui" }
        if cal.isDateInYesterday(date) { return "Hier" }
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.locale = Locale(identifier: "fr_FR")
        return f.string(from: date)
    }
}
