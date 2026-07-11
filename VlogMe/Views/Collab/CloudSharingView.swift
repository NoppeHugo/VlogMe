import SwiftUI
import CloudKit
import UIKit

/// Feuille d'invitation iCloud native (lien iMessage, gestion des participants,
/// arrêt du partage) pour un vlog à plusieurs.
struct CloudSharingView: UIViewControllerRepresentable {

    let share: CKShare
    let container: CKContainer
    let title: String
    var onStopSharing: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        // Invitation privée uniquement (pas de lien public) : le créateur
        // contrôle exactement qui participe.
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let parent: CloudSharingView
        init(_ parent: CloudSharingView) { self.parent = parent }

        func itemTitle(for csc: UICloudSharingController) -> String? { parent.title }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            // L'utilisateur verra l'erreur dans la feuille native ; rien à faire côté app.
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {}

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            parent.onStopSharing?()
        }
    }
}
