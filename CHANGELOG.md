# Journal des versions d'Itinéraire

Notes techniques de chaque version (la plus récente en bas). Pour l'usage, voir `README.md`.

- v1.0 à v1.2 (14/11/2026) : planificateur de trajet à partir du journal de quêtes (Questie + Shortest Path
  Forever), fenêtre réglable, quête suivie, aucune quête écartée (les trop dures passent en fin de trajet).
- v1.3.0 (15/11/2026) : prévision d'XP étape par étape (récompenses + 70 % des monstres à tuer, table Classic
  mise à l'échelle sur UnitXPMax) ; 2e passe qui avance les quêtes « plus tard » dont on aura le niveau en
  route (contraintes « après les étapes qui donnent l'XP », gardée seulement si le trajet n'est pas plus long ;
  `plan.promotion` = coûts avant/après) ; fusion d'étapes seulement entre même priorité ; « tournées » de
  rendus ; icônes d'étape envoyées à Shortest Path (`kind`) ; une étape forcée passe devant les priorités.
  Tests : `promo_test.lua`, `promo_test17.lua`, `pin_test.lua` (même préambule que scenario.lua).
- v1.4.0 (15/11/2026) : 3e passe de `Planner.Build`.
  - Quêtes proposées (`Planner.SelectCandidates`) : suites (`nextQuestInChain`, prise après le rendu
    de la quête d'avant) + quêtes de `AvailableQuests` dont le donneur est à ≤ 300 yd du trajet ;
    évaluées par insertion au moins cher (prise > objectifs via `ObjectiveData` > rendu), gardées si
    XP/temps ≥ 80 % du rythme du trajet, détour + travail ≤ 15 min, places libres du journal
    (`GetMaxNumQuestsCanAccept`).
  - Arrêt réparer/vendre (`Planner.SelectService`) : usure ≤ 25 % (objet) ou ≤ 50 % (moyenne), ou
    ≤ 3 places libres ; réparateurs = Questie `Townsfolk.townsfolk.Repair` ; dans les 30 premières
    minutes, en tête si urgent ; levé 15 min après `MERCHANT_CLOSED`.
  - Estimation d'XP (70 × niveau) quand Questie n'a pas l'XP d'une quête Forever.
  - Test : `propositions_test.lua` (autonome, sans export).
- v1.5.0 (15/11/2026) : précision.
  - Rythme appris (`ItineraireCharDB.calib`) : secondes par monstre/objet/objet utilisé = moyenne glissante
    des écarts entre deux progrès d'un même objectif (≤ 300 s, 1er progrès ignoré) ; facteur de marche =
    temps réel / estimé à l'arrivée sur une étape à pied (≥ 30 s prévues). Actif à partir de 3 mesures.
    `/iti rythme`, `/iti rythme reset`.
  - Étape en cours : `ShortestPathForever.API.Journey().secondsLeft` pour l'affichage (pas pour l'ordre :
    biais face aux estimations en ligne droite).
  - XP de repos (`GetXPExhaustion`) dans la prévision ; élites (rang Questie 1-3, niveau ≥ joueur - 2) =
    « plus tard », sans avance au niveau ; en groupe (`IsInGroup`, ≥ 2) quêtes de groupe/élites normales.
  - Quantités des quêtes proposées lues dans `objectivesText` ; heures (« fin vers ») via `time()`/`date()`.
  - Test : `rythme_test.lua` (lent : ~2 min, à cause des tickers simulés).
  - Stabilité : quêtes proposées / avancées au calcul précédent gardées avec tolérance (hystérésis),
    sinon l'étape en cours sautait d'un calcul à l'autre. Test : `stab_test.lua`.
- v1.6.0 (15/11/2026) : NOUVEAU FICHIER `Group.lua` (relancer WoW, un /reload peut ne pas le charger ;
  Core remplace alors le module par une coquille vide et l'indique).
  - Partage de groupe (2 à 5, désactivé par défaut, `ItineraireDB.groupShare`, `/iti groupe`) : préfixe
    `ITIN1`, canal PARTY, messages `S` (état du journal), `Q` (demande d'état), `R` (trajet), `H` (signe de
    vie), découpés en morceaux de 200 octets (sans couper l'UTF-8), 1 envoi / 0,2 s. Guide = chef de groupe
    s'il partage, sinon 1er nom alphabétique. Le guide fusionne les quêtes des équipiers (`MergeGroup`,
    `Data.ExternalQuest` via `ObjectiveData`) ; rien de personnel dans un trajet de groupe. Suiveur : trajet
    reçu affiché + flèche, calcul perso suspendu ; retour au solo après 150 s sans nouvelles. Tout message
    est validé et borné, les « | » retirés (codes du jeu), expéditeur hors groupe ignoré.
  - Maître de classe (`Townsfolk.classSpecificTownsfolk[classe]["Class Trainer"]`) aux niveaux pairs depuis
    `ItineraireCharDB.trainedAt` (mis à jour par TRAINER_SHOW hors maître de métier).
  - Donjons : quêtes de donjon disponibles dont tous les objectifs sont dans un donjon du trajet -> prise
    avant, fusion dans l'étape du donjon (`EvaluateDungeon`).
  - Pierre de foyer : lieu lu dans `ShortestPathForeverCharDB.bind` (converti par
    `C_Map.GetMapPosFromWorldPos`), meilleur tronçon (≥ 2 min gagnées, pas le 1er), conseil d'auberge
    (Townsfolk « Innkeeper ») si ≥ 3 min de mieux.
  - Insertion des propositions : un nouveau tronçon peut passer par un trajet déjà connu (vol) puis à pied.
  - Tests : `extras_test.lua`, `group_test.lua` (les listes de fichiers des tests incluent `Group.lua`).
- v1.6.1 (15/11/2026) : robustesse après « plus de points sur la minimap » en jeu (cause pas encore connue).
  - Parties facultatives du calcul (quêtes avancées, propositions/arrêts, pierre de foyer) lancées par
    `Optional` dans leur propre coroutine (pcall ne laisse pas passer yield en Lua 5.1) : une erreur est
    notée (`plan.warnings` -> lastError) et le trajet de base part quand même.
  - `ns.ShowPlan` : flèche (Guide.Apply) AVANT la fenêtre, chacune sous pcall.
  - Guide : si Shortest Path refuse le trajet, 2e essai en version simple ; `ns.guideState` = dernier envoi.
  - `/iti etat` (diagnostic dans le tchat) ; `/iti debug` garde aussi guide, pause, warnings, version.
  - CHAT_MSG_ADDON : valeurs « secrètes » ignorées. Test : `robust_test.lua`.
- v1.7.0 (15/11/2026) : demande « ordre dynamique avec toutes les quêtes d'une région » + « route pour rendre
  toutes les quêtes faites ».
  - Mode région (`ItineraireDB.regionMode`, défaut oui) : région = zone du joueur (`Geo.Zone`, remonte
    sous-cartes -> mapType 3). Dans `Precedence` : étapes hors région -> `TIER_AWAY` (0,5, entre maintenant et
    plus tard), propagé le long des contraintes dures (un rendu ici dont l'objectif est ailleurs passe après).
    Quêtes disponibles dont le donneur est dans la région : toutes proposées (≤ 10, ≤ 25 min chacune, sans seuil
    d'XP), dans la limite places libres + rendus du journal faits dans la région.
  - Place dans le journal dans le Solver (`preds.cap` : prise +n, rendu -n, seules les prises sont bloquées ;
    abandonnée si l'ordre glouton ne peut pas la respecter).
  - Prises regroupées par donneur (« Prendre N quêtes », clé `P:id1,id2`) ; objectifs des quêtes proposées
    mêlés aux zones voisines ; leurs rendus regroupés entre eux (phase `cand`), pas avec ceux du journal (sinon
    blocage journal plein). Les suites gardent leurs propres étapes (cycles).
  - Route des rendus (`ns.session.turnins`, bouton « ? », `/iti rendus`, raccourci) : seulement les quêtes
    finies ; retour automatique au trajet complet quand tout est rendu.
  - Test : `region_test.lua`.
- v1.7.1 (15/11/2026) : « plus de points sur la minimap ». Trouvé dans les erreurs enregistrées par Shortest
  Path (`ShortestPathForeverDB`, 12:38) : `UI/Looks.lua:63 bad argument #1 to ipairs` = le genre d'étape
  `kind = "vendor"` (déclaré par SP 1.37 mais sans image) plante le dessin de l'épingle, ce qui coupe la suite
  de `SetJourneyRoute` (dont le tracé minimap). Itinéraire n'envoie plus `vendor`. + reprise automatique
  d'une pause (trajet effacé/remplacé) quand plus aucun trajet SP n'est actif depuis 10 s (`ns.AutoResume`).
- v1.7.2 (15/11/2026) : « le guidage s'arrête et reprend » / « Recherche du chemin le plus rapide… » sans points.
  Cause : chaque NavigateRoute modifié fait repartir SP (StartJourney -> StopGuide + nouvelle recherche) ; pendant
  sa 1re recherche, `API.Journey()` renvoie `nil, "loading"` -> Itinéraire croyait le trajet perdu et le
  renvoyait à chaque recalcul -> recherche relancée sans fin. Désormais : `loading` = toujours notre trajet ;
  tant que la 1re étape (clé + position) ne change pas, la suite n'est renvoyée qu'au plus toutes les 60 s
  (jamais pendant une recherche, ≤ 45 s), le titre de la 1re étape étant renommé ; `Guide.Flush` toutes les 5 s.
  Group.OnRoster ne recalcule plus quand le partage est coupé. Test : `robust_test.lua` (« OK recherche »).
- v1.8.0 (16/11/2026) : « le top du top » — plus intuitif, plus précis, un seul paquet.
  - Bandeau « prochaine étape » (`ItineraireBanner`, au-dessus de la flèche de SP d'après `ShortestPathForeverDB.arrowX/Y`,
    sinon TOP -118 ; déplaçable, `ui.bannerPos`, `ui.bannerScale`) : étape, temps restant de `API.Journey()` (+ moyen de
    transport `legs[1].text`), « Sur place », étape suivante ; clic = fenêtre, clic droit = menu de l'étape / reprendre.
  - Assistant de départ (`Options.ShowWizard`, une fois : `ItineraireDB.wizardDone`) : solo/groupe, région, rendu auto
    Questie (`Questie.db.profile.autocomplete`), fenêtre légère (3 étapes, « À savoir » replié) ou complète, réglages
    conseillés de SP (`ShortestPathForeverDB` : journey, arrow, arrowLabel=both, minimapLine, mapLine, laterLegs,
    useHearthstone). `/iti assistant`.
  - Réglages tout-en-un (`/iti reglages`) : onglets Trajet / Fenêtre / Questie & flèche ; menu … raccourci.
  - `/iti rapport` : boîte de texte brut à copier (version, addons, options, flèche, trajet, rythme, 5 dernières erreurs,
    journal d'erreurs ForeverCore d'Itinéraire ET de Shortest Path via `ForeverCore.Register(nom).CaughtErrors()`).
    Itinéraire s'inscrit au journal ForeverCore (`ItineraireDB.forever`) : erreurs hors calcul gardées entre sessions.
  - Rythme par cible (`calib.targets["monster:3245"]`, ≤ 300) et par objectif en cours (`calib.slots["quête:index"]`),
    mêlés au rythme général par rétrécissement (n·v + 2·général)/(n + 2) ; marche par zone (`calib.zones`, vers le
    général avec un poids 3 ; `Geo.SetPace(général, zones)`, `Geo.PaceAt(point)` = zone d'arrivée).
  - Fourchettes : écart moyen appris (`d` dans chaque mesure) ; par étape √(r²/unités + 0,15²) sur place, r en route
    (0,1 si temps exact) ; total = √(Σσ² + (erreur d'ensemble × total)²), erreur d'ensemble 0,2 / 0,14 / 0,08 selon
    que rien / une partie / tout le rythme est mesuré.
  - 3 prochaines étapes : chemin détaillé de SP (`API.EstimateDetail` : à pied, vol, bateau…) pour les tronçons non
    à pied, estimation SP en bulle pour les longs tronçons à pied (affichage seulement, l'ordre n'en dépend pas).
  - Installateur PowerShell : dernière version GitHub de Questie (bundle Questie+QuestieDB, QuestieTrace écarté) et de
    SP (+ ForeverCore), SHA-256 vérifié contre `digest` de l'API GitHub (refus sans empreinte), extraction contrôlée
    (pas de « .. », dossiers attendus seulement), jamais de rétrogradation, pas de téléchargement si déjà à jour,
    sauvegarde `Interface\AddOns_sauvegardes\<date>` (2 gardées, marquées `.itineraire-sauvegarde`), retour de l'ancienne
    version si l'installation d'un dossier échoue. Options `-WowPath`, `-Verifier`, `-SansTelechargement`, `-Oui`.
  - Faux WoW : l'OnUpdate des cadres nommés ne fait plus tourner la boucle de test (tests 10× plus rapides).
    Test : `v18_test.lua`.
- v1.8.1 (16/11/2026) : « il me propose une quête que je ne peux pas faire, je n'ai pas la bonne classe ».
  Les quêtes à PRENDRE (suites `nextQuestInChain`, quêtes de la région / du trajet, préparation des donjons, prises
  « au passage ») passent par `Data.CanTake` : classe (`requiredClasses` via `QuestiePlayer.HasRequiredClass`, repli
  `UnitClass`), race (`QuestiePlayer.HasRequiredRace`, sinon rien n'est retiré : races Forever au-delà de 32 bits),
  métier (`QuestieProfessions:HasProfessionAndSkillLevel`), `exclusiveTo` fait ou dans le journal, `QuestieDB.autoBlacklist`.
  Fuites d'origine : les suites `nextQuestInChain` n'étaient pas contrôlées, et Questie ajoute à `__availableQuests`
  les `childQuests` d'une quête du journal en ne vérifiant que la race (`_DrawChildQuests`). Les quêtes du journal ne
  sont jamais filtrées (règle « aucune quête ignorée »). Test : `classe_test.lua` (18 tests dans `run_all.sh`).
- v1.9.0 (17/11/2026) : équipement + mises à jour automatiques + dépôt public.
  - Nouveaux fichiers `Gear.lua` (notes, comparaison, récompense conseillée, recherche dans la base) et
    `GearUI.lua` (fenêtre « Équipement ») : relancer WoW (un /reload ne les charge pas). Core met une coquille
    vide à la place s'ils manquent.
  - Note d'un objet = Σ caractéristiques (`GetItemStats`) × poids du rôle (tank, mêlée, distance, sorts, soins ;
    rôle auto = arbre de talents le plus rempli, sinon d'après la classe) ; % du jeu classique (« +1 % crit »)
    convertis × 14. Comparaison avec l'objet porté (anneaux/bijoux : le plus faible ; deux mains : main droite +
    main gauche). Types d'armure et d'armes par classe (plaques/mailles à partir du niveau 40) ; un tank ne garde
    pas d'arme à deux mains (bouclier).
  - Récompense conseillée (`QUEST_COMPLETE`) : meilleure amélioration, sinon la plus chère à revendre ; cadre
    « Conseillé » sur le bouton, présélection via `QuestInfoItem_OnClick` (le joueur valide lui-même).
  - Recherche des améliorations (coroutine, 4 ms par image) dans `QuestieDB.ItemPointers` : armes/armures de
    niveau requis [niveau − 10, niveau + 3] portables par la classe, avec une source précise (récompense de quête
    faisable par la classe/race — `Data.CanTake` —, ≤ 8 vendeurs, ≤ 6 PNJ, ≤ 4 objets ; au-delà = butin du monde,
    écarté). Chargement des objets à la demande (`C_Item.RequestLoadItemDataByID`). 3 meilleures pistes par
    emplacement. Sources : journal > vendeur > quête à prendre > butin > donjon > coffre > plus tard.
  - « Y aller » (`ItineraireCharDB.gear.goals`) : vendeur / PNJ / coffre / entrée du donjon = étape « service »
    `S:objet<id>` (lieu au moindre détour, `Planner.SelectGoal`) ; récompense d'une quête à prendre = quête
    forcée dans les propositions (`opts.wantedQuests`). Objectif retiré quand l'objet est dans les sacs.
  - Rendus : « Récompense à prendre : X » dans la bulle et « récompense pour toi » sous l'étape
    (`opts.gearQuests`) ; une quête proposée dont la récompense améliore passe avec un seuil XP/temps de 50 %.
  - Versions : Itinéraire note les versions de Questie, QuestieDB, Shortest Path, ForeverCore et d'Itinéraire
    (`ItineraireDB.versions`) et annonce ce qui a changé ; nouveautés (`ns.NEWS`) une fois par version.
  - Groupe : message `V` (version d'Itinéraire, ≤ 1/min, même sans partage) ; prévenu si un équipier a plus récent.
  - Installateur v2 : Itinéraire aussi depuis GitHub (`Calgar50/itineraire-wow-forever`, fichier
    `Itineraire-vX.Y.Z.zip`, SHA-256), le plus récent entre GitHub et le dossier fourni ; une source en panne
    n'empêche plus les autres ; `-Auto` (tâche planifiée : silencieux, journal `%LOCALAPPDATA%\Itineraire\maj.log`,
    rien si WoW est ouvert, au plus toutes les 3 h), `-ActiverMajAuto` / `-DesactiverMajAuto` (tâche à ton nom,
    sans droits admin : ouverture de session + toutes les 4 h, seulement si l'ordinateur est inutilisé depuis
    10 min). Le script ne se met jamais à jour tout seul. Il écrit `Itineraire\Installateur.lua`
    (`ItineraireInstallateur = { version, auto, verifie }`) : le jeu prévient si l'installateur est trop ancien
    (`ns.INSTALLER_WANTED`).
  - Réglages : 4e onglet « Équipement » (récompenses, rôle, analyse) ; « Mises à jour » dans « Questie & flèche ».
  - Tests : `gear_test.lua`, versions dans `group_test.lua` (19 tests dans `run_all.sh`).
- v2.0.0 (17/11/2026) : « fusionne tout » — données des addons Forever, équipement complet, licence GPL v3.
  - `Itineraire/Donnees/` (nouveaux fichiers : relancer WoW) importés par `outils/donnees.py` (commits épinglés,
    SHA-256 vérifié, contrôle « rien d'exécutable ») dans `ns.ext` : `BUTINS` + `OBJETS` (Dropdon / All The Things, MIT),
    `ENTREES` (DonData, MIT), `RECETTES` (Guildon Crafts, GPL v3), `PNJ` + `MARCHANDISES` (Finddon, GPL v3 : CMaNGOS,
    ForeverDB.net). Mesure avant fusion : 1 152 des 2 587 objets de donjons/raids n'avaient aucune source dans Questie.
  - Licence GPL-3.0-or-later (`LICENSE`, `THIRD_PARTY.md`, copies `LICENCE.txt` / `TIERS.txt` dans l'addon).
  - Note des objets refaite d'après DonData/Questdon (MIT) : poids F/A/E/I/Es par classe, PA → DPS (14), armure en
    endurance de vie effective (H / (10 (A + 400 + 85 L))), armure et DPS lus dans la bulle (`C_TooltipInfo`) si
    `GetItemStats` ne les donne pas ; rôle par-dessus (tank, sorts, soins). `CanDualWield`, pas de 1M face à une 2M portée.
  - Récompense conseillée : plus AUCUN appel à l'interface de Blizzard (présélection retirée : la fenêtre de quête de
    Forever passe par des délégués sécurisés) ; cadre `ItineraireRewardMark` sur UIParent ancré au bouton
    `type == "choice"` de `QuestInfoRewardsFrame.RewardButtons` ; évaluation une image après `QUEST_COMPLETE`, reprise
    sur `ITEM_DATA_LOAD_RESULT` / `GET_ITEM_INFO_RECEIVED`, pas avant le niveau requis.
  - Recherche d'équipement : + butins des boss (donjons et raids de ton niveau, `GetItemInfoInstant` pour trier sans
    charger), + objets fabriqués (`GetProfessions` / `GetProfessionInfo` ; recettes apprises lues dans ta fenêtre de
    métier via `C_TradeSkillUI`), + vendeurs Finddon (les 8 plus proches de toi). Onglet « Donjons » (`Gear.DungeonRanking`)
    et « Y aller » vers l'entrée (`S:donjon<id>`).
  - Bulle des objets : `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item)` (sinon `OnTooltipSetItem`),
    pas dans les bulles de comparaison du jeu.
  - Quêtes que Questie ne place pas : `Data.QuestHint` = repère du jeu (`C_QuestLog.GetQuestsOnMap` sur la carte du
    joueur et ses parents, puis `GetNextWaypoint`), sinon `DonDataAPI` (ObjectivePoints, TurnInPoint) ; étape marquée
    « approximatif ». (Pas de vérification « la quête existe-t-elle » : sur Forever le serveur répond « non » à tort.)
  - Leveldon ajouté aux guides désactivés ; message unique si Questdon est installé (sa flèche et sa pièce d'or).
  - Nouveautés : toutes les versions sautées sont affichées. Rapport : ligne « Données reprises ».
  - Tests : `fusion_test.lua` (vraies données), 20 tests dans `run_all.sh`.
