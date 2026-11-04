# PodSuite pour REAPER

Transcription et dérushage de podcast, directement dans REAPER. Gratuit, et tout se passe sur votre ordinateur : l'audio ne part nulle part.

- **Transcription mot par mot** avec Whisper, qui reconnaît qui parle (une piste par intervenant).
- **Détection du clicker** : un clic pendant l'enregistrement signale une prise ratée, et PodSuite propose la coupe.
- **Montage par le texte** : barrez des mots dans la page de dérushage, REAPER coupe le son au même endroit, dans le silence le plus proche.

Fonctionne sur Mac et Windows.

## Installation

### 1. Installer ReaPack (une seule fois)
ReaPack est le gestionnaire d'extensions de REAPER : https://reapack.com
Téléchargez le fichier pour votre système, placez-le dans le dossier `UserPlugins` de REAPER
(*Options › Show REAPER resource path*), puis redémarrez REAPER.

### 2. Ajouter le dépôt PodSuite
*Extensions › ReaPack › Import repositories…*, collez cette adresse, puis OK :

```
https://github.com/nicolasdebois-pixel/PodSuite/raw/main/index.xml
```

### 3. Installer PodSuite
*Extensions › ReaPack › Browse packages…*, cherchez **PodSuite**, clic droit › *Install*, puis *Apply*.

### 4. Lancer l'assistant
*Actions › Show action list*, cherchez **PodSuite - Installer**, puis *Run*.
L'assistant installe Whisper, télécharge le modèle de transcription de votre choix, règle PodSuite
et vous guide pour activer l'interface web de REAPER. Il se termine par un test.

Sur Mac, l'assistant utilise Homebrew. S'il n'est pas installé, l'assistant donne la commande à coller dans le Terminal.

Les mises à jour arrivent ensuite toutes seules par ReaPack (*Extensions › ReaPack › Synchronize packages*).

## Utilisation
Une seule action à retenir : **PodSuite**. Elle ouvre une fenêtre avec une page par étape
(Dérushage, Voix, Montage, Export) d'où l'on lance tous les outils. Mettez-la dans une barre d'outils.


1. Enregistrez le projet REAPER.
2. Lancez **PodSuite - Serveur** et laissez-le tourner.
3. Une fois : placez le curseur juste avant un clic dans vos rushes, sélectionnez la piste, puis **PodSuite - Calibrer le clicker**.
4. Sélectionnez les items des intervenants, un par piste, puis **PodSuite - Transcrire**.
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
Action **PodSuite - Controle du niveau** (REAPER 6.71 ou plus récent).
1. Choisissez la norme : **Podcast (Apple, autres)** = −16 LUFS intégrés (± 1 LU), true peak max −1 dBTP ;
   **Podcast (Spotify)** = −14 LUFS intégrés (± 1 LU), true peak max −1 dBTP.
2. Cliquez sur **Mesurer** : REAPER lit tout le mix du master (plus vite que le temps réel) sans créer de fichier.
3. L'outil affiche la loudness intégrée, le true peak et l'écart de volume (LRA), dit si c'est conforme et propose des pistes.
4. **Corriger automatiquement** place « PodSuite limiter » (limiteur true peak) en fin de chaîne du master,
   règle son gain et son plafond, puis remesure jusqu'à être dans la norme. **Retirer le limiteur** annule tout.

Conseil : si le limiteur doit réduire les crêtes de plus de 6 dB, régularisez d'abord la voix
(Vocal level & de-esser) : le résultat sonnera plus naturel.

## Pour le mainteneur : publier une version
1. Modifiez les fichiers dans `Scripts/` ou `www/`.
2. Dans `podsuite.json`, augmentez `version` et décrivez les changements dans `changelog`.
3. Envoyez sur la branche `main`. GitHub met à jour `index.xml` tout seul (onglet *Actions*),
   et les utilisateurs reçoivent la mise à jour par ReaPack.

Licence : MIT. Whisper (whisper.cpp) est distribué séparément sous licence MIT.
