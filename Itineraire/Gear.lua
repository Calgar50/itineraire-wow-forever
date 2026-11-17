-- Itinéraire : équipement.
-- Note chaque objet selon ta classe et ton rôle (tank, mêlée, distance, lanceur de sorts, soigneur), le
-- compare à ce que tu portes, conseille la récompense à prendre au rendu d'une quête et cherche dans la
-- base de Questie les améliorations accessibles : récompenses de quêtes, vendeurs, butins de PNJ et de
-- coffres. Tout est calculé dans le jeu avec les vraies caractéristiques des objets : pas de liste figée
-- qui vieillit à chaque mise à jour du jeu. (Les taux de butin, eux, ne sont connus ni du jeu ni de Questie.)
local _, ns = ...
local Gear = {}
ns.Gear = Gear
local Data = ns.Data

local LOOKAHEAD = 3 -- objets jusqu'à 3 niveaux au-dessus du tien (à viser bientôt)
local LOOKBACK = 10 -- et jusqu'à 10 niveaux en dessous (un vieil objet peut encore t'améliorer)
local MAX_DROPPERS = 6 -- au-delà, c'est un butin « du monde » (aléatoire) : pas une piste
local MAX_VENDORS = 8
local MAX_OBJECTS = 4
local MAX_CANDIDATES = 2500
local PER_SLOT = 3 -- meilleures pistes gardées par emplacement
local MIN_GAIN = 1 -- points de note
local SCAN_BUDGET_MS = 4

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

-------------------------------------------------------------------------------
-- Ce que ta classe peut porter (types d'armure et d'armes du jeu classique)
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

local function Set(list)
	local s = {}
	for _, v in ipairs(list or {}) do
		s[v] = true
	end
	return s
end

local function PlayerClass()
	if UnitClassBase then
		local token = UnitClassBase("player")
		if token then
			return token
		end
	end
	if UnitClass then
		local _, token = UnitClass("player")
		return token
	end
	return nil
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
		if not Set(allowed)[subclassID] then
			return false
		end
		local need = ARMOR_LEVEL[class] and ARMOR_LEVEL[class][subclassID]
		return not need or (level or 1) >= need
	elseif classID == 2 then
		local allowed = WEAPON[class]
		if not allowed then
			return subclassID ~= 20 -- canne à pêche
		end
		return Set(allowed)[subclassID] or false
	end
	return false
end

-------------------------------------------------------------------------------
-- Rôle et poids des caractéristiques
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

-- Points dépensés dans l'arbre `tab` (les deux formes de GetTalentTabInfo selon la version du jeu).
local function TreePoints(tab)
	if not GetTalentTabInfo then
		return nil, nil
	end
	local ok, a, b, c, _, e = pcall(GetTalentTabInfo, tab)
	if not ok then
		return nil, nil
	end
	if type(a) == "string" then
		return tonumber(c), a -- nom, icône, points, fichier
	end
	return tonumber(e), b -- id, nom, description, icône, points…
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

-- Clés du jeu (GetItemStats) -> nom court.
local STAT_KEYS = {
	ITEM_MOD_STAMINA_SHORT = "sta", ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi",
	ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi", RESISTANCE0_NAME = "armor",
	ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps", ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "def",
	ITEM_MOD_DODGE_RATING_SHORT = "dodge", ITEM_MOD_PARRY_RATING_SHORT = "parry",
	ITEM_MOD_BLOCK_RATING_SHORT = "block", ITEM_MOD_BLOCK_VALUE_SHORT = "blockv",
	ITEM_MOD_HIT_RATING_SHORT = "hit", ITEM_MOD_CRIT_RATING_SHORT = "crit", ITEM_MOD_HASTE_RATING_SHORT = "haste",
	ITEM_MOD_ATTACK_POWER_SHORT = "ap", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap",
	ITEM_MOD_SPELL_POWER_SHORT = "sp", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal",
	ITEM_MOD_MANA_REGENERATION_SHORT = "mp5", ITEM_MOD_HEALTH_REGENERATION_SHORT = "hp5",
}
-- Valeurs en % dans le jeu classique (« +1 % de coups critiques ») : converties en équivalent « points ».
local PERCENT_STATS = { hit = true, crit = true, dodge = true, parry = true, block = true, haste = true }
local PERCENT_FACTOR = 14

-- Poids par rôle (pour 1 point). L'endurance compte pour tout le monde en montée de niveau.
local WEIGHTS = {
	tank = { sta = 1, armor = 0.1, def = 1, dodge = 1, parry = 0.9, block = 0.6, blockv = 0.3, str = 0.5,
		agi = 0.6, hit = 0.4, crit = 0.2, ap = 0.15, dps = 1, hp5 = 0.5 },
	melee = { str = 1, agi = 0.7, ap = 0.5, hit = 1, crit = 1, haste = 0.8, sta = 0.4, armor = 0.03, dps = 3, hp5 = 0.3 },
	ranged = { agi = 1, rap = 0.4, ap = 0.4, int = 0.3, hit = 1, crit = 1, sta = 0.4, armor = 0.02, dps = 0.5,
		rdps = 3, mp5 = 0.5 },
	caster = { sp = 1, int = 0.6, spi = 0.3, crit = 0.8, hit = 0.8, haste = 0.8, mp5 = 1, sta = 0.4, armor = 0.01 },
	healer = { heal = 0.8, sp = 0.9, int = 0.8, spi = 0.6, mp5 = 1.5, crit = 0.5, sta = 0.3, armor = 0.01 },
}
-- Classes à l'agilité plutôt qu'à la force en mêlée.
local AGI_MELEE = { ROGUE = true, HUNTER = true, DRUID = true }

local function Weights(role)
	local w = WEIGHTS[role] or WEIGHTS.melee
	if role == "melee" and AGI_MELEE[PlayerClass()] then
		local copy = {}
		for k, v in pairs(w) do
			copy[k] = v
		end
		copy.agi, copy.str = 1, 0.5
		return copy
	end
	return w
end

-------------------------------------------------------------------------------
-- Infos d'objets (le jeu les charge à la demande)
-------------------------------------------------------------------------------
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

-- name, link, quality, itemLevel, reqLevel, equipLoc, texture, sellPrice, classID, subclassID (ou nil si pas
-- encore chargé)
function Gear.Info(item)
	local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local name, link, quality, ilvl, req, _, _, _, equipLoc, texture, sell, classID, subclassID = Call(fn, item)
	if not name then
		return nil
	end
	return {
		name = name, link = link, quality = quality or 1, ilvl = ilvl or 0, req = req or 0, equipLoc = equipLoc or "",
		texture = texture, sell = sell or 0, classID = classID, subclassID = subclassID,
	}
end

function Gear.RequestLoad(id)
	if C_Item and C_Item.RequestLoadItemDataByID then
		Call(C_Item.RequestLoadItemDataByID, id)
	else
		Gear.Info(id) -- l'ancien GetItemInfo demande l'objet au serveur tout seul
	end
end

local function StatsOf(link)
	local fn = (C_Item and C_Item.GetItemStats) or GetItemStats
	local stats = Call(fn, link)
	return type(stats) == "table" and stats or nil
end

-- Note d'un objet pour ton rôle (nil si ses caractéristiques ne sont pas encore chargées).
function Gear.Score(link, info, role)
	local stats = StatsOf(link)
	if not stats then
		return nil
	end
	role = role or Gear.Role()
	local w = Weights(role)
	local score = 0
	for key, value in pairs(stats) do
		local stat = STAT_KEYS[key]
		if stat and type(value) == "number" then
			if PERCENT_STATS[stat] and value <= 5 then
				value = value * PERCENT_FACTOR
			end
			if stat == "dps" and info and SLOTS_OF[info.equipLoc] and SLOTS_OF[info.equipLoc][1] == 18 then
				stat = "rdps" -- arme à distance : compte surtout pour un chasseur
			end
			score = score + value * (w[stat] or 0)
		end
	end
	return score
end

-------------------------------------------------------------------------------
-- Ce que tu portes
-------------------------------------------------------------------------------
local worn -- [slot] = { link, score, info }

function Gear.ResetWorn()
	worn = nil
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

local function DualWielding(list)
	local off = list[17] and list[17].info
	return off and (off.equipLoc == "INVTYPE_WEAPON" or off.equipLoc == "INVTYPE_WEAPONOFFHAND") or false
end

-- Évalue un objet face à ce que tu portes. Rend une table (gain, pct, slot…) ou nil + raison.
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
	local level = UnitLevel and UnitLevel("player") or 1
	if info.classID and not Gear.CanWear(info.classID, info.subclassID, math.max(level, info.req)) then
		return nil, "ta classe ne peut pas le porter"
	end
	local role = opts.role or Gear.Role()
	if role == "tank" and info.equipLoc == "INVTYPE_2HWEAPON" and Set(ARMOR[PlayerClass()] or {})[6] then
		return nil, "arme à deux mains (un tank garde son bouclier)"
	end
	if role ~= "tank" and info.equipLoc == "INVTYPE_SHIELD" and (role == "melee" or role == "ranged") then
		return nil, "bouclier (inutile pour ton rôle)"
	end
	local score = Gear.Score(info.link, info, role)
	if not score then
		return nil, "pas chargé"
	end
	local list = Worn(role)
	local slot, current = slots[1], WornScore(list, slots[1])
	if info.equipLoc == "INVTYPE_2HWEAPON" then
		local main = list[16] and list[16].info
		current = WornScore(list, 16) + ((main and main.equipLoc == "INVTYPE_2HWEAPON") and 0 or WornScore(list, 17))
	elseif #slots == 2 then
		local a, b = WornScore(list, slots[1]), WornScore(list, slots[2])
		if not list[slots[2]] or b < a then
			slot, current = slots[2], b
		else
			current = a
		end
		if not list[slots[1]] then
			slot, current = slots[1], 0
		end
	elseif info.equipLoc == "INVTYPE_WEAPON" and DualWielding(list) then
		local a, b = WornScore(list, 16), WornScore(list, 17)
		if b < a then
			slot, current = 17, b
		else
			current = a
		end
	end
	local gain = score - current
	return {
		id = tonumber(tostring(info.link):match("item:(%d+)")), link = info.link, name = info.name,
		quality = info.quality, texture = info.texture, req = info.req, sell = info.sell,
		equipLoc = info.equipLoc, slot = slot, slotName = SLOT_NAMES[slot] or "?",
		score = score, current = current, gain = gain, empty = not list[slot],
		pct = current > 0 and (gain / current * 100) or nil, role = role,
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

-------------------------------------------------------------------------------
-- Récompense conseillée au rendu d'une quête
-------------------------------------------------------------------------------
local mark -- cadre doré posé sur la récompense conseillée

local function RewardButton(i)
	local frame = rawget(_G, "QuestInfoRewardsFrame")
	local list = frame and frame.RewardButtons
	if type(list) == "table" and list[i] then
		return list[i]
	end
	return rawget(_G, "QuestInfoRewardsFrameQuestInfoItem" .. i) or rawget(_G, "QuestInfoItem" .. i)
end

local function Mark(button)
	if not button then
		return
	end
	if not mark then
		mark = CreateFrame("Frame", nil, UIParent)
		mark.border = mark:CreateTexture(nil, "OVERLAY")
		mark.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		mark.border:SetBlendMode("ADD")
		mark.border:SetVertexColor(1, 0.82, 0)
		mark.label = mark:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		mark.label:SetText("|cff00ff00Conseillé|r")
	end
	mark:SetParent(button)
	mark:ClearAllPoints()
	mark:SetAllPoints(button)
	mark:SetFrameLevel((button.GetFrameLevel and button:GetFrameLevel() or 1) + 5)
	local icon = button.Icon or button.icon or rawget(_G, (button.GetName and button:GetName() or "") .. "IconTexture")
	mark.border:ClearAllPoints()
	if icon then
		mark.border:SetPoint("CENTER", icon, "CENTER", 0, 0)
		mark.border:SetSize(70, 70)
	else
		mark.border:SetAllPoints(mark)
	end
	mark.label:ClearAllPoints()
	mark.label:SetPoint("BOTTOMRIGHT", mark, "BOTTOMRIGHT", -4, 2)
	mark:Show()
end

function Gear.HideMark()
	if mark then
		mark:Hide()
	end
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

-- Choix entre plusieurs récompenses : la meilleure amélioration, sinon la plus chère à revendre.
-- Rend { index, entry, why } ou nil si les objets ne sont pas encore chargés.
function Gear.BestReward(links, counts)
	local best, bestGain, cash, cashValue = nil, MIN_GAIN, nil, -1
	for i, link in ipairs(links) do
		local info = Gear.Info(link)
		if not info then
			return nil
		end
		local e = Gear.Evaluate(link)
		if e and e.gain >= bestGain then
			best, bestGain = i, e.gain
		end
		local value = (info.sell or 0) * ((counts and counts[i]) or 1)
		if value > cashValue then
			cash, cashValue = i, value
		end
		links[i] = { link = link, entry = e, info = info, value = value }
	end
	if best then
		return { index = best, item = links[best], upgrade = true }
	end
	return cash and { index = cash, item = links[cash], upgrade = false } or nil
end

local adviceTries = 0
function Gear.OnQuestComplete(retry)
	local cfg = Gear.Config()
	if cfg.rewardAdvice == false then
		return
	end
	if not retry then
		adviceTries = 0
	end
	local n = GetNumQuestChoices and Call(GetNumQuestChoices) or 0
	if type(n) ~= "number" or n < 2 then
		return
	end
	local links, counts = {}, {}
	for i = 1, n do
		local link = GetQuestItemLink and Call(GetQuestItemLink, "choice", i)
		local _, _, count = Call(GetQuestItemInfo, "choice", i)
		if not link then
			links = nil
			break
		end
		links[i], counts[i] = link, tonumber(count) or 1
	end
	local choice = links and Gear.BestReward(links, counts)
	if not choice then
		adviceTries = adviceTries + 1
		if adviceTries <= 10 then
			C_Timer.After(0.3, function()
				Gear.OnQuestComplete(true)
			end)
		end
		return
	end
	local button = RewardButton(choice.index)
	Mark(button)
	if cfg.preselect ~= false and button then
		local click = rawget(_G, "QuestInfoItem_OnClick")
		if click then
			pcall(click, button)
		end
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

-------------------------------------------------------------------------------
-- Recherche des améliorations dans la base de Questie (en tâche de fond)
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

function Gear.Config()
	if not ns.char then
		return {}
	end
	if type(ns.char.gear) ~= "table" then
		ns.char.gear = {}
	end
	local g = ns.char.gear
	g.ignored = type(g.ignored) == "table" and g.ignored or {}
	g.goals = type(g.goals) == "table" and g.goals or {}
	g.role = g.role or "auto"
	return g
end

local function Count(list)
	return type(list) == "table" and #list or 0
end

-- Sources d'un objet, lisibles et triées (la plus pratique d'abord). `inLog` : quêtes du journal.
local SOURCE_RANK = { journal = 1, vendor = 2, quest = 3, drop = 4, dungeon = 5, object = 6, later = 7 }

local function ZoneOf(points)
	local p = points and points[1]
	return p and ns.Geo.ZoneName(p.map) or nil
end

local function Sources(id, fields, inLog, faction)
	local out = {}
	for _, qid in ipairs(type(fields.questRewards) == "table" and fields.questRewards or {}) do
		if inLog[qid] then
			local q = Data.Quest(qid)
			out[#out + 1] = { kind = "journal", quest = qid, name = q and q.name or ("#" .. qid), text = "récompense de « "
				.. (q and q.name or qid) .. " » (dans ton journal)" }
		elseif not Data.Completed(qid) then
			local q = Data.Quest(qid)
			local ok = q and Data.CanTake(qid, q, inLog)
			if ok then
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
	local vendors = type(fields.vendors) == "table" and fields.vendors or {}
	if #vendors <= MAX_VENDORS then
		for _, npcId in ipairs(vendors) do
			local points, npc = Data.NpcPlaces(npcId, 60)
			if npc and npc.friendly ~= false and #points > 0 then
				out[#out + 1] = { kind = "vendor", npc = npcId, name = npc.name, points = points,
					text = "vendu par " .. tostring(npc.name) .. (ZoneOf(points) and (" (" .. ZoneOf(points) .. ")") or "") }
			end
		end
	end
	local droppers = type(fields.npcDrops) == "table" and fields.npcDrops or {}
	if #droppers >= 1 and #droppers <= MAX_DROPPERS then
		for _, npcId in ipairs(droppers) do
			local points, npc, meta = Data.NpcPlaces(npcId, 60)
			if npc then
				local dungeon = next(meta.dungeons)
				if dungeon then
					local entrance = Data.DungeonEntrance(dungeon)
					out[#out + 1] = { kind = "dungeon", npc = npcId, name = npc.name, dungeon = dungeon,
						dungeonName = Data.DungeonName(dungeon), points = entrance and { entrance } or {},
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
	table.sort(out, function(a, b)
		return (SOURCE_RANK[a.kind] or 9) < (SOURCE_RANK[b.kind] or 9)
	end)
	return out
end
Gear.Sources = Sources

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

local FIELDS = { "requiredLevel", "subClass", "questRewards", "vendors", "npcDrops", "objectDrops", "itemLevel" }

local function Scan(yield)
	local state = Gear.state
	local level = UnitLevel and UnitLevel("player") or 1
	local role = Gear.Role()
	local cfg = Gear.Config()
	local ids = Data.ItemIds()
	if not ids then
		state.phase = "pas de base"
		return
	end
	-- 1. La base : l'équipement de ton niveau, que ta classe peut porter, avec une source précise.
	state.phase, state.done, state.total = "base", 0, 0
	local candidates = {}
	for id in pairs(ids) do
		state.total = state.total + 1
	end
	for id in pairs(ids) do
		state.done = state.done + 1
		yield()
		local class = Data.ItemField(id, "class")
		-- (champ par champ : on ne lit les sources que des objets qui passent les premiers filtres)
		local req = (class == 2 or class == 4) and not cfg.ignored[id] and (tonumber(Data.ItemField(id, "requiredLevel")) or 0)
		local inWindow = false
		if req then
			if req == 0 then
				local ilvl = tonumber(Data.ItemField(id, "itemLevel")) or 0
				inWindow = ilvl >= level - 5 and ilvl <= level + LOOKAHEAD + 2
			else
				inWindow = req <= level + LOOKAHEAD and req >= level - LOOKBACK
			end
		end
		local fields
		if inWindow then
			fields = { subClass = Data.ItemField(id, "subClass") }
			inWindow = Gear.CanWear(class, fields.subClass, math.max(level, req))
		end
		if inWindow then
			for _, key in ipairs(FIELDS) do
				if fields[key] == nil then
					fields[key] = Data.ItemField(id, key)
				end
			end
			do
				local useful = Count(fields.questRewards) > 0
					or (Count(fields.vendors) >= 1 and Count(fields.vendors) <= MAX_VENDORS)
					or (Count(fields.npcDrops) >= 1 and Count(fields.npcDrops) <= MAX_DROPPERS)
					or (Count(fields.objectDrops) >= 1 and Count(fields.objectDrops) <= MAX_OBJECTS)
				if useful and #candidates < MAX_CANDIDATES then
					fields.id, fields.req = id, req
					candidates[#candidates + 1] = fields
				end
			end
		end
	end
	-- 2. Les caractéristiques : le jeu charge les objets à la demande (par paquets).
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
	-- 3. La comparaison avec ce que tu portes.
	state.phase, state.done = "comparaison", 0
	Gear.ResetWorn()
	local inLog = Gear.LogSet()
	local bySlot, byQuest, list = {}, {}, {}
	for _, c in ipairs(candidates) do
		state.done = state.done + 1
		yield()
		local e = Gear.Evaluate(c.id, { role = role })
		local owned = GetItemCount and (Call(GetItemCount, c.id, true) or 0) > 0
		if e and e.gain >= MIN_GAIN and not owned then
			local sources = Sources(c.id, c, inLog)
			if #sources > 0 then
				e.sources, e.best = sources, sources[1]
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
				end
			end
		end
	end
	for slot, slotList in pairs(bySlot) do
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
	Gear.results = { list = list, bySlot = bySlot, byQuest = byQuest, level = level, role = role, at = GetTime(),
		scanned = state.total, candidates = #candidates, unloaded = #waiting }
	state.phase = "fini"
	Gear.CleanGoals()
	if ns.GearUI and ns.GearUI.Refresh then
		pcall(ns.GearUI.Refresh)
	end
	if next(cfg.goals) and ns.RequestPlan then
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

-- Après un changement d'équipement : seulement la comparaison (pas toute la base).
function Gear.OnEquipmentChanged()
	Gear.ResetWorn()
	if Gear.results and not job then
		Gear.Rescan()
	end
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

local WORK = { vendor = 60, drop = 600, object = 120, dungeon = 1800 }

-- Pour le calcul du trajet : quêtes à prendre pour une récompense visée, arrêts (vendeur, butin, donjon),
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
	for id in pairs(Gear.Config().goals) do
		local e = Gear.Find(id)
		local s = e and e.best
		if s then
			if s.kind == "quest" then
				out.wanted[s.quest] = true
			elseif (s.kind == "vendor" or s.kind == "drop" or s.kind == "object" or s.kind == "dungeon") and s.points and s.points[1] then
				local verb = s.kind == "vendor" and "Acheter" or s.kind == "dungeon" and "Donjon pour" or "Butin :"
				local why = {
					"Objectif d'équipement : " .. e.name .. " " .. Gear.GainText(e) .. " (" .. e.slotName .. ").",
					"Source : " .. s.text .. ".",
				}
				if s.kind == "drop" or s.kind == "dungeon" then
					why[#why + 1] = "Le taux de butin n'est pas connu : il faudra peut-être plusieurs essais."
				end
				why[#why + 1] = "Plus envie ? Clic droit > Passer l'étape, ou retire-le dans /iti equipement."
				out.goals[#out.goals + 1] = {
					kind = "gear", key = "objet" .. id, item = id, points = s.points, work = WORK[s.kind] or 300,
					label = verb .. " " .. e.name,
					title = verb .. " " .. e.name .. (s.kind == "vendor" and (" chez " .. tostring(s.name))
						or s.kind == "dungeon" and (" (" .. tostring(s.dungeonName) .. ")") or (" (" .. tostring(s.name) .. ")")),
					why = why,
				}
			end
		end
	end
	return out
end

-- Une ligne pour /iti rapport.
function Gear.ReportLine()
	local role, why = Gear.Role()
	local r = Gear.results
	local st = Gear.state
	local goals = 0
	for _ in pairs(Gear.Config().goals) do
		goals = goals + 1
	end
	return string.format("Équipement : rôle %s (%s) · analyse %s (%d/%d)%s · %d objectif(s)", ROLE_LABEL[role] or role, why,
		tostring(st.phase), st.done or 0, st.total or 0,
		r and string.format(" · %d amélioration(s) sur %d pistes, %d non chargées", #r.list, r.candidates or 0, r.unloaded or 0) or "",
		goals)
end
