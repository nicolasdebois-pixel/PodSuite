# Installer Podcast & ADR Toolbox dans REAPER

Podcast & ADR Toolbox est une boîte à outils gratuite pour REAPER, sur Mac et sur Windows. Elle réunit :

- **Dérushage** : transcription de l'audio avec Whisper et montage d'un podcast à partir du texte ;
- **Édition** : le ripple sur les bords des items et l'aimantation ;
- **Vocal level & de-esser** : une voix plus régulière et plus propre, en un clic ;
- **Export** : la vérification du niveau (LUFS, true peak), puis l'export en MP3 320 kbps avec les tags ;
- **Doublage (ADR)** : les répliques, la bande rythmo sur l'écran de la cabine ou une tablette, l'enregistrement réplique par réplique.

L'installation prend une quinzaine de minutes, dont la plupart passées à attendre un téléchargement. Elle se fait **une seule fois** par ordinateur : ensuite, les mises à jour arrivent toutes seules.

> **Ce qu'il faut avant de commencer**
> - REAPER 7 (ou 6.71 au minimum) : <https://www.reaper.fm>
> - Une connexion internet, pour l'installation seulement. Ensuite, tout fonctionne hors ligne et l'audio ne quitte jamais l'ordinateur (seule la traduction automatique des répliques en français, italien ou espagnol passe par internet : le texte, jamais l'audio).
> - Environ 1 Go d'espace libre, surtout pour le modèle de transcription.

Les menus de REAPER sont indiqués en anglais, comme dans l'installation de base.

---

## Étape 1 — Installer ReaPack

ReaPack est le gestionnaire d'extensions de REAPER, une sorte de « magasin d'applications » gratuit.

1. Allez sur <https://reapack.com> et téléchargez le fichier qui correspond à votre système :
   - **Mac avec puce Apple (M1, M2, M3, M4…)** : la version *ARM64* ;
   - **Mac Intel** : la version *x86_64* ;
   - **Windows** : la version *x64*.
2. Dans REAPER : **Options › Show REAPER resource path in explorer/finder**. Un dossier s'ouvre.
3. Ouvrez le sous-dossier **UserPlugins** et glissez-y le fichier téléchargé.
4. **Quittez REAPER, puis relancez-le.** Un menu **Extensions › ReaPack** est apparu.

> Si le menu **Extensions › ReaPack** existe déjà, ReaPack est installé : passez directement à l'étape 2.

## Étape 2 — Ajouter la boîte à outils

1. Dans REAPER : **Extensions › ReaPack › Import repositories…**
2. Collez cette adresse, puis cliquez sur **OK** :

   ```
   https://github.com/nicolasdebois-pixel/PodSuite/raw/main/index.xml
   ```

## Étape 3 — Installer le paquet

1. **Extensions › ReaPack › Browse packages…**
2. Dans le champ de recherche, tapez **Toolbox**.
3. Clic droit sur **Podcast & ADR Toolbox** › **Install**, puis **Apply** (ou **OK**).
4. Fermez la fenêtre quand ReaPack a terminé.

## Étape 4 — Ouvrir la boîte à outils

1. **Actions › Show action list…**
2. Tapez **Toolbox** dans le champ de recherche.
3. Sélectionnez **Script: Podcast & ADR Toolbox.lua**, puis cliquez sur **Run**.

La fenêtre principale s'ouvre, avec une page par étape : **Accueil**, **Dérushage**, **Édition**, **Voix**, **Export**, puis, pour le doublage, **Répliques** et **Enregistrement**.

> **C'est la seule action à retenir.** Pour l'avoir toujours sous la main :
> - **un bouton dans la barre d'outils** : clic droit sur la barre d'outils › **Customize toolbar…** › **Add…**, cherchez *Podcast & ADR Toolbox*, puis **OK** ;
> - **ou un raccourci clavier** : dans l'*Action list*, sélectionnez l'action, puis **Add…** sous *Shortcuts for selected action*.
>
> Le bouton **?** en haut à droite de chaque page affiche l'aide de la page.

## Étape 5 — Installer la transcription (une seule fois)

Cette étape est nécessaire pour **transcrire** : dérushage d'un podcast, ou répliques créées depuis la VO pour le doublage. Elle active aussi l'**interface web** qui affiche la page de dérushage et la bande rythmo. Les pages **Édition**, **Voix** et **Export** fonctionnent déjà sans elle.

1. Dans la page **Accueil**, cliquez sur **Installer / réparer**.
2. Suivez l'assistant. Il :
   - installe **Whisper**, le programme de transcription (gratuit, il tourne sur votre ordinateur) ;
   - vous fait choisir un **modèle de transcription** :
     - **Précis** pour un Mac à puce Apple ou un PC récent ;
     - **Équilibré** pour un PC moyen ;
     - **Léger** pour un vieil ordinateur ;
   - vous guide pour activer l'**interface web de REAPER**, qui affiche la page de dérushage dans votre navigateur : dans la fenêtre des préférences qui s'ouvre, rubrique **Control/OSC/web** › **Add** › **Web browser interface**, avec le port proposé par l'assistant, puis **OK** ;
   - termine par un test de transcription.

**Sur Mac**, l'assistant télécharge une version de Whisper prête à l'emploi (puces Apple et Intel). Si ce téléchargement échoue, il passe par **Homebrew** : s'il n'est pas installé, l'assistant affiche une commande à copier dans le **Terminal** (le mot de passe du Mac est demandé), puis relancez **Installer / réparer**.

**Sur Windows**, si l'assistant signale un composant Microsoft manquant, installez *Visual C++ Redistributable (x64)* avec le lien qu'il donne, puis relancez **Installer / réparer**.

Quand c'est terminé, la page **Accueil** affiche deux pastilles vertes.

---

## Doublage : afficher la bande rythmo en cabine

La bande rythmo s'affiche dans un navigateur web, avec **l'image du film au-dessus**, calée sur la lecture de REAPER : le comédien voit l'image et la bande sur le même écran, pendant que l'ingé son garde la fenêtre vidéo de REAPER sur le sien. Le son reste dans le casque (la page est muette).

**Sur un écran de la cabine branché à l'ordinateur** : dans la page **Enregistrement**, cliquez sur **Ouvrir sur cet ordinateur**, glissez le navigateur sur l'écran de la cabine, puis touche **F** : plein écran.

**Sur une tablette (ou un autre ordinateur)** :

1. La tablette et l'ordinateur doivent être sur **le même réseau Wi-Fi**.
2. Dans la page **Enregistrement**, notez l'adresse affichée sous *Bande rythmo*, du type `http://192.168.1.42:8080/doublage.html`.
3. Tapez-la dans le navigateur de la tablette (Safari, Chrome…). Touchez **⛶** pour le plein écran.
4. Si rien ne s'affiche : la première fois, l'ordinateur peut demander s'il faut **autoriser REAPER à accepter les connexions entrantes** : répondez **Autoriser**. Sur un réseau d'école qui isole les appareils, utilisez un petit routeur Wi-Fi dédié, ou le partage de connexion de l'ordinateur.

Les boutons en haut à droite de la bande règlent la vitesse de défilement (**− / +**) et le calage sur le son (**◂ / ▸ 10 ms**, appliqué à l'image et à la bande) ; **Vidéo** masque ou affiche l'image. Ces réglages sont mémorisés sur la tablette.

**La vidéo** : à l'ouverture de la bande, la vidéo du projet est copiée pour le serveur web de REAPER, puis chargée par la tablette (comptez quelques secondes à une minute selon la taille et le Wi-Fi). Elle doit être dans un format lisible par un navigateur : **MP4 (H.264)** de préférence. Si la page indique « format vidéo non lisible », exportez la vidéo en MP4 H.264, en résolution réduite (720p suffit), puis remplacez-la dans REAPER.

**Lire la bande** : le bandeau sous l'image affiche toujours la réplique à dire, en entier, avec le temps restant, puis « À VOUS ». En dessous, le texte défile vers la barre verticale ; on dit chaque syllabe quand elle passe sous la barre. La bande suit la fréquence de l'écran (indiquée en haut, par exemple « 60 i/s »). Les deux petits traits avant la réplique à enregistrer correspondent au double bip : « bip, bip, top », on parle au troisième temps. Les signes **RESP** (respiration), **BOUCHE** (bouche fermée), **RIRE** et **SOUPIR** viennent des codes `(r)`, `(b)`, `(rire)` et `(s)` tapés dans le texte des répliques.

---

## Mettre à jour

**Extensions › ReaPack › Synchronize packages.** Les nouvelles versions s'installent toutes seules.

## Vous aviez installé une ancienne version ?

Si vous aviez ajouté séparément les dépôts **PodSuite** ou **Vocal level & de-esser** avant qu'ils ne soient réunis :

1. **Extensions › ReaPack › Manage repositories…**
2. Clic droit sur chacun de ces dépôts › **Uninstall**, puis **OK**.
3. Refaites les étapes 2 à 4 ci-dessus.

Vos réglages et la transcription déjà installée (Whisper, modèle) sont conservés.

## Pour le service informatique (salle de cours)

Pour éviter que chaque étudiant télécharge Whisper et le modèle (environ 500 Mo) :

1. Créez un **dossier commun** :
   - Mac : `/Users/Shared/Podcast ADR Toolbox`
   - Windows : `C:\ProgramData\Podcast ADR Toolbox`
2. Déposez-y **Whisper** (Mac : le fichier `whisper-cli` ; Windows : le dossier dézippé de whisper.cpp contenant `whisper-cli.exe`) et **un modèle** (par exemple `ggml-large-v3-turbo-q5_0.bin`, téléchargeable sur huggingface.co/ggerganov/whisper.cpp). Le dossier doit être lisible par tous les comptes.
3. À l'étape 5, l'assistant trouve ces fichiers et ne télécharge rien.

À savoir pour les postes partagés :
- Les réglages de la boîte à outils sont enregistrés **par compte utilisateur** (dans le dossier de REAPER de chaque compte).
- La traduction automatique gratuite est limitée **par adresse internet** : toute la salle partage la même limite. Chaque étudiant doit indiquer son e-mail (ou sa clé DeepL gratuite) dans **Répliques › ⚙ Réglages de traduction**.
- Le pare-feu doit autoriser REAPER à recevoir des connexions sur le réseau local si la bande rythmo est affichée sur une tablette.

## En cas de problème

| Problème | Solution |
|---|---|
| Pas de menu **Extensions › ReaPack** | Le fichier ReaPack n'est pas dans **UserPlugins**, ou ce n'est pas la bonne version (ARM64, x86_64 ou x64). Vérifiez, puis redémarrez REAPER. |
| **Toolbox** introuvable dans *Browse packages* | **Extensions › ReaPack › Synchronize packages**, puis cherchez à nouveau. Vérifiez l'adresse collée à l'étape 2. |
| L'action **Podcast & ADR Toolbox** n'apparaît pas | Le paquet n'est pas installé : refaites l'étape 3. |
| Pastille rouge pour la transcription | Page **Accueil** › **Installer / réparer** : l'assistant reprend là où il s'était arrêté. |
| La page de dérushage ne s'ouvre pas | L'interface web de REAPER n'est pas activée : relancez **Installer / réparer** (étape 5). |
| Le contrôle du niveau dit que REAPER est trop ancien | Installez REAPER 7. |
| La bande rythmo ne s'ouvre pas sur la tablette | Même Wi-Fi ? Adresse exacte (avec le port) ? Autorisez REAPER dans le pare-feu de l'ordinateur. |
| « Transcrire la VO » est grisé | La transcription n'est pas installée : étape 5. |
