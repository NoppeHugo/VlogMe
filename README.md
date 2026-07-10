# VlogMe — iOS (Swift + AVFoundation)

> Une caméra qui monte tes vlogs toute seule. Filme par petits clips → vidéo montée, prête à publier, sans ouvrir d'éditeur.

Ce dépôt contient le **socle de code des Phases 1 → 3** de la roadmap (cf. cahier des charges `v1.0`) :

| Phase | Contenu | État |
|------|---------|------|
| **1 — Caméra qui filme** | `AVCaptureSession`, preview plein écran, permissions caméra/micro, bouton REC (segment → fichier), switch avant/arrière, compteur cumulé | ✅ codé |
| **2 — Pile de segments & brouillons** | Vignettes, tap long → Refaire/Supprimer, persistance disque + index JSON (recharge à la réouverture) | ✅ codé |
| **3 — Assemblage & prévisualisation** | `AVMutableComposition` (cuts secs), format 9:16 / 16:9 via `AVMutableVideoComposition`, écran de lecture | ✅ codé |
| **4 — Export & partage** | `AVAssetExportSession` + progression, sauvegarde Photos (`PHPhotoLibrary`), share sheet (`UIActivityViewController`), **outro de marque** 3 s en gratuit, résolution 1080p/4K | ✅ codé |
| 5 — Monétisation (RevenueCat) | Paywall, limites freemium | ⬜ à venir |
| **Signature — Intro stylée & Hook** | Carton d'intro animé (`IntroGenerator`, 5 styles, titre + sous-titre éditables) inséré au début ; montage « hook » TikTok (extraits des 1ers clips, pause 0,1–0,2 s) ; retardateur caméra réglable (Off/3/5/10 s) | ✅ codé |
| **Signature — Montage pro** | Templates 1-tap (`VlogTemplate`), transitions flash/zoom/whip (rampes de transform), outro/CTA assorti à l'intro, beat-sync du hook (`BeatDetector`, autocorrélation Accelerate), sticker date/lieu (`StickerRenderer` + `AVVideoCompositionCoreAnimationTool`) | ✅ codé |
| **Vlog à plusieurs** | Sessions partagées CloudKit (`CollabSyncService`) : horodatage précis des clips, file d'upload hors-ligne (sync auto au retour du réseau), fusion chronologique multi-participants, invitations privées par lien iCloud | ✅ codé — ⚠️ activation manuelle, voir §Vlog à plusieurs |
| **Cartons de ville** | La ville de tournage est mémorisée sur chaque clip (`LocationService`, géocodage léger) ; à l'export, un carton animé de 3 s (`CityCardRenderer`) s'affiche à chaque changement de ville — activable dans la feuille d'export | ✅ codé |

> ⚠️ **Code non compilé ici.** Il a été scaffoldé hors Mac/Xcode (environnement Linux). Attends-toi à de petits ajustements de compilation au premier build sur ton Mac — c'est normal. Le point le plus susceptible de demander un réglage sur device réel est la **transform d'aspect-fill** dans `VideoAssembler.swift` (cadrage des segments), identifié comme délicat dans le cahier des charges (§11).

---

## Prérequis

- **macOS + Xcode 15+** (iOS 17 deployment target).
- **[XcodeGen](https://github.com/yonyz/XcodeGen)** pour générer le projet Xcode à partir de `project.yml` :
  ```bash
  brew install xcodegen
  ```

## Générer et lancer

```bash
cd VlogMe
xcodegen generate        # crée VlogMe.xcodeproj à partir de project.yml
open VlogMe.xcodeproj
```

Dans Xcode :
1. Sélectionne le target **VlogMe**, onglet **Signing & Capabilities** → coche *Automatically manage signing* et choisis ton équipe (compte développeur Apple).
2. Branche ton iPhone, sélectionne-le comme destination, **Run** (⌘R).

> Pas envie d'installer XcodeGen ? Crée un projet « App » vide dans Xcode (SwiftUI, iOS 17), supprime les fichiers générés, puis glisse le dossier `VlogMe/` dans le navigateur de projet et ajoute le target de tests. `project.yml` documente exactement les réglages attendus (bundle id `pro.vlogme.app`, iPhone uniquement, Info.plist custom).

## Lancer les tests

```bash
xcodebuild test -scheme VlogMe -destination 'platform=iOS Simulator,name=iPhone 15'
```

---

## Architecture (MVVM, cf. cahier des charges §6.3)

```
VlogMe/
├─ App/            VlogMeApp (composition root) · RootView (navigation Caméra → Preview)
├─ Models/         AspectRatio · CameraFacing · VideoSegment
├─ Services/
│   ├─ CameraService       possède AVCaptureSession, enregistre les segments, switch caméra
│   ├─ VlogStore           liste ordonnée des segments + persistance (brouillons, index JSON)
│   ├─ VideoAssembler      concat cuts secs + format 9:16/16:9 (AVMutableVideoComposition)
│   ├─ ThumbnailGenerator  miniatures des segments
│   └─ PermissionsManager  caméra + micro
├─ ViewModels/     CameraViewModel · PreviewViewModel
└─ Views/
    ├─ Camera/     CameraScreen · CameraPreviewLayerView · RecordButton · SegmentStackView · PermissionGateView
    ├─ Preview/    PreviewScreen
    └─ Components/ DurationLabel
```

### Décisions clés
- **Zéro perte de données (§7).** Chaque segment est écrit sur le disque *dès qu'il est coupé*, dans `Documents/segments/`. Un index JSON (`vlog_index.json`) garde l'ordre + le format. Au pire un crash perd le segment en cours, jamais les précédents.
- **Chemins relatifs.** On persiste un `fileName` relatif, pas une URL absolue : le conteneur de l'app iOS change d'UUID entre les lancements, un chemin absolu deviendrait invalide.
- **Preview sans ré-encodage.** La prévisualisation lit directement la `AVMutableComposition` ; l'export (Phase 4) réutilisera ces objets via `AVAssetExportSession`.
- **Concurrence.** La session caméra est pilotée sur une file série dédiée ; l'état UI est republié sur le main thread. Le mode langage est **Swift 5** pour un build sans friction au démarrage ; tu pourras passer en **Swift 6 strict** plus tard (quelques annotations `@Sendable` / `nonisolated` à prévoir sur `CameraService`).

### Export (Phase 4)
- `Exporter` lance un `AVAssetExportSession` (preset `HighestQuality` + `videoComposition` custom → la résolution de sortie = `renderSize`). Progression échantillonnée sur `session.progress`.
- `OutroGenerator` rend à la volée un clip noir « VlogMe » de 3 s (via `AVAssetWriter`), à la taille exacte de la composition, mis en cache. Concaténé en fin de vlog **uniquement en gratuit**.
- `PhotoSaver` écrit dans la pellicule (permission *add-only*) ; `ShareSheet` ouvre la share sheet iOS native.
- `Entitlements` (stub) pilote outro + résolution. La **4K réelle suppose une capture en 4K** (`sessionPreset = .hd4K3840x2160`) à activer côté `CameraService` en Phase 5 ; aujourd'hui le `renderSize` est mis à l'échelle mais la source caméra reste en `.high`.

## Vlog à plusieurs (sessions partagées CloudKit)

### Comment ça marche
- Chaque vlog partagé vit dans une **zone CloudKit dédiée** (`vlog-<uuid>`) de la base privée du créateur, partagée aux invités via un **`CKShare` de zone** (lien d'invitation privé envoyé par iMessage). Pas de serveur à gérer, pas de compte à créer : les participants sont identifiés par leur iCloud.
- Chaque clip mémorise **l'instant exact du début d'enregistrement** (`VideoSegment.capturedAt`). Au montage, les clips de tous les participants sont fusionnés **dans l'ordre chronologique réel** — filmer hors connexion ne pose aucun problème.
- Les clips filmés sans réseau partent dans une **file d'upload persistée** (`collab_sync_state.json`) qui se vide automatiquement dès que la connexion revient (`NWPathMonitor`). La réception utilise les changements incrémentaux de zone (`recordZoneChanges`) + un **push silencieux CloudKit** quand l'app tourne.
- Une session est **purement additive** (chacun n'écrit que ses clips) : aucun conflit possible. On ne peut pas supprimer le clip d'un autre participant.

### Activation (nécessite l'Apple Developer Program, 99 €/an)
> 📋 Guide pas-à-pas complet (inscription, Xcode, premier test à deux, pièges) : **[GUIDE-APPLE-DEVELOPER.md](GUIDE-APPLE-DEVELOPER.md)**

La feature est **désactivée par défaut** pour que le projet continue de compiler avec un compte Apple gratuit (l'entitlement iCloud ferait échouer la signature). Une fois inscrit au programme développeur :
1. Dans `project.yml`, décommente `CODE_SIGN_ENTITLEMENTS: VlogMe/Resources/VlogMe.entitlements` puis relance `xcodegen generate`.
2. Dans `VlogMe/Resources/Info.plist`, passe `VLOGME_COLLAB_ENABLED` à `true`.
3. Dans Xcode → Signing & Capabilities, vérifie que la capability **iCloud → CloudKit** apparaît avec le container `iCloud.com.hugonoppe.vlogme` (créé automatiquement à la première signature).
4. Premier lancement : filme un clip dans un vlog partagé pour que CloudKit crée le schéma (`CollabSegment`) en environnement Development. Avant de publier, déploie le schéma en Production depuis le [CloudKit Dashboard](https://icloud.developer.apple.com).

Tant que `VLOGME_COLLAB_ENABLED` est à `false`, le bouton « Vlog à plusieurs » affiche un écran « Bientôt disponible » et **aucun appel CloudKit n'est fait**.

## Reste à faire (prochaines phases)
- **Phase 5 :** RevenueCat + StoreKit 2, paywall, limites freemium (durée 3 min, 1080p, outro), restauration d'achat, capture 4K en Pro.
- **Polish (Phase 6) :** pré-init session pour démarrage < 1 s, cas limites (stockage plein, appel entrant), App Icon + LaunchScreen, fiche App Store.
