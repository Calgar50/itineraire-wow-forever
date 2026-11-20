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
  - au rendu d'une quête, la récompense la plus utile pour ton rôle est encadrée « Conseillé » (sinon la plus chère à
    revendre) ; rien n'est cliqué à ta place ;
  - dans la bulle de n'importe quel objet (sacs, butin, hôtel des ventes) : « Itinéraire : +12 % pour toi » ;
  - la fenêtre **Équipement** (`/iti equipement`, bouton E) liste les améliorations à ton niveau, emplacement par
    emplacement, avec leur source : récompense de quête, vendeur, monstre ou coffre, **boss de donjon ou de raid**,
    **objet que tes métiers fabriquent** (recette connue ou à apprendre) ;
  - l'onglet **Donjons** répond à « quel donjon faire pour mon équipement ? » ;
  - **« Y aller »** ajoute la source (ou l'entrée du donjon) au trajet : la flèche t'y emmène.
- **DungeonJournal** ([ExehnTV](https://www.curseforge.com/wow/addons/dungeonjournal), intégré avec l'accord de son
  auteur) : quand il est installé, Itinéraire lit **pendant le jeu** ses donjons (nouveaux donjons de Forever compris),
  boss, butins et quêtes de donjon. Il suit donc ses mises à jour quotidiennes sans attendre une version
  d'Itinéraire. Ce que ça ajoute :
  - équipement : butins de ses donjons et **récompenses des quêtes de donjon**, avec où prendre la quête ;
  - donjon ajouté au trajet : **ses quêtes à prendre avant d'y aller** sont ajoutées aussi ;
  - quêtes de donjon que Questie ne connaît pas : lieu du rendu, entrée du donjon pour les objectifs ;
  - clic droit dans la fenêtre Équipement, ou `/iti dj [donjon]` : ouvre la page dans DungeonJournal.

  Rien de DungeonJournal n'est copié dans Itinéraire.

  Les objets sont notés avec leurs vraies caractéristiques (celles du jeu) : poids par classe tirés des guides,
  14 puissance d'attaque = 1 DPS d'arme, armure comptée en vie effective, et le rôle (tank, mêlée, distance, sorts,
  soins — deviné d'après tes talents, réglable). Les taux de butin ne sont connus ni du jeu ni des bases de données.
- **Le pilote automatique** (comme les guides « autopilot », allumé par défaut, bouton P ou `/iti pilote`) : il prend
  et rend les quêtes, choisit la bonne ligne des dialogues selon l'étape, prend chez le maître de vol le vol prévu par
  le trajet, passe les cinématiques, répare et vend les objets gris, apprend tes techniques chez le maître de classe, et
  affiche un bouton (avec raccourci) pour l'objet de quête à utiliser maintenant. Option : prendre aussi la récompense
  conseillée. MAJ (Shift) en parlant à un PNJ : tu reprends la main. Le personnage ne se déplace jamais tout seul : le
  jeu l'interdit aux addons. Si le jeu bloque une action, cette partie se coupe toute seule. Il s'occupe aussi :
  - de tes **talents** : il suit un plan selon ta classe et ton rôle (les 9 classes, chaque rôle : tank, mêlée,
    distance, sorts, soins, avec des variantes ; arbres de Forever 1.60.1) ; par défaut il demande avant chaque point (Apprendre / Plus tard /
    Toujours), car un point ne se reprend que contre de l'or. Sur Forever, le jeu applique les talents par une courte
    incantation : il attend que tu sois immobile. `/iti talents` montre le plan ;
  - de ton **équipement** : il met tout seul (hors combat) l'objet de tes sacs qui t'améliore d'au moins 3 % ; un objet
    lié quand équipé pas encore lié : il demande ; tu remets ton ancien objet : il n'y touche plus ; un objet porté à
    effet « Utiliser » n'est pas remplacé ;
  - de tes **sacs** : un sac de tes sacs va dans un emplacement de sac libre ;
  - de tes **barres d'action** : les sorts de ta classe qui n'y sont pas vont dans les cases vides des barres
    affichées, et un sort passe à son rang supérieur dès que tu l'apprends, à la même place. Rien n'est déplacé ni
    retiré ; un sort que tu enlèves n'y revient plus.
- **Les quêtes que Questie ne sait pas placer** : Itinéraire prend le repère que le jeu dessine sur la carte (et
  DonData s'il est installé), au lieu de les laisser de côté.
- **À plusieurs** (2 à 5 joueurs, désactivé par défaut) : le chef de groupe calcule un seul trajet avec les
  quêtes de tout le monde.

## Installer

1. Télécharge le **paquet** de la dernière version : onglet [Releases](https://github.com/Calgar50/itineraire-wow-forever/releases)
   → `Itineraire-vX.Y.Z-paquet.zip`.
2. Quitte WoW, extrais le zip, double-clique sur **`Installer-Itineraire.cmd`**.

L'installateur trouve le dossier de WoW Forever, installe ou met à jour **Itinéraire, Questie (+ QuestieDB),
Shortest Path Forever (qui inclut sa copie de ForeverCore) et DungeonJournal** (depuis sa page CurseForge ; `-SansDungeonJournal` pour
s'en passer) et propose d'activer la **mise à jour automatique**.

Installation à la main : copie le dossier `Itineraire` du fichier `Itineraire-vX.Y.Z.zip` dans
`World of Warcraft\_forever_\Interface\AddOns`, et installe Questie et Shortest Path Forever (CurseForge par
exemple).

### Mise à jour automatique

Une tâche planifiée de Windows, à ton nom et sans droits d'administrateur, relance l'installateur
(`-Auto`) à l'ouverture de session puis toutes les 4 heures, **seulement quand l'ordinateur est inutilisé
depuis 10 minutes et que WoW est fermé**. Les nouvelles versions comptent au lancement suivant du jeu.
DungeonJournal, qui sort presque tous les jours, est mis à jour par la même tâche (s'il est installé : le supprimer
suffit pour qu'elle le laisse tranquille).

- Journal : `%LOCALAPPDATA%\Itineraire\maj.log`.
- Activer / désactiver : relance l'installateur avec `-ActiverMajAuto` ou `-DesactiverMajAuto`.
- Dans le jeu : Itinéraire annonce ce qui a été mis à jour depuis ta dernière session.

### Sécurité de l'installateur

- Téléchargements en HTTPS depuis GitHub, et depuis CurseForge pour DungeonJournal (adresses et redirections
  vérifiées).
- Empreinte SHA-256 de chaque fichier comparée à celle publiée par GitHub : refus si elle manque ou diffère.
  CurseForge ne publie pas d'empreinte : pour DungeonJournal, l'installateur exige un fichier publié par le compte
  de son auteur, à la taille exacte annoncée, ne contenant que le dossier de l'addon et des fichiers d'addon, avec
  le bon fichier `.toc` (titre, auteur, version).
- Archives contrôlées entrée par entrée : rien ne peut s'écrire hors du dossier prévu ; seuls les dossiers
  d'addons attendus sont installés.
- L'ancienne version de chaque addon est rangée dans `Interface\AddOns_sauvegardes` (les 2 dernières sont gardées) ;
  une version installée plus récente n'est jamais remplacée. Un ForeverCore installé à part, plus ancien que la copie
  incluse dans Shortest Path et exigé par aucun addon, y est rangé aussi.
- **Le script ne se met jamais à jour tout seul** : seuls les addons (du code de jeu, sans accès à ton
  ordinateur) sont téléchargés. Un nouvel installateur se récupère à la main ; Itinéraire prévient dans le jeu
  quand il en sort un.
- Le script est lisible : `installateur/Installer-Itineraire.ps1`.

## Commandes

| Commande | Effet |
| --- | --- |
| `/iti` | afficher ou cacher la fenêtre |
| `/iti pilote` | pilote automatique : marche / arrêt |
| `/iti talents` | plan de talents suivi et prochain point (et la question, s'il y a un point à mettre) |
| `/iti equipement` | la fenêtre Équipement |
| `/iti dj [donjon]` | ouvrir DungeonJournal (sur un donjon) |
| `/iti reglages` | tous les réglages (Trajet, Fenêtre, Équipement, Pilote, Questie & flèche) |
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
  `GearUI` (équipement), `DungeonJournal` (lecture de l'addon DungeonJournal en jeu), `Group` (partage),
  `Pilote` (pilote automatique), `Core` (événements, calcul en tâche de fond).
- `tests/` : faux WoW en Lua 5.1 exécuté avec [lupa](https://pypi.org/project/lupa/) :

  ```sh
  python -m venv venv && venv/Scripts/pip install lupa
  sh tests/run_all.sh venv/Scripts/python.exe "$PWD/tests" "$PWD/Itineraire"
  ```
- `installateur/` : `Installer-Itineraire.ps1` (PowerShell 5.1, ASCII + BOM + CRLF) et son lanceur `.cmd`.
- `outils/paquet.py` : fabrique `dist/Itineraire-vX.Y.Z.zip` (l'addon, lu par l'installateur) et
  `dist/Itineraire-vX.Y.Z-paquet.zip` (installateur + addon + mode d'emploi) pour une release GitHub.
- `outils/plans_talents.py` : vérifie les plans de talents d'`Autonomie.lua` contre les arbres de talents de
  Forever publiés par ForeverDB (à relancer après un patch qui touche aux talents).
- `outils/donnees.py` : réimporte les données reprises d'autres addons (commits épinglés, SHA-256 vérifié) dans
  `Itineraire/Donnees/`.
- `CHANGELOG.md` : notes techniques de chaque version.

## Données reprises et remerciements

Itinéraire s'appuie sur le travail d'autres projets (détail et licences : `THIRD_PARTY.md`) :

- [Questie](https://github.com/Questie/Questie) / QuestieDB : quêtes, PNJ, objets (lus en jeu) ;
- [Shortest Path Forever](https://github.com/cjber/shortest-path-forever) : la flèche et les trajets ;
- [DungeonJournal](https://www.curseforge.com/wow/addons/dungeonjournal) (ExehnTV) : donjons, boss, butins et quêtes
  de donjon de Forever, lus en jeu avec l'accord de son auteur (rien n'est copié) ;
- les addons de [WoW-Forever-Addons](https://github.com/orgs/WoW-Forever-Addons/repositories) (DonCoohd) :
  butins des donjons et raids (Dropdon), entrées des donjons (DonData), recettes (Guildon Crafts), vendeurs et
  entraîneurs (Finddon) ;
- [All The Things](https://github.com/ATTWoWAddon/AllTheThings), [CMaNGOS classic-db](https://github.com/cmangos/classic-db)
  et **Data from ForeverDB.net (https://foreverdb.net)** ;
- le modèle de note des objets, la prise et le rendu automatiques des quêtes, la vente des objets gris et les
  précautions propres à Forever (fenêtre de quête, données « secrètes ») viennent de DonData et Questdon (MIT).

## Licence

GNU General Public License v3 ou ultérieure (`LICENSE`). Les données reprises gardent leur licence (MIT ou GPL v3).
