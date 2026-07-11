import CloudKit
import Combine
import Network
import UIKit

/// Synchronisation des vlogs à plusieurs via CloudKit.
///
/// Architecture :
/// - chaque vlog partagé vit dans une **zone CloudKit dédiée** (`vlog-<uuid>`) de la base
///   privée du créateur, partagée aux invités via un `CKShare` de zone (lien iMessage) ;
/// - chaque clip est un record `CollabSegment` (métadonnées + vidéo en `CKAsset`) ;
/// - les clips filmés hors connexion partent dans une **file d'upload persistée** qui se
///   vide automatiquement dès que le réseau revient (`NWPathMonitor`) ;
/// - au montage, tous les clips sont remis dans l'ordre chronologique réel grâce à
///   `VideoSegment.capturedAt` — aucune horloge partagée nécessaire, pas de conflit
///   possible : une session est purement additive (chacun n'écrit que ses clips).
///
/// La fonctionnalité est désactivable à la compilation près : tant que la clé Info.plist
/// `VLOGME_COLLAB_ENABLED` est à NO (ou que l'entitlement iCloud n'est pas configuré),
/// aucun appel CloudKit n'est fait — l'app reste 100 % fonctionnelle en local.
@MainActor
final class CollabSyncService: ObservableObject {

    static let shared = CollabSyncService()

    static let containerID = "iCloud.com.hugonoppe.vlogme"
    static let segmentRecordType = "CollabSegment"
    static let zonePrefix = "vlog-"

    enum Availability: Equatable {
        case disabled            // clé Info.plist absente/NO → feature invisible
        case checking
        case ready
        case noICloudAccount
        case error(String)
    }

    // MARK: - État observable (UI)

    @Published private(set) var availability: Availability = .disabled
    @Published private(set) var pendingUploadCount = 0
    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?
    /// Partage CloudKit du brouillon actif (liste des participants pour l'UI).
    @Published private(set) var activeShare: CKShare?
    /// Nom du vlog qu'on vient de rejoindre via une invitation (bannière UI).
    @Published var justJoinedVlogName: String?

    /// Nom affiché aux autres participants sur mes clips.
    @Published var displayName: String {
        didSet { UserDefaults.standard.set(displayName, forKey: "collabDisplayName") }
    }

    // MARK: - Privé

    private weak var store: VlogStore?
    private var container: CKContainer?
    private var myRecordName: String?
    private let pathMonitor = NWPathMonitor()
    private var isNetworkAvailable = false
    private var isFlushing = false

    private struct PendingUpload: Codable, Equatable {
        let draftId: UUID
        let segmentId: UUID
    }

    private struct SyncState: Codable {
        var pendingUploads: [PendingUpload] = []
        var changeTokens: [String: Data] = [:]
        var subscriptionsRegistered = false
    }

    private var state = SyncState() {
        didSet {
            pendingUploadCount = state.pendingUploads.count
            persistState()
        }
    }
    private let stateURL: URL

    private static var isEnabledInBuild: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "VLOGME_COLLAB_ENABLED") as? Bool) ?? false
    }

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        stateURL = docs.appendingPathComponent("collab_sync_state.json")
        displayName = UserDefaults.standard.string(forKey: "collabDisplayName")
            ?? UIDevice.current.name
        if let data = try? Data(contentsOf: stateURL),
           let restored = try? JSONDecoder().decode(SyncState.self, from: data) {
            state = restored
            pendingUploadCount = restored.pendingUploads.count
        }
    }

    // MARK: - Démarrage

    /// À appeler une fois au lancement. Sans le flag build, ne fait rien.
    func configure(store: VlogStore) {
        guard self.store == nil else { return }
        self.store = store

        store.onLocalSegmentAdded = { [weak self] segment, draft in
            self?.enqueueUpload(segment: segment, draft: draft)
        }
        store.onLocalSegmentDeleted = { [weak self] segment, draft in
            self?.handleLocalDeletion(segment: segment, draft: draft)
        }

        guard Self.isEnabledInBuild else {
            availability = .disabled
            return
        }
        availability = .checking
        container = CKContainer(identifier: Self.containerID)

        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasAvailable = self.isNetworkAvailable
                self.isNetworkAvailable = (path.status == .satisfied)
                // Retour du réseau → on vide la file et on récupère les clips des autres.
                if !wasAvailable && self.isNetworkAvailable {
                    await self.syncAll()
                }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "collab.network"))

        UIApplication.shared.registerForRemoteNotifications()

        Task { await refreshAvailability() }
    }

    func refreshAvailability() async {
        guard let container else { return }
        do {
            switch try await container.accountStatus() {
            case .available:
                availability = .ready
                myRecordName = try? await container.userRecordID().recordName
                await registerSubscriptionsIfNeeded()
                await syncAll()
            case .noAccount, .restricted, .temporarilyUnavailable:
                availability = .noICloudAccount
            case .couldNotDetermine:
                availability = .error("Impossible de vérifier le compte iCloud.")
            @unknown default:
                availability = .error("Compte iCloud indisponible.")
            }
        } catch {
            availability = .error(error.localizedDescription)
        }
    }

    var isReady: Bool { availability == .ready }

    /// Container exposé pour `UICloudSharingController`.
    var cloudKitContainer: CKContainer? { container }

    /// Fait remonter une erreur d'action UI dans le bandeau d'état.
    func reportError(_ message: String) { lastError = message }

    // MARK: - Bases et zones

    private func zoneID(for draft: VlogDraft) -> CKRecordZone.ID? {
        guard let zoneName = draft.collabZoneName else { return nil }
        return CKRecordZone.ID(
            zoneName: zoneName,
            ownerName: draft.collabOwnerName ?? CKCurrentUserDefaultName
        )
    }

    /// Base privée pour mes sessions, base partagée pour celles que j'ai rejointes.
    private func database(for draft: VlogDraft) -> CKDatabase? {
        guard let container else { return nil }
        return draft.collabOwnerName == nil
            ? container.privateCloudDatabase
            : container.sharedCloudDatabase
    }

    // MARK: - Créer une session partagée (côté créateur)

    /// Crée la zone + le partage de zone pour un brouillon, et marque le brouillon partagé.
    /// Retourne le `CKShare` à présenter dans `UICloudSharingController`.
    func startSharing(draft: VlogDraft) async throws -> CKShare {
        guard let container, let store else {
            throw CKError(.internalError)
        }
        let zoneName = Self.zonePrefix + draft.id.uuidString
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        let database = container.privateCloudDatabase

        _ = try await database.save(CKRecordZone(zoneID: zoneID))

        // Partage de zone (zone-wide share) : tout record écrit dans la zone est partagé.
        let share: CKShare
        if let existing = try? await database.record(
            for: CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        ) as? CKShare {
            share = existing
        } else {
            let newShare = CKShare(recordZoneID: zoneID)
            newShare[CKShare.SystemFieldKey.title] = draft.name as CKRecordValue
            newShare.publicPermission = .none   // invitation privée uniquement
            share = try await database.save(newShare) as? CKShare ?? newShare
        }

        store.markShared(draft.id, zoneName: zoneName)
        activeShare = share
        Analytics.track(.collabStarted, ["draft_id": draft.id.uuidString])

        // Les clips déjà filmés partent dans la file d'upload.
        if let fresh = store.drafts.first(where: { $0.id == draft.id }) {
            for segment in fresh.segments where segment.isMine {
                enqueueUpload(segment: segment, draft: fresh)
            }
        }
        return share
    }

    /// Recharge le partage existant d'un brouillon (participants à jour pour l'UI).
    func refreshShare(for draft: VlogDraft) async {
        guard isReady, draft.isShared,
              let zoneID = zoneID(for: draft),
              let database = database(for: draft) else {
            activeShare = nil
            return
        }
        activeShare = try? await database.record(
            for: CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        ) as? CKShare
    }

    /// Arrêt du partage (créateur : supprime la zone ; invité : quitte la session).
    func stopSharing(draft: VlogDraft) async {
        guard let store else { return }
        if let container, let zoneID = zoneID(for: draft) {
            if draft.collabOwnerName == nil {
                // Créateur : supprime la zone entière (fin de session pour tout le monde).
                _ = try? await container.privateCloudDatabase.deleteRecordZone(withID: zoneID)
            } else {
                // Invité : supprimer la zone de SA base partagée = quitter la session
                // (les données du créateur ne sont pas touchées).
                _ = try? await container.sharedCloudDatabase.deleteRecordZone(withID: zoneID)
            }
        }
        state.pendingUploads.removeAll { $0.draftId == draft.id }
        state.changeTokens[tokenKey(for: draft)] = nil
        store.markUnshared(draft.id)
        activeShare = nil
    }

    // MARK: - Rejoindre une session (invité)

    /// Accepte une invitation (lien iCloud tapé par l'invité) et crée le brouillon miroir.
    func acceptShare(metadata: CKShare.Metadata) async {
        guard Self.isEnabledInBuild, let container, let store else { return }
        do {
            _ = try await container.accept(metadata)
            let zoneID = metadata.share.recordID.zoneID
            let zoneName = zoneID.zoneName
            guard zoneName.hasPrefix(Self.zonePrefix),
                  let draftId = UUID(uuidString: String(zoneName.dropFirst(Self.zonePrefix.count)))
            else { return }

            let name = (metadata.share[CKShare.SystemFieldKey.title] as? String) ?? "Vlog partagé"
            let draft = store.joinSharedDraft(
                id: draftId,
                name: name,
                zoneName: zoneName,
                ownerName: zoneID.ownerName
            )
            justJoinedVlogName = draft.name
            Analytics.track(.collabJoined, ["draft_id": draftId.uuidString])
            await syncDown(draft: draft)
        } catch {
            lastError = "Impossible de rejoindre le vlog : \(error.localizedDescription)"
        }
    }

    // MARK: - Upload (file persistée, vidée au retour du réseau)

    private func enqueueUpload(segment: VideoSegment, draft: VlogDraft) {
        guard draft.isShared else { return }
        let entry = PendingUpload(draftId: draft.id, segmentId: segment.id)
        guard !state.pendingUploads.contains(entry) else { return }
        state.pendingUploads.append(entry)
        Task { await flushUploads() }
    }

    private func handleLocalDeletion(segment: VideoSegment, draft: VlogDraft) {
        // Pas encore uploadé → il suffit de le retirer de la file.
        if let idx = state.pendingUploads.firstIndex(
            of: PendingUpload(draftId: draft.id, segmentId: segment.id)
        ) {
            state.pendingUploads.remove(at: idx)
            return
        }
        guard isReady, let zoneID = zoneID(for: draft), let database = database(for: draft) else { return }
        let recordID = CKRecord.ID(recordName: segment.id.uuidString, zoneID: zoneID)
        Task { _ = try? await database.deleteRecord(withID: recordID) }
    }

    /// Tente d'envoyer tous les clips en attente. Sans réseau ou sans compte, ne fait
    /// rien : la file reste sur disque et sera rejouée plus tard.
    func flushUploads() async {
        guard isReady, isNetworkAvailable, !isFlushing, let store else { return }
        guard !state.pendingUploads.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }
        isSyncing = true
        defer { isSyncing = false }

        for entry in state.pendingUploads {
            guard let draft = store.drafts.first(where: { $0.id == entry.draftId }),
                  draft.isShared,
                  let segment = draft.segments.first(where: { $0.id == entry.segmentId }),
                  let zoneID = zoneID(for: draft),
                  let database = database(for: draft)
            else {
                state.pendingUploads.removeAll { $0 == entry }
                continue
            }

            let fileURL = store.url(for: segment, in: draft)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                state.pendingUploads.removeAll { $0 == entry }
                continue
            }

            let recordID = CKRecord.ID(recordName: segment.id.uuidString, zoneID: zoneID)
            let record = CKRecord(recordType: Self.segmentRecordType, recordID: recordID)
            record["fileName"]   = segment.fileName as CKRecordValue
            record["duration"]   = segment.durationSeconds as CKRecordValue
            record["facing"]     = segment.facing.rawValue as CKRecordValue
            record["createdAt"]  = segment.createdAt as CKRecordValue
            record["capturedAt"] = (segment.capturedAt ?? segment.createdAt) as CKRecordValue
            record["authorID"]   = (myRecordName ?? "moi") as CKRecordValue
            record["authorName"] = displayName as CKRecordValue
            if let city = segment.city {
                record["city"] = city as CKRecordValue
            }
            record["video"]      = CKAsset(fileURL: fileURL)

            do {
                _ = try await database.save(record)
                state.pendingUploads.removeAll { $0 == entry }
                lastError = nil
                Analytics.track(.collabSegmentUploaded, ["draft_id": draft.id.uuidString])
            } catch let error as CKError where error.code == .serverRecordChanged {
                // Déjà présent (ré-upload après coupure) : considéré envoyé.
                state.pendingUploads.removeAll { $0 == entry }
            } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
                // La session n'existe plus (partage arrêté) → repasse le vlog en local.
                store.markUnshared(draft.id)
                state.pendingUploads.removeAll { $0.draftId == draft.id }
                lastError = "Le vlog partagé « \(draft.name) » n'existe plus, il repasse en local."
            } catch {
                // Réseau instable / quota : on garde l'entrée, on réessaiera.
                lastError = error.localizedDescription
                break
            }
        }
    }

    // MARK: - Download (clips des autres participants)

    /// Synchronise tous les vlogs partagés (appelé au lancement, au premier plan,
    /// au retour du réseau et à la réception d'un push silencieux CloudKit).
    func syncAll() async {
        guard isReady, isNetworkAvailable, let store else { return }
        await flushUploads()
        for draft in store.sharedDrafts {
            await syncDown(draft: draft)
        }
    }

    private func tokenKey(for draft: VlogDraft) -> String {
        "\(draft.collabZoneName ?? "")|\(draft.collabOwnerName ?? "me")"
    }

    /// Récupère les changements incrémentaux de la zone du vlog (nouveaux clips,
    /// suppressions) et les applique localement.
    func syncDown(draft: VlogDraft) async {
        guard isReady, let store,
              let zoneID = zoneID(for: draft),
              let database = database(for: draft) else { return }
        isSyncing = true
        defer { isSyncing = false }

        let key = tokenKey(for: draft)
        var token: CKServerChangeToken? = state.changeTokens[key].flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
        }

        var moreComing = true
        while moreComing {
            do {
                let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)

                var upserts: [VideoSegment] = []
                for (_, result) in changes.modificationResultsByID {
                    guard let record = try? result.get().record,
                          record.recordType == Self.segmentRecordType else { continue }
                    if let segment = await materialize(record: record, draft: draft, store: store) {
                        upserts.append(segment)
                    }
                }
                let deletedIDs = changes.deletions.compactMap { UUID(uuidString: $0.recordID.recordName) }
                    // Ne supprime pas un clip local encore en attente d'upload.
                    .filter { id in !state.pendingUploads.contains(where: { $0.segmentId == id }) }

                if !upserts.isEmpty || !deletedIDs.isEmpty {
                    store.applyRemoteChanges(draftId: draft.id, upserts: upserts, deletedIDs: deletedIDs)
                }

                token = changes.changeToken
                if let data = try? NSKeyedArchiver.archivedData(
                    withRootObject: changes.changeToken, requiringSecureCoding: true
                ) {
                    state.changeTokens[key] = data
                }
                moreComing = changes.moreComing
                lastError = nil
            } catch let error as CKError where error.code == .changeTokenExpired {
                token = nil
                state.changeTokens[key] = nil
            } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
                store.markUnshared(draft.id)
                lastError = "Le vlog partagé « \(draft.name) » n'existe plus, il repasse en local."
                return
            } catch {
                lastError = error.localizedDescription
                return
            }
        }
    }

    /// Transforme un record CloudKit en `VideoSegment` local : copie la vidéo dans le
    /// dossier du brouillon et reconstruit les métadonnées. Ignore mes propres clips
    /// (déjà présents sur cet appareil).
    private func materialize(record: CKRecord, draft: VlogDraft, store: VlogStore) async -> VideoSegment? {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return nil }
        let authorID = record["authorID"] as? String

        // Clip déjà local et filmé ici → la copie locale fait foi.
        if draft.segments.contains(where: { $0.id == id && $0.isMine }) { return nil }
        if let myRecordName, authorID == myRecordName,
           draft.segments.contains(where: { $0.id == id }) { return nil }

        guard
            let fileName = record["fileName"] as? String,
            let duration = record["duration"] as? Double
        else { return nil }

        // Copie l'asset téléchargé dans le dossier du brouillon (si pas déjà fait).
        let destination = store.segmentsDirectory(for: draft.id).appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: destination.path) {
            guard let assetURL = (record["video"] as? CKAsset)?.fileURL,
                  (try? FileManager.default.copyItem(at: assetURL, to: destination)) != nil
            else { return nil }
        }

        let facing = (record["facing"] as? String).flatMap(CameraFacing.init(rawValue:)) ?? .back
        return VideoSegment(
            id: id,
            fileName: fileName,
            durationSeconds: duration,
            facing: facing,
            createdAt: (record["createdAt"] as? Date) ?? Date(),
            capturedAt: record["capturedAt"] as? Date,
            authorID: authorID ?? "inconnu",
            authorName: record["authorName"] as? String,
            city: record["city"] as? String
        )
    }

    // MARK: - Push silencieux (nouveaux clips pendant que l'app tourne)

    private func registerSubscriptionsIfNeeded() async {
        guard let container, !state.subscriptionsRegistered else { return }
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true

        let privateSub = CKDatabaseSubscription(subscriptionID: "collab-private-db")
        privateSub.notificationInfo = info
        let sharedSub = CKDatabaseSubscription(subscriptionID: "collab-shared-db")
        sharedSub.notificationInfo = info

        do {
            _ = try await container.privateCloudDatabase.save(privateSub)
            _ = try await container.sharedCloudDatabase.save(sharedSub)
            state.subscriptionsRegistered = true
        } catch {
            // Non bloquant : la synchro au premier plan et au retour réseau suffit.
        }
    }

    /// À appeler depuis l'AppDelegate quand un push CloudKit arrive.
    func handleRemoteNotification() {
        Task { await syncAll() }
    }

    // MARK: - Persistance

    private func persistState() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }
}
