# Podcast & ADR Toolbox pour REAPER

Boîte à outils gratuite pour REAPER (Mac et Windows). Tout se passe sur votre ordinateur : l'audio ne part nulle part.

- **Dérushage** : transcription mot par mot avec Whisper, détection du clicker, montage par le texte.
- **Édition** : ripple sur les bords des items, aimantation (bords des items, pas la grille).
- **Vocal level & de-esser** : niveau régulier, sifflantes, plosives, voix trop proche, équilibre tonal.
- **Export** : contrôle du niveau (LUFS, true peak) avec correction automatique.
- **Doublage (ADR)** : répliques depuis la VO (Whisper + traduction), un SRT ou à la main ; bande rythmo sur tablette ; enregistrement réplique par réplique avec bips.

## Installation
La procédure détaillée, pas à pas, est dans [INSTALLATION.md](INSTALLATION.md). En bref :
1. Installez ReaPack (https://reapack.com) et redémarrez REAPER.
2. *Extensions › ReaPack › Import repositories…*, collez :
   ```
   https://github.com/nicolasdebois-pixel/PodSuite/raw/main/index.xml
   ```
3. Installez le paquet **Podcast & ADR Toolbox**.
4. Lancez l'action **Podcast & ADR Toolbox**, puis *Accueil › Installer / réparer* pour la transcription.

## Utilisation
Une seule action à retenir : **Podcast & ADR Toolbox**. Elle ouvre une fenêtre avec une page par étape
(Dérushage, Édition, Voix, Export, puis Répliques et Enregistrement pour le doublage) d'où l'on lance tous les outils. Mettez-la dans une barre d'outils.


1. Enregistrez le projet REAPER.
2. Lancez **Toolbox - Serveur de derushage** et laissez-le tourner.
3. Une fois : placez le curseur juste avant un clic dans vos rushes, sélectionnez la piste, puis **Toolbox - Calibrer le clicker**.
4. Sélectionnez les items des intervenants, un par piste, puis **Toolbox - Transcrire**.
5. Ouvrez la page de dérushage, à l'adresse indiquée à la fin de la transcription.

### Le code du clicker
- **1 clic** : la phrase précédente est ratée, PodSuite repère la reprise et propose la coupe.
- **2 clics** : passage à réécouter.
- **3 clics** : tout le paragraphe depuis le dernier long silence est à jeter.

### Le montage
Dès le premier passage barré, PodSuite crée une piste **« ✂ Intervenant »** par intervenant et y reconstruit
le montage depuis les rushes à chaque modification. Les rushes ne sont jamais modifiés, seulement rendus muets.
Le sélecteur **Montage / Rushes** de la page choisit ce que REAPER fait entendre.

## Contrôle du niveau avant l'export
Action **Toolbox - Controle du niveau** (REAPER 6.71 ou plus récent).
1. Choisissez la norme : **Podcast (Apple, autres)** = −16 LUFS intégrés (± 1 LU), true peak max −1 dBTP ;
   **Podcast (Spotify)** = −14 LUFS intégrés (± 1 LU), true peak max −1 dBTP.
2. Cliquez sur **Mesurer** : REAPER lit tout le mix du master (plus vite que le temps réel) sans créer de fichier.
3. L'outil affiche la loudness intégrée, le true peak et l'écart de volume (LRA), dit si c'est conforme et propose des pistes.
4. **Corriger automatiquement** place « Toolbox limiter » (limiteur true peak) en fin de chaîne du master,
   règle son gain et son plafond, puis remesure jusqu'à être dans la norme. **Retirer le limiteur** annule tout.

Conseil : si le limiteur doit réduire les crêtes de plus de 6 dB, régularisez d'abord la voix
(Vocal level & de-esser) : le résultat sonnera plus naturel.

## Pour le mainteneur : publier une version
- Projets d'exercice de l'Accueil : mettez l'adresse d'une archive .zip (projet REAPER + médias) dans `Scripts/Toolbox_demo.json`.
- Whisper pour Mac : onglet *Actions* › « Whisper pour Mac » › *Run workflow* (recompile et publie la version « whisper-macos »).
- Avant de pousser : `python3 tools/release.py` (recopie la version et complète CHANGELOG.md).

1. Modifiez les fichiers dans `Scripts/`, `Effects/` ou `www/`.
2. Dans `toolbox.json`, augmentez `version` et décrivez les changements dans `changelog`.
3. Envoyez sur la branche `main`. GitHub met à jour `index.xml` tout seul (onglet *Actions*),
   et les utilisateurs reçoivent la mise à jour par ReaPack.

Licence : MIT. Whisper (whisper.cpp) est distribué séparément sous licence MIT.
