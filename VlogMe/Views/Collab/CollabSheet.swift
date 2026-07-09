import SwiftUI
import CloudKit

/// Feuille « Vlog à plusieurs » : inviter des amis dans le vlog actif, voir les
/// participants et l'état de synchronisation, quitter ou arrêter la session.
struct CollabSheet: View {

    @EnvironmentObject private var store: VlogStore
    @EnvironmentObject private var collab: CollabSyncService
    @Environment(\.dismiss) private var dismiss

    @State private var shareToPresent: ShareBox?
    @State private var isStartingShare = false
    @State private var confirmStop = false

    private struct ShareBox: Identifiable {
        let id = UUID()
        let share: CKShare
        let container: CKContainer
    }

    private var draft: VlogDraft? { store.activeDraft }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    content
                }
                .padding(28)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await collab.refreshAvailability()
            if let draft { await collab.refreshShare(for: draft) }
        }
        .sheet(item: $shareToPresent) { box in
            CloudSharingView(
                share: box.share,
                container: box.container,
                title: draft?.name ?? "Vlog partagé",
                onStopSharing: {
                    if let draft { Task { await collab.stopSharing(draft: draft) } }
                }
            )
        }
        .confirmationDialog(
            draft?.isCollabOwner == true
                ? "Arrêter le partage ? Les participants perdront l'accès aux clips des autres."
                : "Quitter ce vlog partagé ?",
            isPresented: $confirmStop,
            titleVisibility: .visible
        ) {
            Button(draft?.isCollabOwner == true ? "Arrêter le partage" : "Quitter", role: .destructive) {
                if let draft {
                    Task {
                        await collab.stopSharing(draft: draft)
                        dismiss()
                    }
                }
            }
            Button("Annuler", role: .cancel) {}
        }
    }

    // MARK: - En-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(Color.accentOrange)
                Text("Vlog à plusieurs")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }
            if let draft {
                Text(draft.name)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Contenu selon l'état

    @ViewBuilder
    private var content: some View {
        switch collab.availability {
        case .disabled:
            infoCard(
                icon: "wrench.and.screwdriver",
                title: "Bientôt disponible",
                message: "Le vlog à plusieurs nécessite l'activation d'iCloud dans la build (compte développeur Apple + capability CloudKit). Voir le README du projet pour l'activer."
            )
        case .checking:
            HStack(spacing: 12) {
                ProgressView().tint(Color.accentOrange)
                Text("Vérification du compte iCloud…")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
        case .noICloudAccount:
            infoCard(
                icon: "icloud.slash",
                title: "iCloud requis",
                message: "Connecte-toi à iCloud dans Réglages → ton nom, puis reviens ici pour créer un vlog à plusieurs."
            )
        case .error(let message):
            infoCard(icon: "exclamationmark.triangle", title: "iCloud indisponible", message: message)
        case .ready:
            if let draft {
                if draft.isShared { sharedContent(draft) } else { notSharedContent(draft) }
            }
        }
    }

    // MARK: - Pas encore partagé

    private func notSharedContent(_ draft: VlogDraft) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                bulletRow(icon: "video.fill", text: "Chacun filme ses clips de son côté, même sans connexion.")
                bulletRow(icon: "clock.arrow.2.circlepath", text: "Chaque clip mémorise l'heure exacte où il a été filmé.")
                bulletRow(icon: "wifi", text: "Dès qu'un participant retrouve du réseau, ses clips se synchronisent tout seuls.")
                bulletRow(icon: "wand.and.stars", text: "Le montage final remet tous les clips dans l'ordre réel de la journée.")
            }

            displayNameField

            Button {
                startSharing(draft)
            } label: {
                HStack {
                    Spacer()
                    if isStartingShare {
                        ProgressView().tint(.black)
                    } else {
                        Label("Inviter des amis", systemImage: "person.badge.plus")
                            .font(.subheadline.weight(.bold))
                    }
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentOrange)
            .controlSize(.large)
            .disabled(isStartingShare)

            Text("Jusqu'à \(draft.maxParticipants) personnes par vlog. Invitation privée par lien iMessage — toi seul choisis qui participe.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))

            if let error = collab.lastError {
                errorLabel(error)
            }
        }
    }

    // MARK: - Déjà partagé

    private func sharedContent(_ draft: VlogDraft) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            syncStatusCard

            // Participants
            VStack(alignment: .leading, spacing: 10) {
                Text("Participants")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
                if let share = collab.activeShare {
                    ForEach(Array(share.participants.enumerated()), id: \.offset) { _, participant in
                        participantRow(participant)
                    }
                    if share.participants.count >= draft.maxParticipants {
                        Text("Limite de \(draft.maxParticipants) participants atteinte.")
                            .font(.caption)
                            .foregroundStyle(Color.accentOrange)
                    }
                } else {
                    Text(draft.isCollabOwner
                         ? "Toi (créateur)"
                         : "Connecte-toi au réseau pour voir les participants.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            displayNameField

            VStack(spacing: 10) {
                if draft.isCollabOwner {
                    Button {
                        manageInvitation(draft)
                    } label: {
                        Label("Gérer l'invitation", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentOrange)
                    .controlSize(.large)
                }

                Button {
                    Task { await collab.syncAll() }
                } label: {
                    Label("Synchroniser maintenant", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .controlSize(.large)
                .disabled(collab.isSyncing)

                Button(role: .destructive) {
                    confirmStop = true
                } label: {
                    Label(draft.isCollabOwner ? "Arrêter le partage" : "Quitter ce vlog",
                          systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            if let error = collab.lastError {
                errorLabel(error)
            }
        }
    }

    // MARK: - Composants

    private var syncStatusCard: some View {
        HStack(spacing: 12) {
            if collab.isSyncing {
                ProgressView().tint(Color.accentOrange)
                Text("Synchronisation…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            } else if collab.pendingUploadCount > 0 {
                Image(systemName: "arrow.up.circle")
                    .foregroundStyle(Color.accentOrange)
                Text("\(collab.pendingUploadCount) clip\(collab.pendingUploadCount == 1 ? "" : "s") en attente d'envoi — ils partiront dès que le réseau revient.")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "checkmark.icloud")
                    .foregroundStyle(.green)
                Text("Tout est synchronisé")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(14)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func participantRow(_ participant: CKShare.Participant) -> some View {
        let formatter = PersonNameComponentsFormatter()
        let name = participant.userIdentity.nameComponents.map { formatter.string(from: $0) }
            ?? participant.userIdentity.lookupInfo?.emailAddress
            ?? "Invité"
        let detail: String
        switch (participant.role, participant.acceptanceStatus) {
        case (.owner, _):      detail = "créateur"
        case (_, .pending):    detail = "invitation envoyée"
        case (_, .accepted):   detail = "participe"
        default:               detail = ""
        }
        return HStack(spacing: 10) {
            Image(systemName: participant.role == .owner ? "crown.fill" : "person.fill")
                .font(.caption)
                .foregroundStyle(participant.role == .owner ? Color.accentOrange : .white.opacity(0.6))
            Text(name.isEmpty ? "Invité" : name)
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private var displayNameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ton nom dans le vlog")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
            TextField("", text: $collab.displayName,
                      prompt: Text("ex : Hugo").foregroundColor(.white.opacity(0.35)))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .submitLabel(.done)
        }
    }

    private func bulletRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(Color.accentOrange)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func infoCard(icon: String, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.yellow)
    }

    // MARK: - Actions

    @MainActor
    private func startSharing(_ draft: VlogDraft) {
        guard let container = collab.cloudKitContainer else { return }
        isStartingShare = true
        Task {
            defer { isStartingShare = false }
            do {
                let share = try await collab.startSharing(draft: draft)
                shareToPresent = ShareBox(share: share, container: container)
            } catch {
                collab.reportError(error.localizedDescription)
            }
        }
    }

    @MainActor
    private func manageInvitation(_ draft: VlogDraft) {
        guard let container = collab.cloudKitContainer else { return }
        Task {
            await collab.refreshShare(for: draft)
            if let share = collab.activeShare {
                shareToPresent = ShareBox(share: share, container: container)
            }
        }
    }
}
