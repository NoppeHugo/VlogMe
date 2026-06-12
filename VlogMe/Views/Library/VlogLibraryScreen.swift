import SwiftUI

/// Liste des brouillons de vlogs. Accessible depuis l'écran caméra.
struct VlogLibraryScreen: View {

    @EnvironmentObject private var store: VlogStore
    @Environment(\.dismiss) private var dismiss

    @State private var draftToRename: VlogDraft?
    @State private var newName: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if store.drafts.isEmpty {
                    emptyState
                } else {
                    draftList
                }
            }
            .navigationTitle("Mes vlogs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        store.createDraft()
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .foregroundStyle(Color.accentOrange)
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .alert("Renommer", isPresented: Binding(
            get: { draftToRename != nil },
            set: { if !$0 { draftToRename = nil } }
        )) {
            TextField("Nom du vlog", text: $newName)
                .autocorrectionDisabled()
            Button("Annuler", role: .cancel) { draftToRename = nil }
            Button("OK") {
                if let d = draftToRename, !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                    store.renameDraft(d.id, name: newName)
                }
                draftToRename = nil
            }
        }
    }

    // MARK: - Draft list

    private var draftList: some View {
        List {
            ForEach(store.drafts) { draft in
                DraftRow(
                    draft: draft,
                    isActive: draft.id == store.activeId,
                    isDefault: draft.id == store.defaultId,
                    onTargetChanged: { store.updateTargetDuration($0) }
                )
                .listRowBackground(
                    draft.id == store.activeId
                        ? Color.accentOrange.opacity(0.12)
                        : Color.white.opacity(0.05)
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .contentShape(Rectangle())
                .onTapGesture {
                    store.activateDraft(draft.id)
                    dismiss()
                }
                .contextMenu {
                    Button {
                        store.activateDraft(draft.id)
                        dismiss()
                    } label: {
                        Label("Ouvrir", systemImage: "camera.fill")
                    }
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
                    } label: {
                        Label("Renommer", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) {
                        store.deleteDraft(draft.id)
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                }
            }
            .onDelete { indexSet in
                indexSet.forEach { store.deleteDraft(store.drafts[$0].id) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.3))
            Text("Aucun vlog")
                .foregroundStyle(.white.opacity(0.5))
            Button {
                store.createDraft()
                dismiss()
            } label: {
                Label("Nouveau vlog", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentOrange)
        }
    }
}

// MARK: - Draft row

private struct DraftRow: View {

    let draft: VlogDraft
    let isActive: Bool
    let isDefault: Bool
    let onTargetChanged: (Double?) -> Void

    @State private var showTargetPicker = false

    private static let targets: [(label: String, value: Double?)] = [
        ("Aucune", nil),
        ("30 s", 30),
        ("1 min", 60),
        ("1:30", 90),
        ("2 min", 120),
        ("3 min", 180)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                // Active indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(isActive ? Color.accentOrange : Color.clear)
                    .frame(width: 3)
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if isDefault {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.accentOrange)
                        }
                        Text(draft.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }

                    HStack(spacing: 8) {
                        Text(relativeDateString(draft.createdAt))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))

                        Text("·")
                            .foregroundStyle(.white.opacity(0.3))

                        Text("\(draft.segments.count) clip\(draft.segments.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))

                        if draft.hasSegments {
                            Text("·")
                                .foregroundStyle(.white.opacity(0.3))
                            Text(formatDuration(draft.totalDuration))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }

                Spacer()

                // Target duration button
                Button {
                    showTargetPicker = true
                } label: {
                    Group {
                        if let t = draft.targetDuration {
                            Text("/ \(formatDuration(t))")
                                .font(.caption.monospacedDigit().weight(.medium))
                                .foregroundStyle(Color.accentOrange)
                        } else {
                            Image(systemName: "scope")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.08), in: Capsule())
                }
                .confirmationDialog("Durée cible", isPresented: $showTargetPicker) {
                    ForEach(DraftRow.targets, id: \.label) { option in
                        Button(option.label) { onTargetChanged(option.value) }
                    }
                    Button("Annuler", role: .cancel) {}
                }
                .padding(.trailing, 16)
            }
            .padding(.vertical, 12)
            .padding(.leading, 4)

            Divider().background(.white.opacity(0.08)).padding(.leading, 19)
        }
    }

    private func formatDuration(_ s: Double) -> String {
        let t = Int(s.rounded())
        return t < 60 ? "\(t) s" : String(format: "%d:%02d", t / 60, t % 60)
    }

    private func relativeDateString(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Aujourd'hui" }
        if cal.isDateInYesterday(date) { return "Hier" }
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.locale = Locale(identifier: "fr_FR")
        return f.string(from: date)
    }
}
