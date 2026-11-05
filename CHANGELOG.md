# Nouveautés de Podcast & ADR Toolbox

## 0.10.8 — 05/11/2026
- Mac : Whisper démarre de nouveau depuis REAPER (la commande est passée par un petit script : REAPER cassait les guillemets introduits en 0.10.3, d'où un test d'installation ou une transcription bloqués)
- Mac : le journal de Whisper indique son code de sortie

## 0.10.7 — 05/11/2026
- Mac Intel : Whisper ne prépare plus la carte graphique au démarrage (GGML_METAL_DEVICES=0) : il restait bloqué avant même de charger le modèle
- Installation : le journal du test de Whisper est complet (utile en cas de problème)

## 0.10.6 — 05/11/2026
- Transcription : plus d'erreur « bad argument #1 to 'sub' » quand un effet sur l'item renvoie des valeurs invalides (NaN, infini) ; ces passages sont traités comme du silence

## 0.10.5 — 05/11/2026
- Mac Intel : Whisper calcule sur le processeur (la carte graphique le bloquait : test ou transcription figés)
- Le test de l'installation s'arrête après 2 minutes avec un message au lieu de tourner sans fin ; Whisper est arrêté quand on annule ou quand il ne répond plus

## 0.10.4 — 05/11/2026
- Installation : le modèle de transcription se choisit avec trois boutons dans la fenêtre (le menu déroulant pouvait se refermer tout seul sur Mac : « aucun modèle choisi »)

## 0.10.3 — 05/11/2026
- Windows : Whisper s'installe de nouveau (la dernière version de whisper.cpp ne publie plus de version Windows ; la boîte à outils en garde une copie)
- Windows : la transcription fonctionne avec des accents dans le nom d'utilisateur ou du dossier du projet
- Transcription : la fenêtre de progression indique ce que fait Whisper (chargement du modèle, écoute, calcul en cours) et, en cas d'échec, où trouver le journal

## 0.10.2 — 04/11/2026
- Correction : « Exporter une piste par personnage » règle bien la source d'export sur « Stems (selected tracks) » (un fichier par personnage) au lieu du master

## 0.10.1 — 04/11/2026
- Enregistrement : l'option « Boucle » s'appelle maintenant « Répéter avant d'enregistrer » (expliquée dans l'aide « ? »)

## 0.10.0 — 04/11/2026
- Export : quand on fait du doublage, les normes proposées sont celles de l'audiovisuel — télévision (EBU R128, −23 LUFS ± 0,5, true peak −1), Netflix (−27 LUFS dialogues ± 2, true peak −2), web / YouTube (−14 LUFS) ; « les deux » affiche toutes les normes
- Export pour le doublage réglé en 48 kHz ; conseil de livraison des voix seules (une piste par personnage)

## 0.9.9 — 04/11/2026
- Le mode Simple est supprimé : tous les réglages sont toujours affichés

## 0.9.8 — 04/11/2026
- Dérushage : export de la transcription (.txt), des sous-titres (.srt) et des chapitres YouTube / Spotify, d'après le montage
- Doublage : prises comparables (◀ ▶) et « ★ Garder cette prise » ; liste « séance prête ? » ; export d'une piste par personnage (mode Expert)
- Accueil : « Je fais du podcast / du doublage / les deux » n'affiche que les pages utiles ; projets d'exercice téléchargeables (si l'enseignant en publie)
- Mac : Whisper s'installe sans Homebrew (version prête à l'emploi) ; salle de cours : Whisper et le modèle peuvent être déposés une fois dans un dossier commun
- Les nouvelles transcriptions sont rangées dans un dossier « Transcription » à côté du projet

## 0.9.7 — 04/11/2026
- Fenêtre unique : Vocal level & de-esser est intégré à la page Voix, le contrôle du niveau à la page Export
- Voix : sous chaque traitement, « ce qui a été fait » en une phrase (ex. « 11 sifflantes adoucies… »), pour comprendre et pas seulement appliquer
- Export : liste « Prêt à exporter ? » (projet enregistré, pas de solo, voix traitée, niveau conforme) et bouton « Exporter pour Spotify / les plateformes de podcast »
- Pages longues : défilement à la molette
- La fenêtre complète de Vocal level reste accessible en mode Expert (« Réglages avancés… »)

## 0.9.6 — 04/11/2026
- Mode Simple / Expert (en bas à gauche) : en Simple, seul l'essentiel est affiché, y compris dans Vocal level et le Contrôle du niveau
- Bouton « ? » sur chaque page : l'aide de la page
- Les résultats des outils (import, transcription, calibrage…) s'affichent dans la fenêtre principale au lieu de boîtes de dialogue
- Textes un peu plus grands dans la fenêtre principale

## 0.9.5 — 04/11/2026
- Fiabilité : après le doublage, REAPER retrouve son mode d'enregistrement normal (plus de piège « auto-punch »)
- Fenêtres nettes sur les écrans haute densité (Mac Retina, Windows 150 %)
- Version affichée dans la fenêtre principale, avec un lien « Nouveautés »
- Traduction : e-mail (limite × 10) ou clé DeepL gratuite, réglables dans la page Répliques — indispensable en salle de cours
- Ripple sur les bords : option « Au démarrage de REAPER » (activée automatiquement avec le ripple)
- Vocal level : bouton « Annuler l'analyse »
