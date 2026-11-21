-- Itinéraire : équipement.
-- Note chaque objet pour ta classe et ton rôle (tank, mêlée, distance, sorts, soins), le compare à ce que tu portes,
-- conseille la récompense à prendre au rendu d'une quête, ajoute une ligne dans la bulle des objets, et cherche les
-- améliorations accessibles : récompenses de quêtes, vendeurs, butins de PNJ, de coffres et de boss de donjon,
-- objets que tes métiers fabriquent. Tout est calculé avec les vraies caractéristiques des objets (celles du jeu).
--
-- Le modèle de note reprend celui de DonData / Questdon (MIT, voir TIERS.txt), mis au point en jeu sur Forever :
-- poids des caractéristiques par classe (guides de montée de niveau), 14 puissance d'attaque = 1 DPS d'arme,
-- armure comptée comme l'endurance qu'elle vaut en vie effective, armure et DPS lus dans la bulle quand le jeu ne
-- les donne pas. Itinéraire y ajoute le rôle (tank : endurance, armure, défense, esquive, parade, blocage).
-- Leçons de Questdon sur Forever : ne rien appeler de l'interface de Blizzard (la fenêtre de quête passe par des
-- délégués sécurisés : un appel d'addon peut la « contaminer ») — donc aucun choix automatique de récompense, seulement
-- un cadre posé par-dessus.
local _, ns = ...
local Gear = {}
ns.Gear = Gear
local Data = ns.Data

local LOOKAHEAD = 3 -- objets jusqu'à 3 niveaux au-dessus du tien (à viser bientôt)
local LOOKBACK = 10 -- et jusqu'à 10 niveaux en dessous (un vieil objet peut encore t'améliorer)
local MAX_DROPPERS = 6 -- au-delà, c'est un butin « du monde » (aléatoire) : pas une piste
local MAX_VENDORS = 8
local MAX_OBJECTS = 4
local MAX_CANDIDATES = 4000
local PER_SLOT = 3 -- meilleures pistes gardées par emplacement (fenêtre Équipement)
local MIN_GAIN = 1 -- points de note
local SCAN_BUDGET_MS = 4
local SKILL_AHEAD = 25 -- recettes jusqu'à 25 points de compétence au-dessus de la tienne

-------------------------------------------------------------------------------
-- Emplacements
-------------------------------------------------------------------------------
local SLOTS_OF = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
Gear.SLOTS_OF = SLOTS_OF
local SLOT_NAMES = {
	[1] = "Tête", [2] = "Cou", [3] = "Épaules", [5] = "Torse", [6] = "Taille", [7] = "Jambes", [8] = "Pieds",
	[9] = "Poignets", [10] = "Mains", [11] = "Doigt", [12] = "Doigt", [13] = "Bijou", [14] = "Bijou", [15] = "Dos",
	[16] = "Main droite", [17] = "Main gauche", [18] = "À distance",
}
Gear.SLOT_NAMES = SLOT_NAMES
local ONE_HAND = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
	INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }

local function Call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n = pcall(fn, ...)
	if ok then
		return a, b, c, d, e, f, g, h, i, j, k, l, m, n
	end
	return nil
end

local function Num(v)
	if type(v) ~= "number" then
		return nil
	end
	-- Forever : une valeur « secrète » (combat, instance) a le type number mais refuse tout calcul
	local ok, secret = pcall(function()
		return (issecretvalue and issecretvalue(v)) or (canaccessvalue and not canaccessvalue(v)) or false
	end)
	if not ok or secret then
		return nil
	end
	return v
end

-------------------------------------------------------------------------------
-- Ta classe : ce qu'elle peut porter (jeu classique)
-------------------------------------------------------------------------------
-- Armures : 1 tissu, 2 cuir, 3 mailles, 4 plaques, 6 bouclier, 7 libram, 8 idole, 9 totem (0 = bijoux, cous,
-- anneaux : pour tous).
local ARMOR = {
	WARRIOR = { 1, 2, 3, 4, 6 }, PALADIN = { 1, 2, 3, 4, 6, 7 }, HUNTER = { 1, 2, 3 }, ROGUE = { 1, 2 },
	PRIEST = { 1 }, SHAMAN = { 1, 2, 3, 6, 9 }, MAGE = { 1 }, WARLOCK = { 1 }, DRUID = { 1, 2, 8 },
}
-- Plaques (guerrier, paladin) et mailles (chasseur, chaman) seulement à partir du niveau 40.
local ARMOR_LEVEL = {
	WARRIOR = { [4] = 40 }, PALADIN = { [4] = 40 }, HUNTER = { [3] = 40 }, SHAMAN = { [3] = 40 },
}
-- Armes : 0 hache 1M, 1 hache 2M, 2 arc, 3 fusil, 4 masse 1M, 5 masse 2M, 6 arme d'hast, 7 épée 1M, 8 épée 2M,
-- 10 bâton, 13 arme de pugilat, 15 dague, 16 armes de jet, 18 arbalète, 19 baguette.
local WEAPON = {
	WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }, PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
	HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }, ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
	PRIEST = { 4, 10, 15, 19 }, SHAMAN = { 0, 1, 4, 5, 10, 13, 15 }, MAGE = { 7, 10, 15, 19 },
	WARLOCK = { 7, 10, 15, 19 }, DRUID = { 4, 5, 10, 13, 15 },
}
local CLASS_IDS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }

local function Has(list, v)
	for _, x in ipairs(list or {}) do
		if x == v then
			return true
		end
	end
	return false
end

local function PlayerClass()
	if UnitClassBase then
		local token = Call(UnitClassBase, "player")
		if token then
			return token
		end
	end
	if UnitClass then
		local _, token = Call(UnitClass, "player")
		return token
	end
	return nil
end
Gear.PlayerClass = PlayerClass

local function Level()
	return Num(UnitLevel and Call(UnitLevel, "player")) or 1
end

-- classID / subclassID : ceux du jeu (2 = arme, 4 = armure). `level` : niveau auquel on le portera.
function Gear.CanWear(classID, subclassID, level)
	local class = PlayerClass()
	if classID == 4 then
		if subclassID == 0 then
			return true
		end
		local allowed = ARMOR[class]
		if not allowed then
			return true -- classe inconnue (nouveauté du jeu) : on ne retire rien
		end
		if not Has(allowed, subclassID) then
			return false
		end
		local need = ARMOR_LEVEL[class] and ARMOR_LEVEL[class][subclassID]
		return not need or (level or 1) >= need
	elseif classID == 2 then
		local allowed = WEAPON[class]
		if not allowed then
			return subclassID ~= 20 -- canne à pêche
		end
		return Has(allowed, subclassID)
	end
	return false
end

-------------------------------------------------------------------------------
-- Rôle et poids
-------------------------------------------------------------------------------
Gear.ROLES = {
	{ key = "auto", label = "Auto" },
	{ key = "tank", label = "Tank" },
	{ key = "melee", label = "Mêlée" },
	{ key = "ranged", label = "Distance" },
	{ key = "caster", label = "Sorts" },
	{ key = "healer", label = "Soins" },
}
local ROLE_LABEL = { tank = "tank", melee = "mêlée", ranged = "distance", caster = "lanceur de sorts", healer = "soigneur" }
Gear.ROLE_LABEL = ROLE_LABEL

-- Rôle d'après l'arbre de talents le plus rempli (par classe : arbre 1, 2, 3).
local TREE_ROLES = {
	WARRIOR = { "melee", "melee", "tank" }, PALADIN = { "healer", "tank", "melee" },
	DRUID = { "caster", "tank", "healer" }, SHAMAN = { "caster", "melee", "healer" },
	PRIEST = { "healer", "healer", "caster" }, HUNTER = { "ranged", "ranged", "ranged" },
	ROGUE = { "melee", "melee", "melee" }, MAGE = { "caster", "caster", "caster" },
	WARLOCK = { "caster", "caster", "caster" },
}
local CLASS_ROLE = {
	WARRIOR = "melee", PALADIN = "melee", SHAMAN = "melee", ROGUE = "melee", HUNTER = "ranged",
	DRUID = "caster", PRIEST = "caster", MAGE = "caster", WARLOCK = "caster",
}

-- Points dépensés dans l'arbre `tab` : sur Forever, les talents sont un arbre C_Traits (lu par Autonomie.lua) ;
-- sinon les deux formes de GetTalentTabInfo selon la version du jeu.
local function TreePoints(tab)
	local A = ns.Auto
	local okA, trees = false, nil
	if A and type(A.TreePoints) == "function" then
		okA, trees = pcall(A.TreePoints)
	end
	if okA and type(trees) == "table" and trees[tab] then
		return Num(trees[tab].points), trees[tab].name
	end
	if not GetTalentTabInfo then
		return nil, nil
	end
	local ok, a, b, c, _, e = pcall(GetTalentTabInfo, tab)
	if not ok then
		return nil, nil
	end
	if type(a) == "string" then
		return Num(c) or Num(e), a -- nom, icône, points, fichier
	end
	return Num(e) or Num(c), b -- id, nom, description, icône, points…
end

-- Rend le rôle et d'où il vient (« réglage », « talents Protection », « classe »).
function Gear.Role()
	local choice = ns.char and ns.char.gear and ns.char.gear.role
	if choice and choice ~= "auto" and ROLE_LABEL[choice] then
		return choice, "réglage"
	end
	local class = PlayerClass()
	local trees = TREE_ROLES[class]
	if trees then
		local best, bestPoints, bestName = nil, 0, nil
		for tab = 1, 3 do
			local points, name = TreePoints(tab)
			if points and points > bestPoints then
				best, bestPoints, bestName = tab, points, name
			end
		end
		if best then
			return trees[best], "talents " .. tostring(bestName or best)
		end
	end
	return CLASS_ROLE[class] or "melee", "classe"
end

-- Force, agilité, endurance, intelligence, esprit par classe pendant la montée de niveau (DonData / Questdon, d'après
-- les guides Icy Veins, Warcraft Tavern, Mobalytics, wow.gg).
local CLASS_WEIGHTS = {
	[1] = { 2, 1.5, 1.25, 0, 0.5 }, [2] = { 2, 1.25, 0.5, 0.75, 0.5 }, [3] = { 0, 2, 0.5, 1, 1.25 },
	[4] = { 1.5, 2, 0.75, 0, 0.75 }, [5] = { 0, 0, 1, 1.75, 1.5 }, [7] = { 2, 1.5, 0.5, 1, 0.25 },
	[8] = { 0, 0, 1, 2, 1.5 }, [9] = { 0, 0, 1.5, 1.75, 1.25 }, [11] = { 1.75, 1.75, 0.75, 0.25, 0.5 },
}
local ROLE_WEIGHTS = {
	tank = { 1, 1.25, 2.5, 0, 0.25 }, -- l'endurance d'abord
	caster = { 0, 0, 0.5, 1.75, 1.25 },
	healer = { 0, 0, 0.75, 1.75, 1.5 },
}
local AP_PER_STR = { [1] = 2, [2] = 2, [7] = 2, [11] = 2 } -- 1 pour les autres
-- Caractéristiques secondaires, en points par point (les % du jeu classique, « +1 % de critique », sont convertis :
-- au-delà de 5, c'est une valeur de « score » : ÷ 14).
local SECONDARY = {
	tank = { def = 2.5, dodge = 30, parry = 28, block = 15, blockv = 0.5, hit = 10, crit = 8, hp5 = 1.5 },
	melee = { hit = 25, crit = 25, haste = 20, hp5 = 0.5 },
	ranged = { hit = 25, crit = 25, haste = 20, mp5 = 1 },
	caster = { sp = 1.2, hit = 18, crit = 15, haste = 15, mp5 = 2.5 },
	healer = { heal = 0.9, sp = 0.9, crit = 12, mp5 = 3 },
}
local PERCENT = { hit = true, crit = true, dodge = true, parry = true, block = true, haste = true }
local SECONDARY_KEYS = {
	ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "def", ITEM_MOD_DODGE_RATING_SHORT = "dodge",
	ITEM_MOD_PARRY_RATING_SHORT = "parry", ITEM_MOD_BLOCK_RATING_SHORT = "block", ITEM_MOD_BLOCK_VALUE_SHORT = "blockv",
	ITEM_MOD_HIT_RATING_SHORT = "hit", ITEM_MOD_CRIT_RATING_SHORT = "crit", ITEM_MOD_HASTE_RATING_SHORT = "haste",
	ITEM_MOD_SPELL_POWER_SHORT = "sp", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal",
	ITEM_MOD_MANA_REGENERATION_SHORT = "mp5", ITEM_MOD_HEALTH_REGENERATION_SHORT = "hp5",
}
local PRIMARY_KEYS = { "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT",
	"ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT" }

-- Les poids du personnage pour un rôle : { prim = {5}, sec = {...}, ap, rap, class, role }.
local function Weights(role)
	local class = CLASS_IDS[PlayerClass() or ""] or (UnitClass and select(3, UnitClass("player"))) or 1
	local prim = ROLE_WEIGHTS[role] or CLASS_WEIGHTS[class] or CLASS_WEIGHTS[1]
	if role == "caster" and (class == 8 or class == 9 or class == 5) then
		prim = CLASS_WEIGHTS[class] -- mage, démoniste, prêtre : leurs poids de classe sont déjà ceux d'un lanceur
	end
	local str = prim[1] or 0
	return {
		prim = prim, sec = SECONDARY[role] or SECONDARY.melee, class = class, role = role,
		ap = str / (AP_PER_STR[class] or 1), -- 1 puissance d'attaque = (poids force) / (PA par point de force)
		rap = class == 3 and (prim[2] or 0) / 2 or 0, -- chasseur : 2 PA à distance par point d'agilité
	}
end

-- Ce que vaut 1 point d'armure en endurance pour toi maintenant : vie effective contre un monstre de ton niveau
-- (réduction = A / (A + 400 + 85 L) ; 1 endurance = 10 points de vie).
local function ArmorStamina()
	local level = Level()
	local health = Num(UnitHealthMax and Call(UnitHealthMax, "player"))
	local _, armor = Call(UnitArmor, "player")
	armor = Num(armor) or 0
	local L = level < 60 and level or level + 4.5 * (level - 59)
	local K = 400 + 85 * L
	if not health or health <= 0 then
		health = 20 * level + 40
	end
	return health / (10 * (armor + K))
end

-------------------------------------------------------------------------------
-- Infos d'objets (le jeu les charge à la demande)
-------------------------------------------------------------------------------
-- name, link, quality, itemLevel, reqLevel, equipLoc, texture, sellPrice, classID, subclassID (ou nil si pas
-- encore chargé)
function Gear.Info(item)
	local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local name, link, quality, ilvl, req, _, _, _, equipLoc, texture, sell, classID, subclassID = Call(fn, item)
	if type(name) ~= "string" then
		return nil
	end
	return {
		name = name, link = link, quality = quality or 1, ilvl = ilvl or 0, req = req or 0, equipLoc = equipLoc or "",
		texture = texture, sell = sell or 0, classID = classID, subclassID = subclassID,
	}
end

-- Sans attendre le serveur : emplacement, classe et sous-classe (base du jeu), ou nil.
function Gear.Instant(item)
	local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	local id, _, _, equipLoc, icon, classID, subclassID = Call(fn, item)
	if not id then
		return nil
	end
	return { id = id, equipLoc = equipLoc or "", icon = icon, classID = classID, subclassID = subclassID }
end

function Gear.RequestLoad(id)
	if C_Item and C_Item.RequestLoadItemDataByID then
		Call(C_Item.RequestLoadItemDataByID, id)
	else
		Gear.Info(id) -- l'ancien GetItemInfo demande l'objet au serveur tout seul
	end
end

-- Armure et DPS lus dans la bulle (quand GetItemStats ne les donne pas).
local ARMOR_PAT, DPS_PAT
local function Pattern(t)
	return "^" .. t:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%[sd]", "([%%d%%.,]+)") .. "$"
end
local function TipNumbers(link)
	local tip = C_TooltipInfo and C_TooltipInfo.GetHyperlink
	if type(tip) ~= "function" then
		return nil, nil
	end
	ARMOR_PAT = ARMOR_PAT or Pattern(type(ARMOR_TEMPLATE) == "string" and ARMOR_TEMPLATE or "%s Armor")
	DPS_PAT = DPS_PAT or Pattern(type(DPS_TEMPLATE) == "string" and DPS_TEMPLATE or "(%s damage per second)")
	local data = Call(tip, link)
	local armor, dps
	for _, line in ipairs(type(data) == "table" and type(data.lines) == "table" and data.lines or {}) do
		local txt = type(line) == "table" and line.leftText
		if type(txt) == "string" then
			local a = txt:match(ARMOR_PAT)
			if a then
				armor = tonumber((a:gsub("[,%. ]", "")))
			end
			local d = txt:match(DPS_PAT)
			if d then
				dps = tonumber((d:gsub(",", ".")))
			end
		end
	end
	return armor, dps
end

-- Caractéristiques d'un objet : table plate de nombres (gardée par lien : elles ne changent pas).
local statCache, statCount = {}, 0
local function Read(link, info)
	local cached = statCache[link]
	if cached then
		return cached
	end
	local fn = (C_Item and C_Item.GetItemStats) or GetItemStats
	local st = Call(fn, link)
	if type(st) ~= "table" then
		return nil -- pas encore chargé
	end
	local c = { prim = {}, sec = {} }
	for i, key in ipairs(PRIMARY_KEYS) do
		c.prim[i] = Num(st[key]) or 0
	end
	for key, short in pairs(SECONDARY_KEYS) do
		local v = Num(st[key])
		if v and v ~= 0 then
			c.sec[short] = (c.sec[short] or 0) + v
		end
	end
	c.ap = Num(st.ITEM_MOD_ATTACK_POWER_SHORT) or 0
	c.rap = Num(st.ITEM_MOD_RANGED_ATTACK_POWER_SHORT) or 0
	c.armor = Num(st.RESISTANCE0_NAME) or 0
	c.dps = Num(st.ITEM_MOD_DAMAGE_PER_SECOND_SHORT) or 0
	c.weapon = info and info.classID == 2 or false
	c.wand = c.weapon and info.subclassID == 19
	c.ranged = c.weapon and not c.wand and (info.subclassID == 2 or info.subclassID == 3 or info.subclassID == 18
		or info.equipLoc == "INVTYPE_RANGED" or info.equipLoc == "INVTYPE_RANGEDRIGHT") or false
	c.thrown = c.weapon and (info.subclassID == 16 or info.equipLoc == "INVTYPE_THROWN") or false
	if (c.armor == 0 and not c.weapon) or (c.weapon and c.dps == 0) then
		local a, d = TipNumbers(link)
		if c.armor == 0 and a then
			c.armor = a
		end
		if c.weapon and c.dps == 0 and d then
			c.dps = d
		end
	end
	if statCount >= 2000 then
		statCache, statCount = {}, 0
	end
	statCache[link], statCount = c, statCount + 1
	return c
end

-- Note d'un objet pour ton rôle (nil si ses caractéristiques ne sont pas encore chargées).
function Gear.Score(link, info, role)
	info = info or Gear.Info(link)
	if not info then
		return nil
	end
	local c = Read(link, info)
	if not c then
		return nil
	end
	local w = Weights(role or Gear.Role())
	local score = 0
	for i = 1, 5 do
		score = score + (w.prim[i] or 0) * (c.prim[i] or 0)
	end
	score = score + c.ap * (w.class == 3 and w.rap or w.ap) + c.rap * w.rap
	for stat, value in pairs(c.sec) do
		local weight = w.sec[stat] or 0
		if PERCENT[stat] and value > 5 then
			value = value / 14 -- une valeur de score, pas un %
		end
		score = score + weight * value
	end
	if c.weapon then
		if c.wand then
			score = score + ((w.role == "caster" or w.role == "healer") and 3 or 0) * c.dps
		elseif c.ranged or c.thrown then
			score = score + ((w.class == 3 and not c.thrown) and 14 * w.rap or 0) * c.dps
		else
			score = score + 14 * w.ap * c.dps * (w.role == "tank" and 0.5 or 1)
		end
	end
	score = score + c.armor * ArmorStamina() * (w.prim[3] or 0) * (w.role == "tank" and 1.5 or 1)
	return score
end

-------------------------------------------------------------------------------
-- Ce que tu portes
-------------------------------------------------------------------------------
local worn -- [slot] = { link, score, info }
local wornGen = 0

function Gear.ResetWorn()
	worn = nil
	wornGen = wornGen + 1
end

local function Worn(role)
	if worn and worn.role == role then
		return worn
	end
	local list = { role = role }
	for slot = 1, 18 do
		local link = GetInventoryItemLink and Call(GetInventoryItemLink, "player", slot)
		if link then
			local info = Gear.Info(link)
			local score = info and Gear.Score(link, info, role)
			list[slot] = { link = link, info = info, score = score or 0, pending = score == nil }
		end
	end
	worn = list
	return list
end
Gear.Worn = Worn

local function WornScore(list, slot)
	return list[slot] and list[slot].score or 0
end

local function DualWield(list)
	local can = rawget(_G, "CanDualWield")
	if type(can) == "function" then
		local ok, v = pcall(can)
		if ok and type(v) == "boolean" then
			return v
		end
	end
	local off = list[17] and list[17].info
	return off and (off.equipLoc == "INVTYPE_WEAPON" or off.equipLoc == "INVTYPE_WEAPONOFFHAND") or false
end

-- Évalue un objet face à ce que tu portes. Rend une table (gain, pct, slot…) ou nil + raison.
-- opts.now : il faut pouvoir le porter tout de suite (récompense de quête).
function Gear.Evaluate(item, opts)
	opts = opts or {}
	local info = Gear.Info(item)
	if not info then
		return nil, "pas chargé"
	end
	local slots = SLOTS_OF[info.equipLoc]
	if not slots then
		return nil, "pas un équipement"
	end
	local level = Level()
	if info.classID and not Gear.CanWear(info.classID, info.subclassID, math.max(level, info.req)) then
		return nil, "ta classe ne peut pas le porter"
	end
	if opts.now and info.req > level then
		return nil, "pas avant le niveau " .. info.req
	end
	local role = opts.role or Gear.Role()
	if role == "tank" and info.equipLoc == "INVTYPE_2HWEAPON" and Has(ARMOR[PlayerClass()] or {}, 6) then
		return nil, "arme à deux mains (un tank garde son bouclier)"
	end
	if info.equipLoc == "INVTYPE_SHIELD" and (role == "melee" or role == "ranged") then
		return nil, "bouclier (inutile pour ton rôle)"
	end
	local list = Worn(role)
	local main = list[16] and list[16].info
	if main and main.equipLoc == "INVTYPE_2HWEAPON" and ONE_HAND[info.equipLoc] and role ~= "tank" then
		return nil, "il faudrait lâcher ton arme à deux mains"
	end
	local score = Gear.Score(info.link, info, role)
	if not score then
		return nil, "pas chargé"
	end
	local slot, current = slots[1], WornScore(list, slots[1])
	local empty = not list[slot]
	if info.equipLoc == "INVTYPE_2HWEAPON" then
		current = WornScore(list, 16) + ((main and main.equipLoc == "INVTYPE_2HWEAPON") and 0 or WornScore(list, 17))
		empty = not list[16] and not list[17]
	elseif #slots == 2 then
		-- anneaux, bijoux : il remplace le plus faible (ou prend la place libre)
		if not list[slots[1]] then
			slot, current, empty = slots[1], 0, true
		elseif not list[slots[2]] then
			slot, current, empty = slots[2], 0, true
		else
			local a, b = WornScore(list, slots[1]), WornScore(list, slots[2])
			if b < a then
				slot, current = slots[2], b
			else
				current = a
			end
			empty = false
		end
	elseif info.equipLoc == "INVTYPE_WEAPON" and DualWield(list) and role ~= "tank" and role ~= "caster" and role ~= "healer" then
		local a, b = WornScore(list, 16), WornScore(list, 17)
		if not list[17] or b < a then
			slot, current, empty = 17, b, not list[17]
		end
	end
	local gain = score - current
	return {
		id = tonumber(tostring(info.link):match("item:(%d+)")), link = info.link, name = info.name,
		quality = info.quality, texture = info.texture, req = info.req, sell = info.sell, ilvl = info.ilvl,
		equipLoc = info.equipLoc, slot = slot, slotName = SLOT_NAMES[slot] or "?",
		score = score, current = current, gain = gain, empty = empty,
		pct = (not empty and current > 0) and (gain / current * 100) or nil, role = role,
	}
end

-- « +12 % » / « emplacement vide » / « +3 »
function Gear.GainText(e)
	if not e then
		return ""
	end
	if e.empty then
		return "emplacement vide"
	end
	if e.pct then
		return string.format("%+d %%", math.floor(e.pct + 0.5))
	end
	return string.format("%+d", math.floor(e.gain + 0.5))
end

local function Money(copper)
	copper = math.floor(copper or 0)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local parts = {}
	if g > 0 then
		parts[#parts + 1] = g .. " po"
	end
	if s > 0 then
		parts[#parts + 1] = s .. " pa"
	end
	if c > 0 or #parts == 0 then
		parts[#parts + 1] = c .. " pc"
	end
	return table.concat(parts, " ")
end
Gear.Money = Money

-------------------------------------------------------------------------------
-- Réglages (par personnage)
-------------------------------------------------------------------------------
function Gear.Config()
	if not ns.char then
		return { ignored = {}, goals = {}, dungeonGoals = {}, recipes = {}, skills = {}, role = "auto" }
	end
	if type(ns.char.gear) ~= "table" then
		ns.char.gear = {}
	end
	local g = ns.char.gear
	for _, key in ipairs({ "ignored", "goals", "dungeonGoals", "recipes", "skills" }) do
		g[key] = type(g[key]) == "table" and g[key] or {}
	end
	g.role = g.role or "auto"
	g.preselect = nil -- (1.9.0) plus de présélection : elle pouvait gêner la fenêtre de quête de Forever
	return g
end

-------------------------------------------------------------------------------
-- Récompense conseillée au rendu d'une quête (cadre vert par-dessus le bouton, rien d'autre)
-------------------------------------------------------------------------------
local mark
local rewardOpen, rewardPending = false, false
local lastAdviceKey

-- Le bouton du choix `index`, sans rien appeler de Blizzard qui modifie quoi que ce soit (lecture seule).
local function ChoiceButton(index)
	local frame = rawget(_G, "QuestInfoRewardsFrame")
	if frame and type(frame.RewardButtons) == "table" then
		for _, button in ipairs(frame.RewardButtons) do
			local okId, id = pcall(button.GetID, button)
			local okShown, shown = pcall(button.IsShown, button)
			if button.type == "choice" and okId and id == index and okShown and shown then
				return button
			end
		end
	end
	local button = rawget(_G, "QuestInfoRewardsFrameQuestInfoItem" .. index)
	if button and button.IsShown and Call(button.IsShown, button) then
		return button
	end
	return nil
end
Gear.ChoiceButton = ChoiceButton

local function ShowMark(button)
	if not button then
		return
	end
	if not mark then
		mark = CreateFrame("Frame", "ItineraireRewardMark", UIParent)
		mark:SetFrameStrata("DIALOG")
		mark.glow = mark:CreateTexture(nil, "ARTWORK")
		mark.glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
		mark.glow:SetBlendMode("ADD")
		mark.glow:SetVertexColor(0.3, 1, 0.4, 0.85)
		mark.glow:SetAllPoints()
		mark.label = mark:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		mark.label:SetPoint("BOTTOMRIGHT", mark, "BOTTOMRIGHT", -6, 4)
		mark.label:SetText("|cff00ff00Conseillé|r")
	end
	mark:ClearAllPoints()
	mark:SetPoint("TOPLEFT", button, "TOPLEFT", -4, 4)
	mark:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 4, -4)
	mark.button = button
	mark:Show()
end

function Gear.HideMark()
	if mark then
		mark:Hide()
		mark.button = nil
	end
end

-- Choix entre plusieurs récompenses : la meilleure amélioration portable maintenant, sinon la plus chère à revendre.
-- Rend { index, item, upgrade } ou nil si les objets ne sont pas encore chargés.
function Gear.BestReward(links, counts)
	local entries = {}
	local best, bestGain, cash, cashValue = nil, MIN_GAIN, nil, -1
	for i, link in ipairs(links) do
		local info = Gear.Info(link)
		if not info then
			return nil
		end
		local e = Gear.Evaluate(link, { now = true })
		if e and e.gain >= bestGain then
			best, bestGain = i, e.gain
		end
		local value = (info.sell or 0) * ((counts and counts[i]) or 1)
		if value > cashValue then
			cash, cashValue = i, value
		end
		entries[i] = { link = link, entry = e, info = info, value = value }
	end
	if best then
		return { index = best, item = entries[best], upgrade = true }
	end
	return cash and { index = cash, item = entries[cash], upgrade = false } or nil
end

local function Advise()
	if not rewardOpen then
		return
	end
	local cfg = Gear.Config()
	if cfg.rewardAdvice == false then
		return
	end
	local n = Num(GetNumQuestChoices and Call(GetNumQuestChoices)) or 0
	if n < 2 then
		return
	end
	local links, counts = {}, {}
	for i = 1, n do
		local link = GetQuestItemLink and Call(GetQuestItemLink, "choice", i)
		local _, _, count = Call(GetQuestItemInfo, "choice", i)
		if type(link) ~= "string" then
			rewardPending = true
			return -- on réessaie à l'arrivée des données (ITEM_DATA_LOAD_RESULT / GET_ITEM_INFO_RECEIVED)
		end
		links[i], counts[i] = link, Num(count) or 1
	end
	local choice = Gear.BestReward(links, counts)
	if not choice then
		rewardPending = true
		for _, link in ipairs(links) do
			Gear.RequestLoad(tonumber(link:match("item:(%d+)")))
		end
		return
	end
	rewardPending = false
	ShowMark(ChoiceButton(choice.index))
	local quest = GetQuestID and Call(GetQuestID)
	local key = tostring(quest) .. ":" .. choice.index .. ":" .. tostring(choice.item.link)
	if key == lastAdviceKey then
		return -- déjà dit pour cette fenêtre
	end
	lastAdviceKey = key
	if ns.Pilote and ns.Pilote.OnRewardChoice then
		pcall(ns.Pilote.OnRewardChoice, choice) -- (pilote : prendre la récompense conseillée, si l'option est active)
	end
	local item = choice.item
	if choice.upgrade then
		local e = item.entry
		ns.Print("récompense conseillée : " .. item.link .. " |cff00ff00" .. Gear.GainText(e) .. "|r (" .. e.slotName
			.. ", pour ton rôle " .. (ROLE_LABEL[e.role] or e.role) .. ").")
	else
		ns.Print("aucune récompense ne t'améliore : prends " .. item.link .. " (se revend " .. Money(item.value) .. ").")
	end
	Gear.lastAdvice = { at = time and time() or 0, link = item.link, upgrade = choice.upgrade }
end
Gear.Advise = Advise

function Gear.OnQuestComplete()
	rewardOpen, rewardPending = true, false
	C_Timer.After(0, Advise) -- une image plus tard : le jeu a placé les boutons
end

function Gear.OnQuestFinished()
	rewardOpen, rewardPending, lastAdviceKey = false, false, nil
	Gear.HideMark()
end

function Gear.OnItemData()
	if rewardOpen and rewardPending then
		rewardPending = false
		C_Timer.After(0.1, Advise)
	end
end

-------------------------------------------------------------------------------
-- Tes métiers (compétences et recettes connues)
-------------------------------------------------------------------------------
local PROF_NAMES = {
	[164] = "Forge", [165] = "Travail du cuir", [197] = "Couture", [202] = "Ingénierie", [171] = "Alchimie",
	[333] = "Enchantement", [185] = "Cuisine", [129] = "Secourisme", [186] = "Minage", [182] = "Herboristerie",
	[393] = "Dépeçage", [356] = "Pêche",
}
local PROF_CODE = { [171] = "a", [164] = "b", [185] = "c", [333] = "e", [202] = "g", [129] = "f", [356] = "i",
	[182] = "h", [165] = "l", [186] = "m", [393] = "s", [197] = "t" }
Gear.PROF_NAMES = PROF_NAMES

-- Compétences : GetProfessions / GetProfessionInfo (Forever). Rend { [ligne] = { rank, max, name } }.
function Gear.ReadProfessions()
	local cfg = Gear.Config()
	if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then
		return cfg.skills
	end
	local idx = { pcall(GetProfessions) }
	if not idx[1] then
		return cfg.skills
	end
	local skills = {}
	for i = 2, 7 do
		local k = idx[i]
		if k then
			local name, _, rank, max, _, _, line = Call(GetProfessionInfo, k)
			line = Num(line)
			if line and PROF_NAMES[line] then
				skills[line] = { rank = Num(rank) or 0, max = Num(max) or 0, name = type(name) == "string" and name or nil }
			end
		end
	end
	cfg.skills = skills
	return skills
end

-- Recettes apprises : lues dans TA fenêtre de métier ouverte (C_TradeSkillUI, Forever).
function Gear.ReadRecipes()
	local T = C_TradeSkillUI
	if type(T) ~= "table" or type(T.GetAllRecipeIDs) ~= "function" then
		return false
	end
	if Call(T.IsTradeSkillLinked) or Call(T.IsTradeSkillGuild) or Call(T.IsNPCCrafting) then
		return false -- la fenêtre de quelqu'un d'autre
	end
	local ids = Call(T.GetAllRecipeIDs)
	if type(ids) ~= "table" then
		return false
	end
	local cfg = Gear.Config()
	local n = 0
	-- Couleur de chaque recette (orange, jaune, vert, gris) : le plan de forge de « Ma montée » s'en sert.
	cfg.recipeDiff = type(cfg.recipeDiff) == "table" and cfg.recipeDiff or {}
	for _, id in ipairs(ids) do
		local r = Call(T.GetRecipeInfo, id)
		if type(r) == "table" and r.learned == true then
			cfg.recipes[id] = true
			n = n + 1
			local diff = r.relativeDifficulty
			if diff == nil then
				diff = r.difficulty
			end
			if type(diff) == "number" or type(diff) == "string" then
				cfg.recipeDiff[id] = diff
			end
		end
	end
	cfg.recipesAt = time and time() or 0
	Gear.ReadProfessions()
	return n > 0
end

local function ProfName(line)
	local s = Gear.Config().skills[line]
	return s and s.name or PROF_NAMES[line] or ("métier " .. tostring(line))
end

-------------------------------------------------------------------------------
-- Sources d'un objet
-------------------------------------------------------------------------------
-- (dquest : quête de donjon connue de DungeonJournal seulement, avec le lieu où la prendre)
local SOURCE_RANK = { journal = 1, craft = 2, vendor = 3, quest = 4, dquest = 4, recipe = 5, drop = 6, dungeon = 7, object = 8,
	later = 9 }
Gear.SOURCE_RANK = SOURCE_RANK

local function ZoneOf(points)
	local p = points and points[1]
	return p and ns.Geo.ZoneName(p.map) or nil
end

local function Count(list)
	return type(list) == "table" and #list or 0
end

-- Quêtes du journal (id -> true), lues dans le jeu.
function Gear.LogSet()
	local set = {}
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then
		return set
	end
	for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and info.questID then
			set[info.questID] = true
		end
	end
	return set
end

-- Positions des PNJ de Questie, gardées le temps d'une recherche (un même vendeur sert pour beaucoup d'objets).
local npcCache = {}
local trainerCache = {} -- [code du métier] = positions des entraîneurs amicaux
local function QuestiePlaces(npcId)
	local c = npcCache[npcId]
	if not c then
		local points, npc, meta = Data.NpcPlaces(npcId, 60)
		c = { points = points, npc = npc, meta = meta }
		npcCache[npcId] = c
	end
	return c.points, c.npc, c.meta
end

-- Vendeurs (Questie, puis Finddon) d'un objet, les plus proches de toi d'abord (MAX_VENDORS au plus).
local function VendorSources(id, questieVendors, out)
	local found, seen = {}, {}
	local me = ns.Geo.Player()
	local function Add(npcId, name, points)
		seen[npcId] = true
		local best = math.huge
		for _, p in ipairs(points) do
			local d = ns.Geo.Yards(me, p)
			if d and d < best then
				best = d
			end
		end
		found[#found + 1] = { kind = "vendor", npc = npcId, name = name, points = points, d = best,
			text = "vendu par " .. tostring(name) .. (ZoneOf(points) and (" (" .. ZoneOf(points) .. ")") or "") }
	end
	for _, npcId in ipairs(type(questieVendors) == "table" and questieVendors or {}) do
		if not seen[npcId] then
			local points, npc = QuestiePlaces(npcId)
			if npc and npc.friendly ~= false and #points > 0 then
				Add(npcId, npc.name, points)
			end
		end
	end
	for _, npcId in ipairs(Data.ExtVendors(id) or {}) do
		if not seen[npcId] then
			local npc = Data.ExtNpc(npcId)
			local points = npc and Data.ExtNpcFriendly(npc) and Data.ExtNpcPlaces(npc, 60) or {}
			if #points > 0 then
				Add(npcId, npc.name, points)
			end
		end
	end
	table.sort(found, function(a, b)
		if a.d ~= b.d then
			return a.d < b.d
		end
		return a.npc < b.npc
	end)
	for k = 1, math.min(#found, MAX_VENDORS) do
		out[#out + 1] = found[k]
	end
	return out
end

local function QuestSources(fields, inLog, out)
	for _, qid in ipairs(type(fields.questRewards) == "table" and fields.questRewards or {}) do
		if inLog[qid] then
			local q = Data.Quest(qid)
			out[#out + 1] = { kind = "journal", quest = qid, name = q and q.name or ("#" .. qid), text = "récompense de « "
				.. (q and q.name or qid) .. " » (dans ton journal)" }
		elseif not Data.Completed(qid) then
			local q = Data.Quest(qid)
			if q and Data.CanTake(qid, q, inLog) then
				local available = Data.AvailableQuests()[qid]
				local starts = available and Data.StarterPoints(q) or {}
				out[#out + 1] = {
					kind = available and #starts > 0 and "quest" or "later", quest = qid, name = q.name, points = starts,
					text = available and ("récompense de « " .. q.name .. " » (à prendre" .. (starts[1] and starts[1].name
						and (" chez " .. starts[1].name) or "") .. (ZoneOf(starts) and (", " .. ZoneOf(starts)) or "") .. ")")
						or ("récompense de « " .. q.name .. " » (plus tard : quête pas encore disponible)"),
				}
			end
		end
	end
end

local function DropSources(fields, out)
	local droppers = type(fields.npcDrops) == "table" and fields.npcDrops or {}
	if #droppers >= 1 and #droppers <= MAX_DROPPERS then
		for _, npcId in ipairs(droppers) do
			local points, npc, meta = QuestiePlaces(npcId)
			if npc then
				local dungeon = next(meta.dungeons)
				if dungeon then
					local entrance = Data.DungeonEntrance(dungeon)
					out[#out + 1] = { kind = "dungeon", npc = npcId, name = npc.name, dungeonName = Data.DungeonName(dungeon),
						points = entrance and { entrance } or {},
						text = "butin de " .. tostring(npc.name) .. " (donjon " .. Data.DungeonName(dungeon) .. ")" }
				elseif #points > 0 and npc.friendly ~= true then
					out[#out + 1] = { kind = "drop", npc = npcId, name = npc.name, points = points,
						level = npc.maxLevel or npc.minLevel, rank = npc.rank,
						text = "butin de " .. tostring(npc.name) .. (ZoneOf(points) and (" (" .. ZoneOf(points) .. ")") or "") }
				end
			end
		end
	end
	local objects = type(fields.objectDrops) == "table" and fields.objectDrops or {}
	if #objects >= 1 and #objects <= MAX_OBJECTS then
		for _, objId in ipairs(objects) do
			local points, object = Data.ObjectPlaces(objId, 60)
			if object and #points > 0 then
				out[#out + 1] = { kind = "object", object = objId, name = object.name, points = points,
					text = "dans " .. tostring(object.name) .. (ZoneOf(points) and (" (" .. ZoneOf(points) .. ")") or "") }
			end
		end
	end
end

-- Butin d'un boss de donjon (DungeonJournal, ou données Dropdon / All The Things).
local function BossSource(d, boss)
	local name = Data.BossName(boss)
	local where = (d.raid and "raid " or "donjon ") .. d.name .. ", niv " .. d.min .. "-" .. d.max
	local text = boss.trash and ("butin des monstres (" .. where .. ")")
		or ("butin de " .. name .. (boss.rare and " (rare, " or " (") .. where .. ")")
	return { kind = "dungeon", dungeon = d.id, dungeonName = d.name, name = boss.trash and "monstres" or name, raid = d.raid,
		points = d.entrance and { d.entrance } or {}, dj = boss.dj and d.dj or nil, djBoss = boss.dj and boss.djIndex or nil,
		text = text }
end

-- Récompenses des quêtes de donjon de DungeonJournal (c.djQuests) que Questie ne range pas déjà dans les
-- récompenses de l'objet : dans ton journal, à prendre maintenant (avec le lieu), ou plus tard.
local function DJQuestSources(c, inLog, out)
	local DJ = ns.DJ
	if not (c.djQuests and DJ and DJ.NS and DJ.NS()) then
		return
	end
	local known = {}
	for _, qid in ipairs(type(c.fields.questRewards) == "table" and c.fields.questRewards or {}) do
		known[qid] = true
	end
	for _, e in ipairs(c.djQuests) do
		local q, key = e.q, e.key
		if not known[q.id] then
			known[q.id] = true
			local name = DJ.QuestName(q)
			local where = DJ.DungeonName(key)
			local state, req = DJ.QuestState(q, inLog)
			if state == "log" then
				out[#out + 1] = { kind = "journal", quest = q.id, name = name, dj = key,
					text = "récompense de « " .. name .. " » (dans ton journal ; " .. where .. ")" }
			elseif state == "maintenant" then
				local questie = Data.Quest(q.id)
				local available = questie and Data.CanTake(q.id, questie, inLog) and Data.AvailableQuests()[q.id]
				local starts = available and Data.StarterPoints(questie) or {}
				if #starts > 0 then
					out[#out + 1] = { kind = "quest", quest = q.id, name = name, points = starts, dj = key,
						text = "récompense de « " .. name .. " » (à prendre" .. (starts[1].name and (" chez " .. starts[1].name) or "")
							.. (ZoneOf(starts) and (", " .. ZoneOf(starts)) or "") .. " ; " .. where .. ")" }
				else
					local p = DJ.StartPoint(q, key)
					local zone = p and ZoneOf({ p })
					local at = p and ((p.name and (" chez " .. p.name) or "") .. (zone and ((p.name and ", " or " : ") .. zone) or ""))
					if at == "" then
						at = nil
					end
					out[#out + 1] = { kind = p and "dquest" or "later", quest = q.id, name = name, points = p and { p } or {}, dj = key,
						text = "récompense de « " .. name .. " » (" .. where .. " ; à prendre"
							.. (at or (" : " .. tostring(DJ.Text(q.pickup) or "lieu inconnu"))) .. ")" }
				end
			elseif state == "plus tard" or state == "chaîne" then
				out[#out + 1] = { kind = "later", quest = q.id, name = name, dj = key,
					text = "récompense de « " .. name .. " » (" .. where .. " ; plus tard : "
						.. (state == "chaîne" and "quêtes préalables à finir" or ("niveau " .. tostring(req))) .. ")" }
			end
		end
	end
end

-- Fabrication (recettes de Guildon Crafts) : rend la source ou nil.
local function CraftSource(r, spell)
	local cfg = Gear.Config()
	local line, minSkill, src, recipeItem = r[1], tonumber(r[2]) or 0, r[3], tonumber(r[4]) or 0
	local skill = cfg.skills[line]
	if not skill then
		return nil
	end
	local prof = ProfName(line)
	local short = skill.rank < minSkill and (" (compétence " .. minSkill .. " requise, tu as " .. skill.rank .. ")") or ""
	if cfg.recipes[spell] then
		return { kind = "craft", spell = spell, prof = line, minSkill = minSkill, reagents = r[7],
			text = "à fabriquer : " .. prof .. " (tu connais la recette)" .. short }
	end
	if src == "t" then
		local code = PROF_CODE[line]
		local trainers = code and trainerCache[code]
		if code and not trainers then
			trainers = {}
			for _, npc in ipairs(Data.ExtNpcsWithRole("P" .. code)) do
				for _, p in ipairs(Data.ExtNpcPlaces(npc)) do
					trainers[#trainers + 1] = p
				end
			end
			trainerCache[code] = trainers
		end
		trainers = trainers or {}
		return { kind = "recipe", spell = spell, prof = line, minSkill = minSkill, reagents = r[7], points = trainers,
			text = prof .. " : recette chez ton entraîneur (compétence " .. minSkill .. ")" .. short }
	end
	if src == "i" and recipeItem > 0 then
		local out = VendorSources(recipeItem, Data.ItemField(recipeItem, "vendors"), {})
		local info = Gear.Info(recipeItem)
		local rname = info and info.name or (Data.ItemFallback(recipeItem) or {}).name or ("objet " .. recipeItem)
		local seller = out[1]
		return { kind = "recipe", spell = spell, prof = line, minSkill = minSkill, reagents = r[7], recipeItem = recipeItem,
			points = seller and seller.points or {},
			text = prof .. " : recette « " .. rname .. " »" .. (seller and (" " .. seller.text) or " (butin ou rare)") .. short }
	end
	return nil
end

local function SortSources(out)
	table.sort(out, function(a, b)
		return (SOURCE_RANK[a.kind] or 9) < (SOURCE_RANK[b.kind] or 9)
	end)
	return out
end

-------------------------------------------------------------------------------
-- Recherche des améliorations (en tâche de fond)
-------------------------------------------------------------------------------
Gear.state = { phase = "idle", done = 0, total = 0 }
Gear.results = nil

local job
local runner = CreateFrame("Frame")
runner:Hide()
local deadline = 0
local function Yield()
	if coroutine.running() and debugprofilestop() > deadline then
		coroutine.yield()
	end
end

runner:SetScript("OnUpdate", function(self)
	if not job then
		self:Hide()
		return
	end
	deadline = debugprofilestop() + SCAN_BUDGET_MS
	local ok, err = coroutine.resume(job)
	if not ok then
		job = nil
		self:Hide()
		Gear.state.phase = "erreur"
		Gear.state.error = tostring(err)
		if ns.OnError then
			ns.OnError("équipement : " .. tostring(err))
		end
	elseif coroutine.status(job) == "dead" then
		job = nil
		self:Hide()
	end
end)

local FIELDS = { "requiredLevel", "subClass", "questRewards", "vendors", "npcDrops", "objectDrops", "itemLevel" }

local function InWindow(req, ilvl, level)
	req, ilvl = tonumber(req) or 0, tonumber(ilvl) or 0
	if req == 0 then
		return ilvl == 0 or (ilvl >= level - 5 and ilvl <= level + LOOKAHEAD + 2)
	end
	return req <= level + LOOKAHEAD and req >= level - LOOKBACK
end

local function Scan(yield)
	local state = Gear.state
	local level = Level()
	local role = Gear.Role()
	local cfg = Gear.Config()
	Gear.ReadProfessions()
	npcCache, trainerCache = {}, {}
	local candidates, byId = {}, {}
	local function Add(id, fields)
		local c = byId[id]
		if not c then
			if #candidates >= MAX_CANDIDATES or cfg.ignored[id] then
				return nil
			end
			c = { id = id, fields = fields or {}, extra = {} }
			byId[id] = c
			candidates[#candidates + 1] = c
		elseif fields then
			c.fields = fields
		end
		return c
	end

	-- 1. La base de Questie : l'équipement de ton niveau, que ta classe peut porter, avec une source précise.
	state.phase, state.done, state.total = "base", 0, 0
	local ids = Data.ItemIds() or {}
	for _ in pairs(ids) do
		state.total = state.total + 1
	end
	for id in pairs(ids) do
		state.done = state.done + 1
		yield()
		local class = Data.ItemField(id, "class")
		-- (champ par champ : on ne lit les sources que des objets qui passent les premiers filtres)
		if (class == 2 or class == 4) and not cfg.ignored[id] then
			local req = tonumber(Data.ItemField(id, "requiredLevel")) or 0
			local ilvl = req == 0 and tonumber(Data.ItemField(id, "itemLevel")) or 0
			if InWindow(req, ilvl, level) then
				local sub = Data.ItemField(id, "subClass")
				if Gear.CanWear(class, sub, math.max(level, req)) then
					local fields = { subClass = sub, requiredLevel = req }
					for _, key in ipairs(FIELDS) do
						if fields[key] == nil then
							fields[key] = Data.ItemField(id, key)
						end
					end
					local useful = Count(fields.questRewards) > 0 or Count(fields.vendors) >= 1
						or (Count(fields.npcDrops) >= 1 and Count(fields.npcDrops) <= MAX_DROPPERS)
						or (Count(fields.objectDrops) >= 1 and Count(fields.objectDrops) <= MAX_OBJECTS)
					if useful then
						Add(id, fields)
					end
				end
			end
		end
	end

	-- 2. Butins des donjons et raids de ton niveau (Dropdon / All The Things) : Questie n'en connaît qu'une partie.
	state.phase = "donjons"
	for _, d in ipairs(Data.Dungeons()) do
		if d.min <= level + LOOKAHEAD and d.max >= level - 6 then
			for _, boss in ipairs(d.bosses) do
				for _, id in ipairs(type(boss.items) == "table" and boss.items or {}) do
					local inst = Gear.Instant(id)
					if inst and SLOTS_OF[inst.equipLoc] and Gear.CanWear(inst.classID, inst.subclassID, level + LOOKAHEAD) then
						local c = Add(id)
						if c then
							c.extra[#c.extra + 1] = BossSource(d, boss)
						end
					end
				end
				yield()
			end
		end
	end

	-- 2 bis. Récompenses des quêtes de donjon de DungeonJournal (s'il est chargé), quêtes faisables à ton niveau.
	local DJ = ns.DJ
	if DJ and DJ.NS and DJ.NS() then
		state.phase = "quêtes de donjon"
		local inLog = Gear.LogSet()
		for _, j in ipairs(DJ.Dungeons() or {}) do
			for _, q in ipairs(j.quests) do
				yield()
				local st = DJ.QuestState(q, inLog)
				if st ~= "non" and st ~= "fait" and (tonumber(q.requires) or 1) <= level + LOOKAHEAD then
					for _, list in ipairs({ q.rewardItems, q.additionalRewardItems }) do
						for _, it in ipairs(type(list) == "table" and list or {}) do
							local id = type(it) == "table" and tonumber(it[1])
							local inst = id and Gear.Instant(id)
							if inst and SLOTS_OF[inst.equipLoc] and Gear.CanWear(inst.classID, inst.subclassID, level + LOOKAHEAD) then
								local c = Add(id)
								if c then
									c.djQuests = c.djQuests or {}
									c.djQuests[#c.djQuests + 1] = { q = q, key = j.key }
								end
							end
						end
					end
				end
			end
		end
	end

	-- 3. Ce que tes métiers fabriquent (Guildon Crafts), jusqu'à SKILL_AHEAD points au-dessus de ta compétence.
	state.phase = "métiers"
	if next(cfg.skills) then
		for spell, r in pairs(Data.Ext().RECETTES or {}) do
			yield()
			local skill = type(r) == "table" and cfg.skills[r[1]]
			local created = skill and tonumber(r[5]) or 0
			if skill and created > 0 and (tonumber(r[2]) or 0) <= skill.rank + SKILL_AHEAD then
				local inst = Gear.Instant(created)
				if inst and SLOTS_OF[inst.equipLoc] and Gear.CanWear(inst.classID, inst.subclassID, level + LOOKAHEAD) then
					local source = CraftSource(r, spell)
					local c = source and Add(created)
					if c then
						c.extra[#c.extra + 1] = source
					end
				end
			end
		end
	end

	-- 4. Ce que vendent les vendeurs connus de Finddon (Forever compris).
	state.phase = "vendeurs"
	for id in pairs(Data.ExtGoodsIds() or {}) do
		yield()
		if not byId[id] then
			local inst = Gear.Instant(id)
			if inst and SLOTS_OF[inst.equipLoc] and Gear.CanWear(inst.classID, inst.subclassID, level + LOOKAHEAD) then
				local c = Add(id)
				if c then
					c.fromGoods = true
				end
			end
		end
	end

	-- 5. Les caractéristiques : le jeu charge les objets à la demande (par paquets).
	state.phase, state.done, state.total = "objets", 0, #candidates
	local waiting = {}
	for i, c in ipairs(candidates) do
		if not Gear.Info(c.id) then
			Gear.RequestLoad(c.id)
			waiting[#waiting + 1] = c
		end
		if i % 40 == 0 then
			coroutine.yield()
		end
	end
	local started = GetTime()
	while #waiting > 0 and GetTime() - started < 20 do
		coroutine.yield()
		local still = {}
		for _, c in ipairs(waiting) do
			if not Gear.Info(c.id) then
				still[#still + 1] = c
			end
		end
		waiting = still
		state.done = #candidates - #waiting
	end

	-- 6. La comparaison avec ce que tu portes, et les sources.
	state.phase, state.done = "comparaison", 0
	Gear.ResetWorn()
	local inLog = Gear.LogSet()
	local bySlot, byQuest, byDungeon, list = {}, {}, {}, {}
	for _, c in ipairs(candidates) do
		state.done = state.done + 1
		yield()
		local info = Gear.Info(c.id)
		local e = info and InWindow(info.req, info.ilvl, level) and Gear.Evaluate(c.id, { role = role })
		local owned = GetItemCount and (Call(GetItemCount, c.id, true) or 0) > 0
		if e and e.gain >= MIN_GAIN and not owned then
			if c.fields.subClass == nil then
				-- objet venu des donjons, des métiers ou des vendeurs : ce que Questie en sait en plus
				for _, key in ipairs({ "questRewards", "vendors", "npcDrops", "objectDrops" }) do
					c.fields[key] = Data.ItemField(c.id, key)
				end
			end
			local sources = {}
			QuestSources(c.fields, inLog, sources)
			DJQuestSources(c, inLog, sources)
			VendorSources(c.id, c.fields.vendors, sources)
			local bossKnown = false
			for _, s in ipairs(c.extra) do
				bossKnown = bossKnown or s.kind == "dungeon"
			end
			local drops = {}
			DropSources(c.fields, drops)
			for _, s in ipairs(drops) do
				if not (bossKnown and s.kind == "dungeon") then -- (le même boss, déjà connu par les données de donjon)
					sources[#sources + 1] = s
				end
			end
			for _, s in ipairs(c.extra) do
				sources[#sources + 1] = s
			end
			if #sources > 0 then
				e.sources, e.best = SortSources(sources), sources[1]
				local slotList = bySlot[e.slot] or {}
				bySlot[e.slot] = slotList
				slotList[#slotList + 1] = e
				for _, s in ipairs(sources) do
					if s.quest and (s.kind == "journal" or s.kind == "quest") then
						local prev = byQuest[s.quest]
						if not prev or prev.gain < e.gain then
							byQuest[s.quest] = e
						end
					end
					if s.kind == "dungeon" and s.dungeon then
						local entry = byDungeon[s.dungeon] or { id = s.dungeon, items = {}, bosses = {} }
						byDungeon[s.dungeon] = entry
						entry.items[#entry.items + 1] = e
						entry.bosses[s.name] = true
					end
				end
			end
		end
	end
	for _, slotList in pairs(bySlot) do
		table.sort(slotList, function(a, b)
			local ra, rb = SOURCE_RANK[a.best.kind] or 9, SOURCE_RANK[b.best.kind] or 9
			if math.abs(a.gain - b.gain) > 2 then
				return a.gain > b.gain
			end
			if ra ~= rb then
				return ra < rb
			end
			return a.id < b.id
		end)
		for k = PER_SLOT + 1, #slotList do
			slotList[k] = nil
		end
		for _, e in ipairs(slotList) do
			list[#list + 1] = e
		end
	end
	table.sort(list, function(a, b)
		if a.gain ~= b.gain then
			return a.gain > b.gain
		end
		return a.id < b.id
	end)
	Gear.results = { list = list, bySlot = bySlot, byQuest = byQuest, byDungeon = byDungeon, level = level, role = role,
		at = GetTime(), scanned = state.total, candidates = #candidates, unloaded = #waiting }
	state.phase = "fini"
	Gear.CleanGoals()
	if ns.GearUI and ns.GearUI.Refresh then
		pcall(ns.GearUI.Refresh)
	end
	if (next(cfg.goals) or next(cfg.dungeonGoals)) and ns.RequestPlan then
		ns.RequestPlan("équipement", 1)
	end
end

-- Lance (ou relance) la recherche. Sans effet si elle tourne déjà.
function Gear.Rescan()
	if job or not (Data.QuestieReady() and Data.Modules()) then
		return false
	end
	job = coroutine.create(function()
		Scan(Yield)
	end)
	runner:Show()
	return true
end

function Gear.Busy()
	return job ~= nil
end

-- Après un changement d'équipement : comparaison refaite.
function Gear.OnEquipmentChanged()
	Gear.ResetWorn()
	if Gear.results and not job then
		Gear.Rescan()
	end
end

-------------------------------------------------------------------------------
-- Donjons : lequel faire pour ton équipement ?
-------------------------------------------------------------------------------
-- { dungeon, count, gain (meilleure amélioration par emplacement, additionnées), items, bosses } triés par gain.
function Gear.DungeonRanking()
	local out = {}
	local level = Level()
	local byId = {}
	for _, d in ipairs(Data.Dungeons()) do
		byId[d.id] = d
	end
	for id, entry in pairs(Gear.results and Gear.results.byDungeon or {}) do
		local d = byId[id]
		if d then
			local bestBySlot = {}
			for _, e in ipairs(entry.items) do
				local prev = bestBySlot[e.slot]
				if not prev or prev.gain < e.gain then
					bestBySlot[e.slot] = e
				end
			end
			local gain, count, pct = 0, 0, 0
			for _, e in pairs(bestBySlot) do
				gain, count = gain + e.gain, count + 1
				pct = pct + (e.pct or 25) -- emplacement vide : compté comme un bon gain
			end
			local bosses = {}
			for name in pairs(entry.bosses) do
				bosses[#bosses + 1] = name
			end
			table.sort(bosses)
			out[#out + 1] = { dungeon = d, count = count, gain = gain, pct = pct, items = entry.items, bosses = bosses,
				fits = d.min <= level + 2 and d.max >= level - 2 }
		end
	end
	table.sort(out, function(a, b)
		if a.fits ~= b.fits then
			return a.fits
		end
		if a.gain ~= b.gain then
			return a.gain > b.gain
		end
		return a.dungeon.id < b.dungeon.id
	end)
	return out
end

-------------------------------------------------------------------------------
-- « Y aller » : objectifs d'équipement ajoutés au trajet
-------------------------------------------------------------------------------
function Gear.Find(id)
	for _, e in ipairs(Gear.results and Gear.results.list or {}) do
		if e.id == id then
			return e
		end
	end
	return nil
end

-- La source vers laquelle « Y aller » emmène (la meilleure qui a un lieu).
function Gear.Target(e)
	for _, s in ipairs(e and e.sources or {}) do
		if s.kind == "quest" or (s.points and s.points[1] and s.kind ~= "journal" and s.kind ~= "later" and s.kind ~= "craft") then
			return s
		end
	end
	return nil
end

function Gear.IsGoal(id)
	return Gear.Config().goals[id] and true or false
end

function Gear.SetGoal(id, on)
	Gear.Config().goals[id] = on and true or nil
	if ns.RequestPlan then
		ns.SetPaused(false)
		ns.RequestPlan("équipement", 0)
	end
end

function Gear.IsDungeonGoal(id)
	return Gear.Config().dungeonGoals[id] and true or false
end

function Gear.SetDungeonGoal(id, on)
	Gear.Config().dungeonGoals[id] = on and true or nil
	if ns.RequestPlan then
		ns.SetPaused(false)
		ns.RequestPlan("équipement", 0)
	end
end

function Gear.Ignore(id)
	local cfg = Gear.Config()
	cfg.ignored[id] = true
	cfg.goals[id] = nil
	local r = Gear.results
	if r then
		local function Without(list)
			local kept = {}
			for _, e in ipairs(list or {}) do
				if e.id ~= id then
					kept[#kept + 1] = e
				end
			end
			return kept
		end
		r.list = Without(r.list)
		for slot, list in pairs(r.bySlot or {}) do
			r.bySlot[slot] = Without(list)
		end
		for qid, e in pairs(r.byQuest or {}) do
			if e.id == id then
				r.byQuest[qid] = nil
			end
		end
		for _, entry in pairs(r.byDungeon or {}) do
			entry.items = Without(entry.items)
		end
	end
end

-- Objectif atteint (objet dans les sacs ou porté) ou plus une amélioration : retiré.
function Gear.CleanGoals()
	local cfg = Gear.Config()
	local removed = false
	for id in pairs(cfg.goals) do
		local owned = GetItemCount and (Call(GetItemCount, id, true) or 0) > 0
		if owned or (Gear.results and not Gear.Find(id)) then
			cfg.goals[id] = nil
			removed = true
			if owned then
				local e = Gear.Find(id)
				ns.Print("objectif d'équipement atteint : " .. (e and e.link or ("objet " .. id)) .. ".")
			end
		end
	end
	if removed and ns.RequestPlan then
		ns.RequestPlan("équipement", 1)
	end
	return removed
end

local WORK = { vendor = 60, drop = 600, object = 120, dungeon = 1800, recipe = 90, dquest = 30 }

-- Objectifs « Donjon » enregistrés avant que DungeonJournal ne remplace ce donjon : repris sous son nouvel id.
function Gear.MigrateDungeonGoals()
	local goals = Gear.Config().dungeonGoals
	local moves = {}
	for id in pairs(goals) do
		local alias = Data.DungeonAlias and Data.DungeonAlias(id)
		if alias and alias ~= id then
			moves[id] = alias
		end
	end
	for id, alias in pairs(moves) do -- (pas d'ajout de clé pendant le parcours de la table)
		goals[id] = nil
		goals[alias] = true
	end
end

-- Préparer un donjon de DungeonJournal : ses quêtes dans ton journal (à faire dedans) et celles à prendre avant.
function Gear.DungeonQuests(d, inLog)
	local DJ = ns.DJ
	local out = { log = {}, now = {}, later = {} }
	if not (d and d.dj and DJ and DJ.NS and DJ.NS()) then
		return out
	end
	for _, e in ipairs(DJ.QuestsFor(d.dj, inLog) or {}) do
		local list = e.state == "log" and out.log or e.state == "maintenant" and out.now or out.later
		list[#list + 1] = e
	end
	return out
end

local function GoalWhy(e, s)
	local why = {
		"Objectif d'équipement : " .. e.name .. " " .. Gear.GainText(e) .. " (" .. e.slotName .. ").",
		"Source : " .. s.text .. ".",
	}
	if s.kind == "drop" or s.kind == "dungeon" then
		why[#why + 1] = "Le taux de butin n'est pas connu : il faudra peut-être plusieurs essais."
	end
	why[#why + 1] = "Plus envie ? Clic droit > Passer l'étape, ou retire-le dans /iti equipement."
	return why
end

-- Pour le calcul du trajet : quêtes à prendre pour une récompense visée, arrêts (vendeur, butin, donjon, recette),
-- et les récompenses qui t'améliorent (rendus du trajet).
function Gear.PlanOptions()
	local out = { goals = {}, wanted = {}, quests = {} }
	local results = Gear.results
	if not results then
		return out
	end
	for qid, e in pairs(results.byQuest or {}) do
		out.quests[qid] = { link = e.link, name = e.name, gain = Gear.GainText(e), slot = e.slotName }
	end
	local cfg = Gear.Config()
	local inLog = Gear.LogSet()
	local goalQuests = {} -- quêtes de DungeonJournal déjà visées par un objectif d'équipement
	for id in pairs(cfg.goals) do
		local e = Gear.Find(id)
		local s = e and Gear.Target(e)
		if s and s.kind == "quest" then
			out.wanted[s.quest] = true
		elseif s and s.kind == "dquest" and (inLog[s.quest] or Data.Completed(s.quest)) then
			-- quête déjà prise (ou faite) depuis la dernière analyse : plus rien à aller chercher
		elseif s then
			if s.kind == "dquest" then
				goalQuests[s.quest] = true
			end
			local verb = s.kind == "vendor" and "Acheter" or s.kind == "dungeon" and "Donjon pour"
				or s.kind == "recipe" and "Recette pour" or s.kind == "dquest" and "Quête pour" or "Butin :"
			out.goals[#out.goals + 1] = {
				kind = "gear", key = "objet" .. id, item = id, points = s.points, work = WORK[s.kind] or 300,
				label = verb .. " " .. e.name,
				title = verb .. " " .. e.name .. (s.kind == "vendor" and (" chez " .. tostring(s.name))
					or s.kind == "dungeon" and (" (" .. tostring(s.dungeonName) .. ")")
					or s.kind == "dquest" and (" : « " .. tostring(s.name) .. " »")
					or s.kind == "recipe" and "" or (" (" .. tostring(s.name) .. ")")),
				why = GoalWhy(e, s),
			}
		end
	end
	Gear.MigrateDungeonGoals()
	local ranking
	for id in pairs(cfg.dungeonGoals) do
		ranking = ranking or Gear.DungeonRanking()
		for _, r in ipairs(ranking) do
			local d = r.dungeon
			if d.id == id and d.entrance then
				local why = {
					d.name .. " (niv " .. d.min .. "-" .. d.max .. ") : " .. r.count .. " amélioration(s) pour toi.",
					"Boss : " .. table.concat(r.bosses, ", ") .. ".",
				}
				-- DungeonJournal : les quêtes de ce donjon, à prendre AVANT d'y aller (étapes ajoutées au trajet)
				local DJ = ns.DJ
				local quests = Gear.DungeonQuests(d, inLog)
				local names = {}
				for _, e in ipairs(quests.log) do
					names[#names + 1] = DJ.QuestName(e.q)
				end
				if #names > 0 then
					why[#why + 1] = "À faire dedans (ton journal) : " .. table.concat(names, ", ") .. "."
				end
				local toTake = {}
				for _, e in ipairs(quests.now) do
					local q = e.q
					local questie = Data.Quest(q.id)
					local starts = questie and Data.CanTake(q.id, questie, inLog) and Data.AvailableQuests()[q.id]
						and Data.StarterPoints(questie) or {}
					local p = #starts == 0 and not q.startsInDungeon and DJ.StartPoint(q, d.dj) or nil
					if #starts > 0 then
						out.wanted[q.id] = true
						toTake[#toTake + 1] = DJ.QuestName(q)
					elseif p and goalQuests[q.id] then
						toTake[#toTake + 1] = DJ.QuestName(q) -- (déjà une étape, pour une récompense visée)
					elseif p then -- (« Passer l'étape » : le calcul du trajet l'écarte, clé S:djq…)
						local qname = DJ.QuestName(q)
						toTake[#toTake + 1] = qname
						out.goals[#out.goals + 1] = {
							kind = "gear", key = "djq" .. q.id, points = { p }, work = 30,
							label = "Quête de donjon : " .. qname,
							title = "Prendre « " .. qname .. " »" .. (p.name and (" chez " .. p.name) or "") .. " (" .. d.name .. ")",
							why = {
								"Quête de " .. d.name .. " (DungeonJournal) : à prendre avant d'y aller.",
								"Où : " .. tostring(DJ.Text(q.pickup) or "?") .. ".",
								"Plus envie ? Clic droit > Passer l'étape.",
							},
						}
					end
				end
				if #toTake > 0 then
					why[#why + 1] = "Quêtes à prendre avant (ajoutées au trajet) : " .. table.concat(toTake, ", ") .. "."
				end
				why[#why + 1] = "Plus envie ? Clic droit > Passer l'étape, ou retire-le dans /iti equipement (onglet Donjons)."
				out.goals[#out.goals + 1] = {
					kind = "gear", key = "donjon" .. id, points = { d.entrance }, work = 1800,
					label = (d.raid and "Raid : " or "Donjon : ") .. d.name,
					title = (d.raid and "Raid : " or "Donjon : ") .. d.name .. " (" .. r.count .. " amélioration(s))",
					why = why,
				}
			end
		end
	end
	return out
end

-------------------------------------------------------------------------------
-- Ligne dans la bulle des objets (« Itinéraire : +12 % pour toi »)
-------------------------------------------------------------------------------
local tipCache = {}
local function TooltipLine(tooltip)
	if Gear.Config().tooltip == false or not (tooltip and tooltip.GetItem and tooltip.AddLine) then
		return
	end
	local name = tooltip.GetName and Call(tooltip.GetName, tooltip)
	if type(name) == "string" and name:find("Shopping") then
		return -- les bulles de comparaison du jeu
	end
	local _, link = Call(tooltip.GetItem, tooltip)
	if type(link) ~= "string" then
		return
	end
	local cached = tipCache[link]
	local e, why
	if cached and cached.gen == wornGen then
		e, why = cached.e, cached.why
	else
		e, why = Gear.Evaluate(link)
		if e or (why and why ~= "pas chargé") then
			tipCache[link] = { gen = wornGen, e = e, why = why }
		end
	end
	if e then
		if e.gain >= MIN_GAIN then
			tooltip:AddLine("Itinéraire : |cff00ff00" .. Gear.GainText(e) .. "|r pour toi (" .. e.slotName .. ", "
				.. (ROLE_LABEL[e.role] or e.role) .. ")" .. ((e.req or 0) > Level() and (" — niv " .. e.req) or ""), 0.3, 0.8, 1)
		elseif e.gain < -MIN_GAIN then
			tooltip:AddLine("Itinéraire : " .. (e.pct and string.format("%d %%", math.floor(e.pct + 0.5))
				or string.format("%d", math.floor(e.gain + 0.5))) .. " par rapport au tien (" .. e.slotName .. ")", 0.6, 0.6, 0.6)
		end
	elseif why == "ta classe ne peut pas le porter" then
		tooltip:AddLine("Itinéraire : ta classe ne peut pas le porter", 0.8, 0.3, 0.3)
	end
end

function Gear.HookTooltips()
	if Gear.tooltipHooked then
		return Gear.tooltipHooked
	end
	local T, E = rawget(_G, "TooltipDataProcessor"), Enum and Enum.TooltipDataType
	if T and T.AddTooltipPostCall and E and E.Item then
		if pcall(T.AddTooltipPostCall, E.Item, function(tooltip)
			pcall(TooltipLine, tooltip)
		end) then
			Gear.tooltipHooked = "TooltipDataProcessor"
		end
	elseif GameTooltip and GameTooltip.HookScript then
		if pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", function(tooltip)
			pcall(TooltipLine, tooltip)
		end) then
			Gear.tooltipHooked = "OnTooltipSetItem"
		end
	end
	return Gear.tooltipHooked
end

-- Une ligne pour /iti rapport.
function Gear.ReportLine()
	local role, why = Gear.Role()
	local r = Gear.results
	local st = Gear.state
	local cfg = Gear.Config()
	local goals, skills = 0, {}
	for _ in pairs(cfg.goals) do
		goals = goals + 1
	end
	for _ in pairs(cfg.dungeonGoals) do
		goals = goals + 1
	end
	for line, s in pairs(cfg.skills) do
		skills[#skills + 1] = (PROF_NAMES[line] or line) .. " " .. tostring(s.rank)
	end
	table.sort(skills)
	return string.format("Équipement : rôle %s (%s) · analyse %s (%d/%d)%s · %d objectif(s) · métiers %s · bulle %s",
		ROLE_LABEL[role] or role, why, tostring(st.phase), st.done or 0, st.total or 0,
		r and string.format(" · %d amélioration(s) sur %d pistes, %d non chargées", #r.list, r.candidates or 0, r.unloaded or 0) or "",
		goals, #skills > 0 and table.concat(skills, ", ") or "aucun", tostring(Gear.tooltipHooked or "non"))
end
