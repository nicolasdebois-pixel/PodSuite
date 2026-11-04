# Installer Podcast & ADR Toolbox dans REAPER

Podcast & ADR Toolbox est une boîte à outils gratuite pour REAPER, sur Mac et sur Windows. Elle réunit :

- **PodSuite** : transcription de l'audio avec Whisper et montage d'un podcast à partir du texte ;
- **Vocal level & de-esser** : une voix plus régulière et plus propre, en un clic ;
- **Montage** : le ripple sur les bords des items ;
- **Export** : la vérification du niveau (LUFS, true peak) avant d'exporter.

L'installation prend une quinzaine de minutes, dont la plupart passées à attendre un téléchargement. Elle se fait **une seule fois** par ordinateur : ensuite, les mises à jour arrivent toutes seules.

> **Ce qu'il faut avant de commencer**
> - REAPER 7 (ou 6.71 au minimum) : <https://www.reaper.fm>
> - Une connexion internet, pour l'installation seulement. Ensuite, tout fonctionne hors ligne et l'audio ne quitte jamais l'ordinateur.
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

La fenêtre principale s'ouvre, avec une page par étape : **Accueil**, **Dérushage**, **Voix**, **Montage**, **Export**.

> **C'est la seule action à retenir.** Pour l'avoir toujours sous la main :
> - **un bouton dans la barre d'outils** : clic droit sur la barre d'outils › **Customize toolbar…** › **Add…**, cherchez *Podcast & ADR Toolbox*, puis **OK** ;
> - **ou un raccourci clavier** : dans l'*Action list*, sélectionnez l'action, puis **Add…** sous *Shortcuts for selected action*.
>
> Le bouton **Ancrer**, en bas à gauche de la fenêtre, la range dans l'interface de REAPER.

## Étape 5 — Installer la transcription (une seule fois)

Cette étape n'est nécessaire que pour **transcrire et dérusher** (page *Dérushage*). Les pages **Voix**, **Montage** et **Export** fonctionnent déjà.

1. Dans la page **Accueil**, cliquez sur **Installer / réparer**.
2. Suivez l'assistant. Il :
   - installe **Whisper**, le programme de transcription (gratuit, il tourne sur votre ordinateur) ;
   - vous fait choisir un **modèle de transcription** :
     - **Précis** pour un Mac à puce Apple ou un PC récent ;
     - **Équilibré** pour un PC moyen ;
     - **Léger** pour un vieil ordinateur ;
   - vous guide pour activer l'**interface web de REAPER**, qui affiche la page de dérushage dans votre navigateur : dans la fenêtre des préférences qui s'ouvre, rubrique **Control/OSC/web** › **Add** › **Web browser interface**, avec le port proposé par l'assistant, puis **OK** ;
   - termine par un test de transcription.

**Sur Mac**, Whisper s'installe avec **Homebrew**. S'il n'est pas encore installé, l'assistant affiche une commande à copier dans le **Terminal** : le mot de passe du Mac est demandé. Relancez ensuite **Installer / réparer**.

**Sur Windows**, si l'assistant signale un composant Microsoft manquant, installez *Visual C++ Redistributable (x64)* avec le lien qu'il donne, puis relancez **Installer / réparer**.

Quand c'est terminé, la page **Accueil** affiche deux pastilles vertes.

---

## Mettre à jour

**Extensions › ReaPack › Synchronize packages.** Les nouvelles versions s'installent toutes seules.

## Vous aviez installé une ancienne version ?

Si vous aviez ajouté séparément les dépôts **PodSuite** ou **Vocal level & de-esser** avant qu'ils ne soient réunis :

1. **Extensions › ReaPack › Manage repositories…**
2. Clic droit sur chacun de ces dépôts › **Uninstall**, puis **OK**.
3. Refaites les étapes 2 à 4 ci-dessus.

Vos réglages et la transcription déjà installée (Whisper, modèle) sont conservés.

## En cas de problème

| Problème | Solution |
|---|---|
| Pas de menu **Extensions › ReaPack** | Le fichier ReaPack n'est pas dans **UserPlugins**, ou ce n'est pas la bonne version (ARM64, x86_64 ou x64). Vérifiez, puis redémarrez REAPER. |
| **Toolbox** introuvable dans *Browse packages* | **Extensions › ReaPack › Synchronize packages**, puis cherchez à nouveau. Vérifiez l'adresse collée à l'étape 2. |
| L'action **Podcast & ADR Toolbox** n'apparaît pas | Le paquet n'est pas installé : refaites l'étape 3. |
| Pastille rouge pour la transcription | Page **Accueil** › **Installer / réparer** : l'assistant reprend là où il s'était arrêté. |
| La page de dérushage ne s'ouvre pas | L'interface web de REAPER n'est pas activée : relancez **Installer / réparer** (étape 5). |
| Le contrôle du niveau dit que REAPER est trop ancien | Installez REAPER 7. |
