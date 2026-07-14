# Mettre vos vlogs en commun — sans compte Apple payant

Le « vlog à plusieurs » temps réel (CloudKit) demande le **compte Apple Developer
payant** *actif*. En attendant, voici comment faire **un seul vlog à deux** sans
rien payer et **sans Mac pendant le voyage** — il suffit que l'app soit installée
sur les deux téléphones.

## Idée générale

Chacun filme ses clips de son côté dans VlogMe (ou avec l'appareil photo).
À la fin, **un seul téléphone** récupère les clips de l'autre et les **importe**
dans un même vlog, puis l'exporte. Le montage signature VlogMe (intro, musique,
transitions, cartons de ville…) s'applique alors à l'ensemble.

## Avant de partir (avec le Mac, une fois par téléphone)

1. Installe l'app via Xcode sur **les deux iPhone** (branche `⌘R`).
   > Cette build est signée avec le compte Apple **gratuit** : elle expire au
   > bout de **7 jours**. Un voyage plus long ? Réinstalle au retour, ou attends
   > le compte payant (validité 1 an).
2. Sur **chaque** téléphone : ouvre la caméra → menu **…** → active
   **« Enregistrer les clips dans la pellicule »**. Ainsi chaque clip filmé est
   aussi sauvegardé dans Photos, prêt à être partagé.

## Pendant le voyage

- Chacun filme normalement dans son propre vlog. Aucune connexion nécessaire.

## À la fin — rassembler dans un seul vlog

1. La personne A **AirDrop** ses clips (depuis Photos) vers le téléphone de B.
   Ils atterrissent dans la pellicule de B.
2. Sur le téléphone de B : ouvre (ou crée) le vlog qui servira de montage final.
3. Caméra → menu **…** → **« Importer des clips »** → sélectionne tous les clips
   (les tiens + ceux reçus d'A).
4. Appuie sur la pile de vignettes → **réorganise** les clips dans l'ordre voulu
   (l'import les ajoute à la suite ; l'ordre chronologique n'est pas automatique).
5. **Terminer** → règle intro / musique / transitions → **Exporter**.

En DEBUG (build Xcode), l'export est débloqué gratuitement : pas de paywall,
pas de filigrane, jusqu'en 4K.

## Astuce

Pas besoin que les clips viennent de VlogMe : **« Importer des clips »** accepte
n'importe quelle vidéo de la pellicule (appareil photo, reçue par message, etc.).
