# Itinéraire — le trajet le plus court à travers ton journal de quêtes (WoW Forever)

Itinéraire est un addon pour **World of Warcraft Forever**. Il lit **ton** journal de quêtes, calcule l'ordre le
plus court pour tout faire (objectifs regroupés, rendus en série, vols, bateaux, pierre de foyer) et le confie
à la flèche de [Shortest Path Forever](https://github.com/cjber/shortest-path-forever). Il s'appuie sur la base
de [Questie](https://github.com/Questie/Questie) pour savoir où sont les monstres, les objets et les PNJ.

Il ne suit pas un guide figé : le trajet se recalcule à chaque quête prise, rendue ou avancée.

## Ce qu'il fait

- **Le trajet** : toutes les quêtes du journal, sans en écarter aucune (une quête trop dure passe en fin de
  trajet, ou juste après le moment où tu auras le niveau). **Selon ton niveau** : rien n'est proposé dans une zone
  dont le plus bas niveau est 4 au-dessus du tien (quête à prendre, marchand, maître, auberge), et une quête du
  journal qui ne se fait ou ne se rend que là passe en fin de trajet, avec la raison. Option « finir la région d'abord », avec les quêtes
  à prendre de la région. Quêtes proposées sur le trajet et suites de quêtes (jamais celles d'une autre classe
  ou d'une autre race). Donjons, réparer / vendre, maître de classe, pierre de foyer.
- **Ma soirée** (bouton « Zzz », ou `/iti soiree 1h30`, `/iti soiree 23h`) : tu dis combien de temps tu as.
  Itinéraire garde les quêtes qui rapportent le plus d'XP par minute dans ce temps (une zone lointaine compte son
  voyage, payé une fois par ses quêtes) et finit le trajet dans une **auberge**, où ton repos monte 4 fois plus vite
  qu'en pleine nature ; si ta pierre de foyer est prête à la fin et fait gagner du temps, c'est elle qui t'y emmène.
  Le reste du journal passe après l'auberge (« après la soirée ») : aucune quête n'est écartée. Arrivé à l'auberge :
  le bilan de la soirée (niveau, quêtes rendues).
- **La suite après la région** : quand ton journal se vide (moins de 4 étapes ou de 20 minutes), une étape
  « Nouvelle région » t'emmène dans la zone de ton niveau qui a le plus de quêtes à prendre (au moins 4, pas dans
  une zone trop haute), au point où leurs donneurs se regroupent. Sur place, le mode région prend le relais.
- **Ma montée** (bouton parchemin, ou `/iti montee`) : la **frise jusqu'au niveau 60**, zone par zone, à partir des
  quêtes de la base Questie faisables par ta classe et ta race et pas encore faites, avec les **donjons** au bon moment
  (estimation : les suites de quêtes sont comptées comme ouvertes, l'XP des monstres n'est pas comptée). Onglet
  **Minage et forge** : les filons qui te font monter (orange, jaune ; vert parfois), tes minerais et barres, les
  recettes de forge qui font monter et ce qu'elles demandent (couleurs exactes une fois ta fenêtre de forge ouverte).
- **Les filons sur le trajet** : avec le minage, les coins à filons utiles (2 emplacements ou plus) qui demandent moins
  de ~75 secondes de détour dans la première demi-heure du trajet deviennent des étapes (3 au plus). Un filon n'est
  pas toujours là : l'étape se valide en arrivant, puis pas d'autre détour de minage pendant 10 min. Jamais vers
  l'argent, l'or ni le vrai-argent (ils remplacent rarement un filon courant : emplacements presque toujours vides).
  Le même coin reste au trajet d'un calcul à l'autre. Menu … pour couper.
- **Objet de quête dans les sacs mais pas compté** (« 0/1 » alors que tu l'as) : Itinéraire ne te renvoie pas le
  chercher, il te mène au rendu et te le dit dans le tchat (/reload ou reconnexion si le PNJ ne prend pas la quête).
  Au bout de 20 min sans que le jeu le compte, il refait confiance au jeu.
- **Contrôle en jeu** (`/iti controle`) : chaque partie de l'addon est vérifiée pour de vrai dans ton jeu (Questie,
  Shortest Path, trajet, niveau de ta zone, pierre de foyer, talents, équipement, barres, pilote, DungeonJournal,
  métiers, mise à jour automatique) ; le compte rendu, rapport complet compris, est prêt à copier-coller.
- **Trier mon journal** (`/iti tri`, sur ta demande seulement) : la liste des quêtes grises (trop basses pour te
  rapporter de l'XP), échouées ou qui ne te rapportent presque rien, avec la raison. Tu coches, tu confirmes (deux
  clics), elles sont abandonnées, puis le journal est relu pour vérifier. Gardées d'office : la quête suivie, les
  quêtes de classe ou de métier, celles dont la récompense t'améliore, celles qui mènent à une suite de ton niveau.
  Une quête grise terminée est proposée sans être cochée (la rendre rapporte encore un peu).
- **Vider mes sacs** (`/iti sacs`, sur ta demande seulement) : ce qui ne te sert pas ou plus, avec la raison.
  Coché d'office : le gris, l'équipement lié moins bon que le tien ou que ta classe ne porte pas. À toi de voir pour
  le reste : équipement pas encore lié (hôtel des ventes ?), équipement d'un autre rôle, consommables de bas niveau,
  composants et recettes de métiers que tu n'as pas. « Vendre » : tout de suite chez un marchand ouvert, sinon au
  prochain (le trajet en ajoute un) ; un objet vendu se rachète chez ce marchand jusqu'à ta déconnexion.
  « Détruire » (deux clics) : seulement ce qui ne se vend pas. Jamais proposé : pierre de foyer, outils de métier,
  objets de quête, ensembles d'équipement, améliorations (même pour plus tard), ce qui sert à tes métiers, sacs.
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
  - bouton **livre** de la fenêtre d'Itinéraire (ou un raccourci clavier, Échap > Raccourcis > Itinéraire) : ouvre
    DungeonJournal sur le donjon où tu es, sinon sur le prochain donjon de ton trajet ; clic droit : les donjons de
    ton niveau. Aussi : clic droit dans la fenêtre Équipement, ou `/iti dj [donjon]`.

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
    affichées, et un sort passe à son rang supérieur dès que tu l'apprends, à la même place ; un sort que tu enlèves
    n'y revient plus. **Guerrier : barres rangées par posture** (tout seul, puis entretenu ; `/iti barres non` pour ne plus ranger) : la barre
    principale change avec la posture, et chaque touche y garde le même rôle (1 Charge / Interception, 2 Frappe
    héroïque, 3 Fulgurance / Vengeance / Tourbillon, 4 grosse frappe, 5 Fracasser l'armure, 6 Coup de tonnerre, 8
    interrompre, 9 provoquer, 12 survie…) ; les cris et autres sorts vont sur la barre du dessus. Postures exigées :
    celles de Forever (Coup de tonnerre aussi en Défensive, Charge en Défensive avec Avant-garde). Tes objets et
    macros sont déplacés vers une case libre, jamais effacés ; `/iti barres annuler` remet tout comme avant. Ensuite
    un nouveau sort va à sa touche, et une case que tu changes reste à toi. **Druide : par forme** (humanoïde, félin,
    ours ; sélénien et félin en rôdant dès que le jeu leur donne une page) : 1 Colère / Griffe / Mutiler, 3 Éclat
    lunaire / Griffure / Lacérer, 6 Lucioles partout, 8 Récupération / Traquenard / Sonner… **Voleur : camouflé ou
    non** : 1 Attaque pernicieuse / Coup bas, 2 Attaque sournoise / Embuscade, 5 Rupture / Garrot, 7 Suriner /
    Assommer, 12 Disparition / Camouflage…
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
(`-Auto`) 2 minutes après l'ouverture de session puis toutes les 4 heures, **sans aucune fenêtre** (`conhost
--headless`) **et jamais quand WoW est ouvert** (installateur 5 ; le 4 attendait 10 minutes d'ordinateur inutilisé
et ne passait presque jamais). Les nouvelles versions comptent au lancement suivant du jeu.
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
| `/iti soiree [1h30 \| 45 \| 23h \| stop]` | ma soirée : le temps que tu as (ou jusqu'à quelle heure), puis une auberge |
| `/iti montee` | ma montée : la frise jusqu'au niveau 60 (`/iti minage` : minage et forge) |
| `/iti sacs` | vider mes sacs : vendre ou jeter ce qui ne sert plus (tu coches, tu confirmes) |
| `/iti tri` | trier mon journal : abandonner les quêtes grises ou inutiles (tu coches, tu confirmes) |
| `/iti controle` | contrôle en jeu de tout l'addon, compte rendu à copier |
| `/iti pilote` | pilote automatique : marche / arrêt |
| `/iti talents` | plan de talents suivi et prochain point (et la question, s'il y a un point à mettre) |
| `/iti equipement` | la fenêtre Équipement |
| `/iti barres [ranger \| annuler \| non]` | barres par posture, forme ou camouflage (guerrier, druide, voleur) : voir chaque touche, ranger, revenir |
| `/iti dj [donjon]` | ouvrir DungeonJournal (le donjon où tu es ou celui du trajet ; ou celui nommé) |
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
