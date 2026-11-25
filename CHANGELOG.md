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
- v2.0.1 (17/11/2026) : fluidité de la recherche d'équipement en jeu (positions des vendeurs Questie gardées le temps
  d'une recherche, positions des PNJ Finddon et listes d'entraîneurs par métier gardées) ; un joueur venant d'une
  version d'avant le suivi des versions voit toutes les nouveautés (1.9.0 et 2.0.0).
- v2.1.0 (17/11/2026) : « un autopilote comme sur Azeroth » — nouveau fichier `Pilote.lua` (relancer WoW).
  - Prise / rendu des quêtes repris de Questdon (MIT) : `C_GossipInfo.SelectActiveQuest` (finies d'abord) puis
    `SelectAvailableQuest` (pas répétables, pas grises si l'option, pas les « P:id » passées, journal pas plein),
    `QUEST_GREETING` (ancienne liste), `AcceptQuest` / `AcknowledgeAutoAcceptQuest`, `ConfirmAcceptQuest` (escortes),
    `CompleteQuest` (pas si `GetQuestMoneyToGet() > 0`), `GetQuestReward` si 0-1 choix ; plusieurs choix : option
    « reward » (coupée par défaut) = la récompense conseillée par Gear (`Pilote.OnRewardChoice`). Valeurs secrètes = « non ».
  - Dialogues utiles selon l'étape (`C_GossipInfo.GetOptions`, icône 132057 vol / 132058 maître / 132060 marchand).
  - Vols : destination = 1re étape « flight » de `ShortestPathForever.API.Journey()` (trajet d'Itinéraire seulement),
    nœud le plus proche (≤ 300 m) parmi `C_TaxiMap.GetAllTaxiNodes(GetTaxiMapID())` atteignables, `TakeTaxiNode`.
  - Cinématiques (`CinematicFrame_CancelCinematic`, `MovieFrame:StopMovie`), marchand (`RepairAllItems`, vente des gris
    un par un toutes les 0,15 s, MERCHANT_SHOW/CLOSED, on laisse faire Scrap/AutoVendor/Peddler/Leatrix/Questdon),
    maître de classe (`BuyTrainerService` des « available », de la fin vers le début).
  - Bouton sécurisé `ItineraireItemButton` (SecureActionButtonTemplate, type item, attributs hors combat seulement) :
    objet utilisable (`C_Item.GetItemSpell`) qui est un `requiredSourceItems` (Questie) des quêtes des 3 prochaines
    étapes, sinon un objet qui commence une quête ; raccourci `CLICK ItineraireItemButton:LeftButton`.
  - MAJ = la main au joueur ; `ADDON_ACTION_BLOCKED`/`FORBIDDEN` coupe la partie concernée pour la session ; Questie :
    prise/rendu automatiques coupés tant que le pilote le fait (`questiePrev` remis à l'arrêt). Bouton P, `/iti pilote`,
    raccourci, onglet « Pilote » (panneau élargi à 480), ligne « Pilote » dans le rapport.
  - Tests : `pilote_test.lua` (21 tests dans `run_all.sh`).
- v2.2.0 (17/11/2026) : « l'aspect graphique, que ce soit parfait » — refonte visuelle, sans nouveau fichier
  (un /reload suffit depuis la 2.1.0).
  - `UI.Skin` (dans UI.lua) : cadres plats (WHITE8X8, bordure 1 px du thème, liseré d'accent de 2 px), barre de titre
    avec icône et trait, boutons à icône (`IconButton`, `skinKey`, bordure verte = actif), boutons / onglets / choix
    plats (`Skin.Button` + `SetSelected`), barres de progression (`Skin.Bar`), traits de séparation. Style « Blizzard »
    (cadres d'infobulle du jeu) au choix : `ui.style`.
  - Fenêtre : icônes du jeu à la place des boutons rouges « P E ? Q R … », étape en cours soulignée (liseré + numéro et
    temps dorés), une ligne sur deux teintée, barre d'avancement des objectifs (`UI.StopProgress`), trait avant
    « À savoir ».
  - Bandeau : icône encadrée, barre d'avancement, « PILOTE », bordure verte sur place / orange en pause, s'allume à
    chaque nouvelle étape (animation Alpha).
  - Équipement : icône encadrée à la couleur de la qualité, petite icône de la source, onglets et boutons plats.
  - Réglages, assistant, rapport, menus : même habillage ; intitulés soulignés.
  - Bouton de l'objet de quête : raccourci affiché (`GetBindingKey`), bordure.
- v2.3.0 (20/11/2026) : DungeonJournal (ExehnTV, curseforge.com/wow/addons/dungeonjournal), avec l'accord de son
  auteur. Nouveau fichier `DungeonJournal.lua` (relancer WoW) ; rien de DungeonJournal n'est copié dans le dépôt.
  - `ns.DJ` lit `ForeverDungeonJournal_NS` en jeu (lecture seule, tout en pcall) : `DB[donjon]` (level « 13-20 »,
    entrance, bosses[].loot = { itemID, nom, emplacement, qualité }, quests[] = id, faction, requires, classOnly,
    profession, unavailable(Races), repeatable, startMap / turninMap / objectiveMap, startsInDungeon, rewardItems,
    additionalRewardItems), `QUEST_START_MAPS`, `questChainPage` (pages de chaîne : pas des donjons). Noms traduits
    par ses `Localize*`. Quêtes : `QuestCountsForCharacter`, `PrereqChainOf` + `QuestChainUnlocked`. Ouverture :
    `ForeverDungeonJournalFrame:Show()` puis `OpenQuestPage` / `OpenBossPage`.
  - `Data.Dungeons()` : ses donjons (id `dj:<clé>`) remplacent les entrées Dropdon qu'ils couvrent (ailes séparées ;
    alias Sunken Temple / Temple d'Atal'Hakkar, pic Rochenoire inférieur et supérieur) ; boss et objets de Dropdon
    qu'il n'a pas rangés dans son donjon (même créature ou nom, sinon l'aile, sinon le premier) ; raids inchangés ;
    boss d'un seul camp écartés ; `Data.DungeonAlias` reprend les objectifs « Donjon » enregistrés avant.
  - Équipement : étape « quêtes de donjon » (récompenses des quêtes faisables jusqu'à niveau + 3) ; source `dquest`
    (quête connue de lui seul, avec le lieu du donneur : « Y aller » = étape « Quête pour … », retirée dès que la quête
    est dans le journal), `later` (niveau ou quêtes préalables), `journal` ; butin des monstres / rares.
  - Objectif « Donjon » : quêtes du donjon à prendre avant (Questie : `wanted` ; sinon étape `djq<id>` chez le
    donneur, sans doublon avec un objectif d'équipement), quêtes du journal à faire dedans dans l'explication.
  - `Data.QuestHint` / `Data.TurnInGuess` : après le repère du jeu, DungeonJournal (turninMap, donneur = destinataire,
    rendu « inside » = entrée ; objectifs = objectiveMap ou entrée du donjon), puis DonData.
  - Fenêtre Équipement : clic droit « Ouvrir / Voir dans DungeonJournal », quêtes du donjon dans la bulle ; lecture des
    lignes par `rawget` (les champs remis à nil ne doivent pas tomber sur le cadre). `/iti dj [donjon]`, ligne
    « DungeonJournal » dans le rapport, version suivie dans les annonces de mise à jour.
  - Installateur v3 : DungeonJournal depuis CurseForge (liste des fichiers du projet 1707971, compte « exehntv »,
    version publiée ; redirections suivies à la main, hôtes www.curseforge.com / edge.forgecdn.net /
    mediafilez.forgecdn.net seulement ; taille exacte ; archive : un seul dossier, extensions d'addon, ≤ 600 Mo ;
    .toc « Title: DungeonJournal », « Author: Exehn », version = nom du fichier). Pas d'empreinte publiée par
    CurseForge : SHA-256 du fichier reçu noté dans le journal. Installé s'il manque (à la main), mis à jour s'il est là
    (aussi en `-Auto`) ; `-SansDungeonJournal`. `ns.INSTALLER_WANTED = 3`.
  - Tests : `dj_test.lua` (faux DungeonJournal à la forme de la 2.1.0 ; 22 tests dans `run_all.sh`) ; vérifié aussi
    hors dépôt avec les vraies données 2.1.0 (35 donjons, 391 quêtes, 2 880 butins ; chargées sans io/os).
- v2.3.1 (20/11/2026) : ForeverCore n'est plus livré à part par Shortest Path (1.43.9 : copie incluse dans
  `ShortestPathForever\Libs\ForeverCore`, 1.15.4). L'installateur 3 attendait encore un dossier `ForeverCore` dans
  l'archive (« Archive incomplete ») : Shortest Path était mis à jour mais l'ancien ForeverCore 1.15.1 installé à part
  restait, et son chargeur prévenait à la connexion (« ForeverCore 1.15.1 est plus ancien que le ForeverCore 1.15.4
  inclus dans vos addons »).
  - Installateur v4 : ForeverCore facultatif dans l'archive de Shortest Path (mis à jour s'il est déjà installé à
    part, installé seulement si un addon de l'archive l'exige) ; `Remove-StaleForeverCore` range dans
    `AddOns_sauvegardes` un ForeverCore à part plus ancien que la copie incluse la plus récente (numéro lu dans
    `Libs\ForeverCore\Begin.lua`, `ForeverCoreLoader.Begin(dossier, 1015004, …)`) si aucun `.toc` ne l'exige
    (`## Dependencies` / `RequiredDeps`). Ligne « ForeverCore a part / inclus » dans l'état. `ns.INSTALLER_WANTED = 4`.
  - Itinéraire s'inscrit au journal d'erreurs de ForeverCore via `ForeverCoreLoader.OnReady` quand le global
    `ForeverCore` n'existe pas encore (copie incluse publiée à la connexion) ; le rapport dit quelle copie tourne
    (`ForeverCoreLoader.Selected()`).
- v2.4.0 (20/11/2026) : « automatiser la prise de talents, l'équipement utilisé, etc. ». Nouveau fichier
  `Autonomie.lua` (`ns.Auto`, relancer WoW), réglé avec le pilote (`ns.db.pilote` : `talents` = « demander » / « auto »
  / « non », `talentPlan` = « auto » (rôle) ou clé de plan, `equip`, `equipBoE` = « demander » / « auto » / « non »,
  `bags`). Fenêtre de question à soi (pas de StaticPopup), une question à la fois, jamais en combat.
  - Talents de Forever = arbre C_Traits (pas l'API Classic, absente) : `C_ClassTalents.GetActiveConfigID`, arbre
    unique (`GetConfigInfo().treeIDs[1]`), onglets = groupes (`GetGroupDisplayInfoByTreeID`, triés par `orderIndex`),
    points par onglet (`GetGroupCurrencyInfo`, onglet absent = 0), points libres (`GetTreeCurrencyInfo`), nœuds
    (`GetNodeInfo` : `currentRank`, `maxRanks`, `canPurchaseRank`, `groupIDs`), sort du talent (`GetEntryInfo` →
    `GetDefinitionInfo().spellID`). Tous les points libres du plan sont préparés (`PurchaseRank`, rangs comptés par
    nous si le jeu ne les montre pas) puis appliqués en une incantation (`C_ClassTalents.CommitConfig`, sinon
    `C_Traits.CommitConfig`) seulement immobile et hors combat ; `CONFIG_COMMIT_FAILED` = `RollbackConfig` puis nouvel
    essai à l'arrêt ; rien si le joueur prépare des talents lui-même (`ConfigHasStagedChanges`). API Classic
    (`GetTalentInfo` / `LearnTalent`) gardée en secours. Sources : code Blizzard de Forever (branche `forever` de
    Gethe/wow-ui-source, 1.60.1.70959), notes publiques ForeverPlusPlus, addons Forever publiés.
  - Plans guerrier (Protection tank, Armes) écrits sur les arbres de Forever (ForeverDB, build 70959 : 11 talents
    nouveaux, 24 changés) ; un pas = un rang, reconnu par l'identifiant de son sort, puis son nom traduit, puis son nom
    anglais ; vérifiés hors jeu (51 points, paliers de 5 points, rangs max). C'est le jeu (`canPurchaseRank`) qui dit si
    un point est possible.
  - Rôle de la fenêtre Équipement : sur Forever `GetTalentTabInfo` n'existe pas, donc le rôle tombait toujours sur
    celui de la classe (guerrier = mêlée) ; il se lit maintenant dans les points par onglet (`Auto.TreePoints`, gardé
    2 s car appelé à chaque bulle).
  - Équipement : meilleur objet des sacs d'après `Gear.Evaluate` (≥ 2 points et ≥ 3 %, ou emplacement vide), un à la
    fois, hors combat / incantation / objet au curseur ; `C_Container.PickupContainerItem` + `EquipCursorItem` (le bon
    exemplaire), sinon `C_Item.EquipItemByName`. Lié quand équipé (type de lien 2, `isBound` faux) : question, puis
    `EquipPendingItem` sur `EQUIP_BIND_CONFIRM` / `AUTOEQUIP_BIND_CONFIRM`. Objet remis à la main (changement d'emplacement
    hors de nos 3 s) : laissé de côté pour la session. Objet porté à effet « Utiliser » : jamais remplacé tout seul.
  - Sacs : emplacement de sac libre + sac ordinaire (classe 1, sous-classe 0) des sacs : `PickupContainerItem` +
    `PutItemInBag`.
  - `Pilote` : clés bloquées par le jeu `LearnTalent`, `EquipItemByName`, `EquipCursorItem`, `EquipPendingItem`
    → talents / equip ; `PickupContainerItem`, `PutItemInBag` → bags ; rapport. `/iti talents`. Réglages : section
    « Talents, équipement, sacs » de l'onglet Pilote (`ChoiceFn`), panneau agrandi à 690.
  - Tests : `auto_test.lua` (API Classic factice : question, plan, combat, blocage ; équipement, lié quand équipé,
    objet remis, bijou à effet, sac) et `auto_traits_test.lua` (C_Traits factice : préparer + appliquer immobile,
    incantation interrompue, changements du joueur, rôle par onglet). 24 tests.
- v2.5.0 (20/11/2026) : « généralise les plans pour toutes les classes et tous les rôles » + « les barres d'action se
  remplissent seules ».
  - 28 plans de talents pour les 9 classes, chaque rôle de la fenêtre Équipement couvert (tank, melee, ranged, caster,
    healer) avec des variantes (`melee_fureur`, `ranged_precision`, `ranged_survie`, `melee_assassinat`,
    `melee_finesse`, `healer_discipline`, `caster_feu`, `caster_arcanes`, `caster_demonologie`, `caster_destruction`).
    Écrits sur les arbres de Forever 1.60.1 (ForeverDB, build 70959, effets nouveaux / changés compris) ; prérequis
    probables mis d'abord (les flèches ne sont pas publiées). `Plan(rôle, libellé, …)` ; plan par défaut = la clé du
    rôle ; ordre des choix : tank, mêlée, distance, sorts, soins. Réglages : bouton qui ouvre la liste des plans.
  - `outils/plans_talents.py` : vérifie tous les plans contre les pages de ForeverDB (51 points, sorts, noms, onglets,
    paliers de 5 points, rangs max, niveaux) ; rien n'est enregistré dans le dépôt.
  - Barres d'action : sorts actifs appris de la classe (`C_SpellBook` : ligne de compétence au nom de la classe,
    `GetSpellBookItemInfo` sans passifs, sans sorts futurs ni hors spé ; formes et postures écartées
    via `GetShapeshiftFormInfo`) posés dans les cases vides des barres affichées (`MultiBar*Button.action`, puis la
    barre principale si `GetBonusBarOffset() == 0`) par `C_Spell.PickupSpell` + `PlaceAction` ; rang supérieur
    (`C_ActionBar.IsHighestSpellRank`, sinon « Rang N ») posé à la place de l'ancien ; un sort posé puis enlevé par le
    joueur est noté (`ItineraireCharDB.actionbars.removed`) et ne revient plus ; hors combat, curseur vide ; réglage
    `actionbars`, clés bloquées `PlaceAction` / `PickupSpell`. Événements `SPELLS_CHANGED`,
    `LEARNED_SPELL_IN_SKILL_LINE` / `LEARNED_SPELL_IN_TAB` (enregistrés sous pcall).
  - Tests : `auto_bars_test.lua` (rang supérieur, cases vides de la barre affichée, posture, passif, sort futur,
    sort enlevé, combat, barre principale hors posture, blocage) ; `auto_test.lua` vérifie un plan par rôle pour
    chaque classe (28 plans de 51 points). 25 tests.
- v2.6.0 (20/11/2026) : barres rangées par posture (guerrier), bouton DungeonJournal, valeurs secrètes.
  - `Autonomie.lua`, table `LAYOUTS.WARRIOR` : 3 postures (sort, page `GetBonusBarOffset`), `only` = postures exigées
    (ForeverDB build 70959 ; un nombre = talent qui ajoute la posture : Charge en Défensive avec Avant-garde 1310317),
    `keys` = 12 touches × 3 postures, chaque case = liste de sorts de rang 1 (le premier connu, permis dans la posture,
    pas déjà sur la page ; sorts de bouclier seulement si bouclier porté ou rôle tank), `static` = ordre de la barre
    fixe (la première barre affichée en plus de la principale) pour les sorts absents d'une page où ils marchent.
    Case d'une touche : `(NUM_ACTIONBAR_PAGES + page - 1) * 12 + touche` (Combat 73-84, Défensive 85-96, Berserker
    97-108) ; refus si `ActionButton1.action` ne correspond pas (`PagingProblem`, dans le rapport).
  - `Auto.ArrangeBars(force)` : rangement complet (sorts de classe hors de place retirés, objets/macros/compagnons des
    touches voulues déplacés par `PickupAction` + `PlaceAction` vers une case vide affichée, sinon « garés » sur une
    touche libre de la page (`parked`), sinon la touche leur reste ; journal `actionbars.journal` rejoué à l'envers par
    `Auto.UndoBars`) ou entretien (cases à nous `owned` ; une case changée par le joueur devient `locked`, un sort
    enlevé de partout `removed` ; un sort d'attente à nous est remplacé ; un objet garé repart quand sa touche sert).
    Rangs supérieurs partout (`UpgradeRanks`, toutes les cases 1-180). Question unique (Ranger / Plus tard / Jamais),
    `/iti barres [ranger|annuler|non]`, bouton dans /iti reglages > Pilote, état dans `/iti rapport`.
    `outils/postures.py` revérifie `only` contre ForeverDB (39 sorts, 0 erreur).
  - Bouton « Journal des donjons » (barre de titre, clic droit = donjons du niveau) et raccourci `ITINERAIRE_DJ` :
    `DJ.CurrentKey` (instance via `GetInstanceInfo`, sinon 1re étape de donjon du trajet) ; `DJ.Find` cherche aussi
    dans l'autre sens (nom Questie plus long que celui de DungeonJournal) ; `/iti dj` sans nom fait pareil.
  - Corrigé : `Num` (Autonomie, Gear, Pilote, Data) refuse les valeurs « secrètes » de Forever (`issecretvalue` /
    `canaccessvalue`) : `UnitArmor` secret faisait planter `ArmorStamina` (Gear.lua:277, vu dans une vraie sauvegarde).
  - Tests : `auto_layout_test.lua` (rangement, objets déplacés, annulation exacte, Avant-garde, sort d'attente
    remplacé, case du joueur gardée, rangs, combat, refus de page) ; `dj_test.lua` (bouton, raccourci, menu). 26 tests.
- v2.7.0 (20/11/2026) : barres rangées pour le druide (par forme) et le voleur (camouflé ou non).
  - `LAYOUTS` généralisé : `pages` = { key, label, offset attendu, `form` (sorts de forme), `need`, `stealth`,
    `within` (page qui doit aussi correspondre), `always` (page 0 = cases 1-12), `optional` (page rangée seulement une
    fois vue), `transient` (ne compte pas pour la barre fixe), `keysFrom` / `usableAs` } ; `free` = pages d'un sort
    absent de `only` (druide : humanoïde et sélénien) ; `weapon` = « shield », « dagger », « dagger2 ».
  - Page vue en jeu : `Auto.ObservePage` (forme active via `GetShapeshiftFormInfo`, `IsStealthed`, `GetBonusBarOffset`)
    sur `UPDATE_SHAPESHIFT_FORM` / `UPDATE_BONUS_ACTIONBAR` / `UPDATE_STEALTH` → `actionbars.seen` ; une page vue avec
    la même case qu'une autre est ignorée (camouflage sans page à lui : ses techniques vont sur la barre fixe).
    Sélénien et « félin en rôdant » : optionnels (pages incertaines dans Classic). `PageSlot(0, k) = k`.
  - Druide (Forever) : Lucioles dans toutes les formes, Charge farouche en félin et en ours, Morsure primale et
    Lacérer en ours, soins en humanoïde seulement. Voleur : Coup bas, Embuscade, Garrot, Assommer, Vol à la tire en
    camouflage ; Préméditation sans camouflage (Forever) ; Camouflage (forme) pris à son rang réel.
  - Barre fixe : un sort sur aucune page, ou absent d'une page non passagère où il marche.
  - `outils/postures.py` vérifie les trois classes (123 sorts, 0 erreur) ; tests `auto_layout_druid_test.lua`,
    `auto_layout_rogue_test.lua` (faux jeu commun `layout_mock.lua`). 28 tests.
- v2.8.0 (21/11/2026) : barres rangées tout seul, trajet selon le niveau, installateur 5.
  - Barres : plus de question ; `AutoArrange` fait le rangement complet quand `actionbars.layout` n'est pas la
    version du rangement (et n'est pas « non ») ; versions passées à 2 pour le refaire une fois. Corrigé :
    `Auto.ClassSpells` ne lisait que l'onglet n° 2 du grimoire quand aucun ne porte le nom de la classe ; Forever
    (comme Classic) a un onglet par arbre de talents (Armes, Fureur, Protection) : vu dans une vraie sauvegarde
    (Vengeance déplacée comme un objet étranger, Cri de guerre absent). Tous les onglets après « Général » sont lus
    (sauf guilde, cachés, métiers). Forever : `IsPlayerSpell(rang 1)` est faux quand un rang supérieur est appris.
    Un objet sur une touche libre d'une page est « garé » après un rangement complet.
  - Trajet : `Data.ZONE_LEVELS` (41 zones, plages warcraft.wiki reprises de Shortest Path ; Reflet-de-Lune exclu),
    `Data.ZoneLevels` (repli `C_Map.GetMapLevels` pour une zone inconnue), `Data.ZoneDanger` (plus bas niveau ≥ le
    tien + 4, comme `avoidHighZones` de Shortest Path), `Data.SafePoints`. Planner : objectifs et rendus pris hors des
    zones trop hautes s'il y a le choix, sinon à la fin (`t.tier`/`t.late` pour un rendu seul, `stop.lateWhy`) ;
    quêtes à prendre, proposées, de donjon, marchands, maîtres et auberges : jamais dans une zone trop haute.
  - Installateur 5 : tâche planifiée lancée par `conhost.exe --headless` (aucune fenêtre) et SANS la condition
    « inutilisé 10 min » (elle ne passait presque jamais : vu le 21/11, aucune vérification depuis la veille) ;
    repli sur l'ancienne condition si Windows est trop ancien. `ns.INSTALLER_WANTED = 5`.
  - Tests : `zone_test.lua` ; `auto_layout_test.lua` avec un grimoire à onglets et la version 1 → 2. 29 tests.
- v3.0.0 (21/11/2026) : soirée planifiée, région suivante, frise jusqu'au 60, filons et forge, contrôle en jeu.
  - Soirée (`Planner.Soiree`, état `ItineraireCharDB.soiree` en heure réelle, survit à un /reload, oubliée 30 min
    après la fin) : valeur de chaque quête = XP (rendu + 70 % des monstres) ; coût = temps gagné à la retirer du
    trajet (`QuestValues`) ; voyage vers une zone (`ZoneEntries` : ce que le trajet gagne à n'y faire aucune étape,
    moins les temps des quêtes) payé une fois par un groupe de quêtes de la zone (`SelectSoiree`, glouton par XP/s,
    quête seule ou groupe d'une nouvelle zone). Niveaux de priorité : choisies 0, région suivante 0,55, auberge 0,6
    (`TIER_INN`, pas « libre » face au « plus tard »), gardées pour après 0,75, trop dures 1. Auberge = aubergiste le
    plus rapide depuis la dernière étape (4 comparés avec Shortest Path), ou la pierre de foyer si prête et plus
    rapide (son tronçon = l'incantation). Trop long : on recommence avec moins de temps (3 essais). Pas de conseil de
    pierre de foyer en route pendant une soirée. Bilan à l'arrivée à l'auberge ; quêtes rendues comptées.
  - `Build` : `Reroute` (quêtes proposées sauf celles que la soirée laisse, arrêts, étapes en plus) ; 4e passe région
    suivante + filons, 5e passe soirée ; chacune annulée proprement en cas d'erreur (`Optional`).
  - `Data.QuestIndex` (toute la base : `QuestieDB.QuestPointers` + `QueryQuestSingle` ; ni répétables, ni métier, ni
    donjon), construit en tâche de fond (`Montee.BuildIndex`). `Montee.Frise` : zone qui rapporte le plus à chaque
    niveau (XP réduite selon l'écart, pas de quête grise, pas de zone trop haute), trous comblés « monstres,
    donjons ». `Montee.NextRegionNeed` : journal presque fini (< 4 étapes ou < 20 min), région actuelle sans 3 quêtes
    à prendre, zone avec au moins 4 quêtes disponibles (Questie), point = plus gros groupe de donneurs.
  - Filons : 13 minerais (identifiants d'objets QuestieDB), couleurs Classic (orange < +25, jaune < +50, vert < +100),
    coins de 2 emplacements ou plus à moins de 75 s de détour (3 au plus), validés après 6 s sur place.
    Forge : recettes de Guildon Crafts qui font monter (couleur lue dans la fenêtre de forge si possible :
    `Gear.ReadRecipes` garde `recipeDiff`).
  - `Controle.lua` : 18 contrôles en jeu (lecture seule) + le rapport complet, dans la fenêtre à copier.
  - `MonteeUI.lua` : fenêtre « Ma montée » (frise, soirée, minage et forge). Boutons parchemin et « Zzz » dans la
    barre de titre (titre coupé si la fenêtre est étroite).
  - Tests : `soiree_test.lua`, `montee_test.lua`. 31 tests.
- v3.1.0 (22/11/2026) : trier mon journal (`/iti tri`, demandé : « abandonne toutes celles qui sont en dessous de
  mon niveau ou ne rapportent rien pour moi »).
  - `Tri.lua` (nouveau fichier) : `Tri.Analyse` = quêtes grises (niveau <= `GrayLevel` Classic), échouées, ou à moins
    de 1 % de ton niveau en XP (XP Questie pour ton niveau) ; gardées : quête suivie, classe (`requiredClasses`),
    métier (`requiredSkill`), récompense qui t'améliore (`Gear.PlanOptions().quests`), suite (`nextQuestInChain`) pas
    grise et pas faite. Grise terminée : proposée, pas cochée.
  - Abandon au 2e clic (6 s pour confirmer) : `C_QuestLog.SetSelectedQuest` + `SetAbandonQuest` + `AbandonQuest`
    (ancienne interface en repli), dans le clic du joueur ; journal relu 1,5 s après : refus du jeu signalé, la quête
    suivie jamais abandonnée. Rappel dans « À savoir » quand il y a des quêtes grises.
  - Le trajet, lui, n'écarte toujours rien tout seul. Test `tri_test.lua` (32 tests).
- v3.2.0 (22/11/2026) : vider mes sacs (`/iti sacs`, demandé : « vider mon inventaire de tout ce qui ne sert pas ou
  plus maintenant »).
  - `Sacs.lua` (nouveau fichier) : `Sacs.Analyse` lit les sacs 0 à `NUM_BAG_SLOTS` (`C_Container`) ; gardés : pierre de
    foyer et outils de métier (liste d'identifiants), objets de quête (`GetContainerItemQuestInfo`, classe 12),
    ensembles d'équipement, améliorations (`Gear.Evaluate` gain > 0, même pas encore portables), composants des
    recettes de TES métiers (Guildon Crafts), recettes de tes métiers, sacs. Cochés : gris, équipement lié moins bon,
    équipement que ta classe ne porte pas (lié ou blanc). Proposés non cochés : équipement pas lié vert ou mieux,
    équipement d'un autre rôle, consommables 15 niveaux sous toi, composants et recettes d'autres métiers.
  - Vente : `UseContainerItem` toutes les 0,2 s chez un marchand ouvert (le gris laissé au pilote s'il vend) ; sinon
    vente prévue (`Sacs.PendingCount` -> `opts.forceSell` -> arrêt « Vendre ce qui ne sert plus », même juste après
    un marchand) faite à `MERCHANT_SHOW` pour ce qui est toujours jugé inutile. Destruction au 2e clic,
    `PickupContainerItem` + `DeleteCursorItem`, seulement les objets sans valeur ; vérifiée 1 s après.
  - Test `sacs_test.lua` (33 tests).
- v3.2.1 (22/11/2026) : suivi des quêtes (retour en jeu : « le suivi des quêtes est devenu très mauvais », capture
  « Journal de Khazgorm : 0/1 » avec le journal dans les sacs, un équipier à 1/1).
  - `Data.ItemsInBags` : objectif « item » non fini dont l'objet (base Questie) est dans les sacs en nombre suffisant
    (`C_Item.GetItemCount`, sans la banque) et dont le nom est dans le texte de l'objectif. `Planner.Tasks` le tient
    pour fait (copie des objectifs, jamais les tables du jeu), la quête passe « à rendre » si c'était le dernier ;
    `plan.inBags` / `plan.bagSeen`. `Core` : annonce une fois par session, `ItineraireCharDB.inBags` (heure réelle),
    confiance au jeu après 20 min (`opts.bagGiveUp`), ligne dans `/iti rapport`.
  - Filons : plus l'argent, l'or, le vrai-argent sur le trajet (`rare`, `UsefulOres(rank, true)`) ; pause de 10 min
    après un coin visité ou passé (`ns.session.mineRest`, levée par « réafficher ») ; coin du calcul précédent gardé
    (`opts.prevMines` : détour toléré ×1,6, préféré de 40 s).
  - Test `suivi_test.lua` (34 tests).
- v3.3.0 (25/11/2026) : notre propre moteur (demandé : « reprendre tout ce que Questie fait avant qu'ils verrouillent »,
  issue Questie #8463 ; « que tout soit consolidé »).
  - `Moteur.lua` (nouveau fichier) : ne lit que la bibliothèque publique QuestieDB (`LibQuestieDB`, contrat 4 vérifié par
    `RequireContract`) ; mêmes formes que les modules de Questie qu'il remplace (`DB.GetQuest/GetNPC/GetObject/GetItem`,
    `Query*Single`, `*Pointers`, `Zone`, `XP`, `Avail.__availableQuests`) : logique adaptée de Questie (GPL v3) —
    `GetQuest` (ObjectiveData dans l'ordre de QuestieDB, `ObjectiveFirst`), `IsDoable` (race, classe, prérequis
    simples et groupés, réputation, métier et rang, quête parente, suite déjà faite, exclusives, sort, pistes,
    `availableUntilCompleted`/`availableStartingWith`), `IsLevelRequirementsFulfilled` (verte à ton niveau, niveau
    requis, niveau max), suites des quêtes du journal, `zoneDB` (tables de QuestieDB décodées), `QuestieXP` (règles
    cmangos), maîtres de classe de Forever, habitants des villes par drapeaux des PNJ. Liste recalculée en tâche de
    fond (4 ms par image) à la connexion et à chaque quête prise / rendue / abandonnée, niveau, métier, réputation.
  - `Donnees/Politique.lua` + `outils/politique_questie.py` : quêtes jamais proposées (blacklist de Questie évaluée
    pour Forever + événements saisonniers) et étiquettes corrigées, version et SHA-256 en tête.
  - `Data.lua` : `Data.Modules()` choisit le moteur interne (défaut, `ItineraireDB.moteur`), sinon Questie ; `Data.Engine()`.
    Objet acheté : positions de ses marchands de ta faction. `Geo.lua` : sans HereBeDragons, `C_Map.GetWorldPosFromMapPos`.
  - Filons : Questie vide leurs positions dans la base partagée (« GatheringNodeDisplayPolicy ») -> le moteur reprend
    celles d'origine (`Object.GetRaw`) : les étapes de minage existent enfin en jeu.
  - `.toc` : dépendance QuestieDB (Questie facultatif). `/iti moteur [interne|questie]`, `/iti controle` (moteur, et
    comparaison des quêtes disponibles avec Questie quand il est là), ligne « Moteur » dans `/iti rapport`.
  - Test `moteur_test.lua` (sans Questie du tout : règles de disponibilité, formes, zones, XP, habitants, filons, trajet).
