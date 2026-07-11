# Guide — Activer le vlog à plusieurs sur ton iPhone (Apple Developer)

Suis ces étapes **dans l'ordre**. Compte ~30 min de manipulation une fois l'inscription validée.

---

## Étape 0 — L'inscription

1. Va sur <https://developer.apple.com/programs/> → **Enroll** → choisis **Individual**,
   avec le **même identifiant Apple que celui utilisé dans Xcode**. Paiement : 99 €/an.
2. Attends l'email « **Welcome to the Apple Developer Program** ».
   C'est souvent validé en quelques minutes/heures, parfois jusqu'à 48 h.
   ⚠️ **Ne fais pas les étapes suivantes avant d'avoir reçu cet email** — la build
   échouerait à la signature.

## Étape 1 — Brancher le compte dans Xcode

3. Xcode → **Settings → Accounts** → vérifie ton identifiant Apple.
   Ton équipe doit maintenant s'appeler « Hugo Noppe » **sans** la mention
   *(Personal Team)* : c'est le signe que le programme payant est actif.

## Étape 2 — Activer la feature dans le projet

4. Récupère la branche à jour :
   ```bash
   git pull origin claude/pro-features-export-2r3v30
   ```
5. Dans `project.yml`, **décommente** la ligne :
   ```yaml
   CODE_SIGN_ENTITLEMENTS: VlogMe/Resources/VlogMe.entitlements
   ```
6. Dans `VlogMe/Resources/Info.plist`, passe `VLOGME_COLLAB_ENABLED`
   de `<false/>` à `<true/>`.
7. Regénère et ouvre le projet :
   ```bash
   xcodegen generate && open VlogMe.xcodeproj
   ```

## Étape 3 — Vérifier la signature et les capabilities

8. Target **VlogMe** → onglet **Signing & Capabilities** :
   - *Automatically manage signing* coché, ton équipe (la payante) sélectionnée ;
   - la capability **iCloud** doit apparaître avec **CloudKit** coché et le container
     `iCloud.com.hugonoppe.vlogme` ;
   - **Push Notifications** et **Background Modes → Remote notifications**
     doivent apparaître aussi.

   À la première signature (connexion Internet nécessaire), Xcode enregistre
   automatiquement l'app ID, crée le container CloudKit et le profil.
   Si le container apparaît en rouge : clique sur ↻ (refresh), ou ajoute-le via
   **+ Capability → iCloud**.

## Étape 4 — Sur l'iPhone

9. Réglages → ton nom : vérifie que tu es **connecté à iCloud** (iCloud Drive activé).
   Le vlog à plusieurs identifie les participants par leur compte iCloud — rien
   d'autre à créer.
10. Branche l'iPhone, **⌘R**. La build DEBUG a toujours le Pro débloqué,
    et le bouton 👥 de la caméra est maintenant actif.

## Étape 5 — Premier test

11. Ouvre l'app → bouton **👥** → « Inviter des amis » → filme un clip.
    Ce premier envoi crée automatiquement le schéma `CollabSegment` côté CloudKit
    (environnement *Development*). Vérifiable sur
    <https://icloud.developer.apple.com> → ton container → **Schema**.

---

## ⚠️ Tester à deux : le point important

Le lien d'invitation ne fonctionne que si l'invité **a VlogMe installé sur son iPhone**.
Comme l'app n'est pas sur l'App Store, deux options :

- **Un 2ᵉ appareil sous la main** (ton iPad/vieil iPhone, ou l'iPhone d'un ami présent) :
  branche-le au Mac et installe la même build via Xcode. Test le plus simple.
- **TestFlight** (test à distance) : upload sur App Store Connect, puis invitation
  TestFlight. Dans ce cas, **avant** d'envoyer la build :
  CloudKit Dashboard → ton container → **Deploy Schema Changes to Production**
  (TestFlight utilise l'environnement *Production*, pas *Development*).
  Note : en TestFlight (build Release) le paywall redevient actif — crée les
  abonnements `com.hugonoppe.vlogme.pro.monthly` / `.annual` dans App Store Connect
  à ce moment-là.

## Pièges classiques

| Symptôme | Cause |
|---|---|
| Erreur de signature « iCloud is not available » | Inscription pas encore validée, ou mauvaise équipe sélectionnée |
| Le bouton 👥 dit « Bientôt disponible » | `VLOGME_COLLAB_ENABLED` encore à `false`, ou `xcodegen` pas relancé |
| « iCloud requis » dans la feuille de partage | iPhone non connecté à iCloud dans Réglages |
| L'invité tape le lien et rien ne se passe | VlogMe pas installé sur son iPhone |
| Ça marche en Xcode mais pas en TestFlight | Schéma pas déployé en Production dans le CloudKit Dashboard |
