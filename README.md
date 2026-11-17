# Itinéraire — le trajet le plus court à travers ton journal de quêtes (WoW Forever)

Itinéraire est un addon pour **World of Warcraft Forever**. Il lit **ton** journal de quêtes, calcule l'ordre le
plus court pour tout faire (objectifs regroupés, rendus en série, vols, bateaux, pierre de foyer) et le confie
à la flèche de [Shortest Path Forever](https://github.com/cjber/shortest-path-forever). Il s'appuie sur la base
de [Questie](https://github.com/Questie/Questie) pour savoir où sont les monstres, les objets et les PNJ.

Il ne suit pas un guide figé : le trajet se recalcule à chaque quête prise, rendue ou avancée.

## Ce qu'il fait

- **Le trajet** : toutes les quêtes du journal, sans en écarter aucune (une quête trop dure passe en fin de
  trajet, ou juste après le moment où tu auras le niveau). Option « finir la région d'abord », avec les quêtes
  à prendre de la région. Quêtes proposées sur le trajet et suites de quêtes (jamais celles d'une autre classe
  ou d'une autre race). Donjons, réparer / vendre, maître de classe, pierre de foyer.
- **Le bandeau** au-dessus de la flèche : l'étape en cours, le temps restant, l'étape d'après.
- **Ton rythme** : il apprend en jouant le temps que tu mets par monstre, par objet et par zone, et affiche des
  fourchettes de temps qui se resserrent.
- **L'équipement** :
  - au rendu d'une quête, la récompense la plus utile pour ton rôle est encadrée et présélectionnée (sinon la
    plus chère à revendre) ;
  - la fenêtre **Équipement** (`/iti equipement`) liste les améliorations à ton niveau, emplacement par
    emplacement, avec leur source : récompense de quête, vendeur, PNJ ou boss qui le fait tomber, coffre ;
  - **« Y aller »** ajoute la source au trajet : la flèche t'y emmène.

  Les objets sont notés avec leurs vraies caractéristiques (celles du jeu) selon ton rôle (tank, mêlée,
  distance, sorts, soins — deviné d'après tes talents, réglable) puis comparés à ce que tu portes. Les taux de
  butin ne sont connus ni du jeu ni de Questie.
- **À plusieurs** (2 à 5 joueurs, désactivé par défaut) : le chef de groupe calcule un seul trajet avec les
  quêtes de tout le monde.

## Installer

1. Télécharge le **paquet** de la dernière version : onglet [Releases](https://github.com/Calgar50/itineraire-wow-forever/releases)
   → `Itineraire-vX.Y.Z-paquet.zip`.
2. Quitte WoW, extrais le zip, double-clique sur **`Installer-Itineraire.cmd`**.

L'installateur trouve le dossier de WoW Forever, installe ou met à jour **Itinéraire, Questie (+ QuestieDB) et
Shortest Path Forever (+ ForeverCore)** et propose d'activer la **mise à jour automatique**.

Installation à la main : copie le dossier `Itineraire` du fichier `Itineraire-vX.Y.Z.zip` dans
`World of Warcraft\_forever_\Interface\AddOns`, et installe Questie et Shortest Path Forever (CurseForge par
exemple).

### Mise à jour automatique

Une tâche planifiée de Windows, à ton nom et sans droits d'administrateur, relance l'installateur
(`-Auto`) à l'ouverture de session puis toutes les 4 heures, **seulement quand l'ordinateur est inutilisé
depuis 10 minutes et que WoW est fermé**. Les nouvelles versions comptent au lancement suivant du jeu.

- Journal : `%LOCALAPPDATA%\Itineraire\maj.log`.
- Activer / désactiver : relance l'installateur avec `-ActiverMajAuto` ou `-DesactiverMajAuto`.
- Dans le jeu : Itinéraire annonce ce qui a été mis à jour depuis ta dernière session.

### Sécurité de l'installateur

- Téléchargements en HTTPS depuis GitHub uniquement (adresse vérifiée).
- Empreinte SHA-256 de chaque fichier comparée à celle publiée par GitHub : refus si elle manque ou diffère.
- Archives contrôlées entrée par entrée : rien ne peut s'écrire hors du dossier prévu ; seuls les dossiers
  d'addons attendus sont installés.
- L'ancienne version de chaque addon est rangée dans `Interface\AddOns_sauvegardes` (les 2 dernières sont gardées) ;
  une version installée plus récente n'est jamais remplacée.
- **Le script ne se met jamais à jour tout seul** : seuls les addons (du code de jeu, sans accès à ton
  ordinateur) sont téléchargés. Un nouvel installateur se récupère à la main ; Itinéraire prévient dans le jeu
  quand il en sort un.
- Le script est lisible : `installateur/Installer-Itineraire.ps1`.

## Commandes

| Commande | Effet |
| --- | --- |
| `/iti` | afficher ou cacher la fenêtre |
| `/iti equipement` | la fenêtre Équipement |
| `/iti reglages` | tous les réglages (Trajet, Fenêtre, Équipement, Questie & flèche) |
| `/iti assistant` | les 5 questions du début |
| `/iti rendus` | route des rendus (seulement les quêtes terminées) |
| `/iti r` | recalculer |
| `/iti rythme` | ton rythme appris |
| `/iti groupe` | partage de groupe |
| `/iti version` | version et état des mises à jour |
| `/iti rapport` | rapport à copier en cas de souci |

## Développement

- `Itineraire/` : l'addon (Lua 5.1). `Data` (journal + Questie) → `Planner` (étapes, propositions) →
  `Solver` (ordre le plus court sous contraintes) → `Guide` (Shortest Path) → `UI` / `Options` ; `Gear` /
  `GearUI` (équipement), `Group` (partage), `Core` (événements, calcul en tâche de fond).
- `tests/` : faux WoW en Lua 5.1 exécuté avec [lupa](https://pypi.org/project/lupa/) :

  ```sh
  python -m venv venv && venv/Scripts/pip install lupa
  sh tests/run_all.sh venv/Scripts/python.exe "$PWD/tests" "$PWD/Itineraire"
  ```
- `installateur/` : `Installer-Itineraire.ps1` (PowerShell 5.1, ASCII + BOM + CRLF) et son lanceur `.cmd`.
- `outils/paquet.py` : fabrique `dist/Itineraire-vX.Y.Z.zip` (l'addon, lu par l'installateur) et
  `dist/Itineraire-vX.Y.Z-paquet.zip` (installateur + addon + mode d'emploi) pour une release GitHub.
- `CHANGELOG.md` : notes techniques de chaque version.
