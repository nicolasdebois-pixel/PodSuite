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

1. Enregistrez le projet REAPER.
2. Lancez **PodSuite - Serveur** et laissez-le tourner.
3. Une fois : **PodSuite - Calibrer le clicker** (sélection temporelle autour d'un clic).
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

## Pour le mainteneur : publier une version
1. Modifiez les fichiers dans `Scripts/` ou `www/`.
2. Dans `podsuite.json`, augmentez `version` et décrivez les changements dans `changelog`.
3. Envoyez sur la branche `main`. GitHub met à jour `index.xml` tout seul (onglet *Actions*),
   et les utilisateurs reçoivent la mise à jour par ReaPack.

Licence : MIT. Whisper (whisper.cpp) est distribué séparément sous licence MIT.
