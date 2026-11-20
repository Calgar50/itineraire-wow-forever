-- Itinéraire : ce que le pilote fait aussi pour toi, hors des PNJ (réglages : /iti reglages > Pilote).
--   - TALENTS : suit un plan de talents (selon ta classe et ton rôle) et met tes points, en te demandant d'abord
--     (par défaut : un clic) ou tout seul. Un point de talent ne se reprend que contre de l'or chez le maître de
--     classe : d'où la question par défaut.
--   - ÉQUIPEMENT : met l'objet de tes sacs qui t'améliore (note de la fenêtre Équipement), hors combat, dès que tu
--     peux le porter. Un objet « lié quand équipé » pas encore lié : il te demande d'abord. Tu remets ton ancien
--     objet : il n'y touche plus (pour la session).
--   - SACS : un sac de tes sacs va dans un emplacement de sac libre.
-- Tout passe par le pilote (marche / arrêt, une case par partie) ; si le jeu bloque une action, la partie se coupe.
--
-- Les plans de talents sont écrits pour WoW Forever 1.60.1 (arbres du client, build 70959 : talents nouveaux ou
-- changés par rapport à Classic compris). Un talent est reconnu par son sort (identifiant), puis par le nom de ce sort
-- dans la langue du jeu, puis par son nom anglais : un plan reste bon si Blizzard déplace un talent dans l'arbre. C'est
-- le jeu qui dit si un point est possible (paliers, prérequis) : un pas impossible attend, le suivant passe.
local _, ns = ...
local Auto = {}
ns.Auto = Auto

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
	local ok, n = pcall(function()
		return type(v) == "number" and v or nil
	end)
	return ok and n or nil
end

local function Level()
	return Num(Call(UnitLevel, "player")) or 1
end

local function InCombat()
	return (InCombatLockdown and Call(InCombatLockdown)) or (UnitAffectingCombat and Call(UnitAffectingCombat, "player"))
		or false
end

local function Cfg()
	return ns.Pilote.Config()
end

-- La partie `key` du pilote est-elle permise ? (pilote en marche, case cochée, pas bloquée par le jeu)
local function Allowed(key)
	return ns.Pilote.Active and ns.Pilote.Active(key, true) or false
end

Auto.log = {}
local function Note(text)
	local log = Auto.log
	log[#log + 1] = date("%H:%M:%S") .. " " .. text
	while #log > 12 do
		table.remove(log, 1)
	end
end

-------------------------------------------------------------------------------
-- Fenêtre de question (la sienne : pas les fenêtres du jeu, pour ne rien contaminer)
-------------------------------------------------------------------------------
local ask, queue = nil, {}

local function ShowNext()
	if not ask or ask:IsShown() or #queue == 0 or InCombat() then
		return
	end
	local q = table.remove(queue, 1)
	ask.current = q
	ask.text:SetText(q.text)
	for i, b in ipairs(ask.buttons) do
		local choice = q.buttons[i]
		b:SetShown(choice ~= nil)
		if choice then
			b:SetText(choice.label)
		end
	end
	ask:SetHeight(math.max(96, (ask.text:GetStringHeight() or 30) + 74))
	ns.UI.Skin.Panel(ask, 0.97)
	ns.UI.Skin.HeaderColors(ask)
	ask:Show()
end

local function Build()
	ask = CreateFrame("Frame", "ItineraireQuestion", UIParent, "BackdropTemplate")
	ask:SetSize(340, 110)
	ask:SetPoint("TOP", UIParent, "TOP", 0, -160)
	ask:SetFrameStrata("DIALOG")
	ask:SetClampedToScreen(true)
	ask:SetMovable(true)
	ask:EnableMouse(true)
	ask:RegisterForDrag("LeftButton")
	ask:SetScript("OnDragStart", ask.StartMoving)
	ask:SetScript("OnDragStop", ask.StopMovingOrSizing)
	ask:Hide()
	ns.UI.Skin.Header(ask, "Itinéraire — pilote", "Interface\\Icons\\Ability_Hunter_Pathfinding", 24)
	ask.text = ask:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	ask.text:SetPoint("TOPLEFT", 14, -34)
	ask.text:SetPoint("RIGHT", -14, 0)
	ask.text:SetJustifyH("LEFT")
	ask.buttons = {}
	for i = 1, 3 do
		local b = ns.UI.Skin.Button(ask, "", 100, 22, function()
			local q = rawget(ask, "current")
			ask:Hide()
			ask.current = nil
			local choice = q and q.buttons[i]
			if choice and choice.func then
				local ok, err = pcall(choice.func)
				if not ok and ns.OnError then
					ns.OnError("pilote (question) : " .. tostring(err))
				end
			end
			ShowNext()
		end)
		b:SetPoint("BOTTOMLEFT", 12 + (i - 1) * 106, 10)
		ask.buttons[i] = b
	end
end

-- Pose une question (une à la fois, jamais en combat). `key` : une seule question de ce genre en attente.
-- buttons = { { label, func }, … } (3 au plus).
function Auto.Ask(key, text, buttons)
	if not ask then
		Build()
	end
	local current = rawget(ask, "current")
	if current and current.key == key then
		return
	end
	for i, q in ipairs(queue) do
		if q.key == key then
			queue[i] = { key = key, text = text, buttons = buttons }
			return
		end
	end
	queue[#queue + 1] = { key = key, text = text, buttons = buttons }
	ShowNext()
end

function Auto.Asking(key)
	local current = ask and rawget(ask, "current")
	if current and current.key == key then
		return true
	end
	for _, q in ipairs(queue) do
		if q.key == key then
			return true
		end
	end
	return false
end

-------------------------------------------------------------------------------
-- Plans de talents
-------------------------------------------------------------------------------
-- S(onglet, sort de rang 1, nom anglais, du rang, au rang) : une suite de points dans un talent.
local function Plan(label, tree, parts)
	local steps = {}
	for _, p in ipairs(parts) do
		for rank = p[4], p[5] do
			steps[#steps + 1] = { tab = p[1], spell = p[2], en = p[3], rank = rank }
		end
	end
	return { label = label, tree = tree, steps = steps }
end

-- Guerrier (Forever 1.60.1) : onglets 1 Armes, 2 Fureur, 3 Protection. Un point par niveau de 10 à 60 ; un palier
-- d'arbre demande 5 points de plus dans les paliers au-dessus.
local PLANS = {
	WARRIOR = {
		tank = Plan("Protection (tank, avec bouclier)", 3, {
			{ 3, 12298, "Shield Specialization", 1, 5 }, -- 10-14 : blocage, rage au blocage
			{ 3, 12797, "Improved Revenge", 1, 3 }, -- 15-17
			{ 3, 12297, "Anticipation", 1, 2 }, -- 18-19
			{ 3, 1310316, "Master of Defense", 1, 2 }, -- 20-21 : rage sur esquive / parade
			{ 3, 12975, "Last Stand", 1, 1 }, -- 22
			{ 3, 12792, "Defiance", 1, 2 }, -- 23-24 : menace
			{ 3, 1310317, "Vanguard", 1, 1 }, -- 25 : Charge en posture défensive
			{ 3, 12792, "Defiance", 3, 3 }, -- 26
			{ 3, 12297, "Anticipation", 3, 5 }, -- 27-29
			{ 3, 12809, "Concussion Blow", 1, 1 }, -- 30
			{ 3, 29787, "Focused Rage", 1, 3 }, -- 31-33
			{ 3, 12301, "Improved Bloodrage", 1, 1 }, -- 34
			{ 3, 16538, "Bastion", 1, 5 }, -- 35-39
			{ 3, 23922, "Shield Slam", 1, 1 }, -- 40
			{ 3, 12287, "Improved Thunder Clap", 1, 3 }, -- 41-43
			{ 3, 12308, "Improved Sunder Armor", 1, 3 }, -- 44-46
			{ 3, 12312, "Improved Shield Wall", 1, 2 }, -- 47-48
			{ 3, 12301, "Improved Bloodrage", 2, 2 }, -- 49
			{ 3, 12311, "Improved Shield Bash", 1, 2 }, -- 50-51
			{ 3, 12962, "Iron Will", 1, 5 }, -- 52-56
			{ 3, 12313, "Improved Disarm", 1, 3 }, -- 57-59
			{ 1, 12282, "Improved Heroic Strike", 1, 1 }, -- 60
		}),
		melee = Plan("Armes (arme à deux mains)", 1, {
			{ 1, 12282, "Improved Heroic Strike", 1, 3 }, -- 10-12
			{ 1, 16462, "Deflection", 1, 2 }, -- 13-14
			{ 1, 12285, "Improved Charge", 1, 2 }, -- 15-16
			{ 1, 12290, "Improved Overpower", 1, 2 }, -- 17-18
			{ 1, 12295, "Improved Tactical Mastery", 1, 1 }, -- 19
			{ 1, 12296, "Anger Management", 1, 1 }, -- 20
			{ 1, 12834, "Deep Wounds", 1, 3 }, -- 21-23
			{ 1, 12295, "Improved Tactical Mastery", 2, 2 }, -- 24
			{ 1, 12163, "Two-Handed Weapon Specialization", 1, 3 }, -- 25-27
			{ 1, 16493, "Impale", 1, 2 }, -- 28-29
			{ 1, 12292, "Sweeping Strikes", 1, 1 }, -- 30
			{ 1, 1290261, "Weaponmaster", 1, 5 }, -- 31-35
			{ 1, 12862, "Improved Slam", 1, 2 }, -- 36-37
			{ 1, 1310222, "Spearing Strike", 1, 1 }, -- 38
			{ 1, 1289682, "Bloodthrill", 1, 1 }, -- 39
			{ 1, 12294, "Mortal Strike", 1, 1 }, -- 40
			{ 1, 1289682, "Bloodthrill", 2, 2 }, -- 41
			{ 1, 16462, "Deflection", 3, 5 }, -- 42-44
			{ 1, 12295, "Improved Tactical Mastery", 3, 3 }, -- 45
			{ 2, 12320, "Cruelty", 1, 5 }, -- 46-50
			{ 2, 12322, "Unbridled Wrath", 1, 5 }, -- 51-55
			{ 2, 16487, "Blood Craze", 1, 3 }, -- 56-58
			{ 2, 12323, "Piercing Howl", 1, 1 }, -- 59
			{ 1, 12286, "Improved Rend", 1, 1 }, -- 60
		}),
	},
}
Auto.PLANS = PLANS

local function PlayerClass()
	local _, token = Call(UnitClass, "player")
	return type(token) == "string" and token or "?"
end

-- Le plan suivi : celui choisi dans les réglages, sinon celui de ton rôle (comme la fenêtre Équipement).
function Auto.Plan()
	local plans = PLANS[PlayerClass()]
	if not plans then
		return nil
	end
	local choice = Cfg().talentPlan
	if choice and choice ~= "auto" and plans[choice] then
		return plans[choice], choice
	end
	local role = ns.Gear and ns.Gear.Role and ns.Gear.Role() or nil
	if role and plans[role] then
		return plans[role], role
	end
	local key = next(plans)
	return plans[key], key
end

-- Les plans de ta classe : { { key, label }, … }.
function Auto.PlanChoices()
	local out = {}
	for key, plan in pairs(PLANS[PlayerClass()] or {}) do
		out[#out + 1] = { key = key, label = plan.label }
	end
	table.sort(out, function(a, b)
		return a.key > b.key -- (tank d'abord)
	end)
	return out
end

local function Lower(s)
	return type(s) == "string" and s:lower() or nil
end

local function SpellName(id)
	if C_Spell and C_Spell.GetSpellName then
		local n = Call(C_Spell.GetSpellName, id)
		if type(n) == "string" and n ~= "" then
			return n
		end
	end
	if C_Spell and C_Spell.GetSpellInfo then
		local info = Call(C_Spell.GetSpellInfo, id)
		if type(info) == "table" and type(info.name) == "string" then
			return info.name
		end
	end
	local n = Call(rawget(_G, "GetSpellInfo"), id)
	return type(n) == "string" and n or nil
end

-------------------------------------------------------------------------------
-- Lecture des talents
--   Forever : arbre « à la Retail » (C_Traits) : une config (C_ClassTalents.GetActiveConfigID) d'un seul arbre, dont
--   les trois onglets sont des groupes (C_Traits.GetGroupDisplayInfoByTreeID). Un point se PRÉPARE
--   (C_Traits.PurchaseRank) puis s'APPLIQUE (CommitConfig : une courte incantation, il faut rester immobile).
--   Secours : l'API Classic (GetTalentInfo / LearnTalent), si le jeu l'a.
-- Format commun : trees[onglet] = { name, points, talents = { [clé] = t }, byName, bySpell }, trees.free,
--   trees.mode (« traits » ou « classic »), trees.configID ; t = { key, name, spell, rank, max, can, tab }.
-------------------------------------------------------------------------------
local function TraitIDs()
	if not (C_ClassTalents and C_Traits and type(C_ClassTalents.GetActiveConfigID) == "function"
		and type(C_Traits.GetTreeNodes) == "function") then
		return nil
	end
	local configID = Num(Call(C_ClassTalents.GetActiveConfigID))
	local info = configID and Call(C_Traits.GetConfigInfo, configID)
	local treeID = type(info) == "table" and type(info.treeIDs) == "table" and Num(info.treeIDs[1]) or nil
	if not treeID then
		return nil
	end
	return configID, treeID
end

local function TraitTrees(configID, treeID)
	local groups = {}
	for _, g in ipairs(Call(C_Traits.GetGroupDisplayInfoByTreeID, treeID) or {}) do
		if type(g) == "table" and Num(g.groupID) then
			groups[#groups + 1] = g
		end
	end
	table.sort(groups, function(a, b)
		return (Num(a.orderIndex) or 0) < (Num(b.orderIndex) or 0)
	end)
	local trees, byGroup, ids = { mode = "traits", configID = configID, treeID = treeID }, {}, {}
	for tab, g in ipairs(groups) do
		trees[tab] = { name = g.displayName, groupID = g.groupID, points = 0, talents = {}, byName = {}, bySpell = {} }
		byGroup[g.groupID] = tab
		ids[#ids + 1] = g.groupID
	end
	-- (un onglet sans point manque dans la réponse : 0)
	for _, e in ipairs(Call(C_Traits.GetGroupCurrencyInfo, configID, ids) or {}) do
		local tab = type(e) == "table" and byGroup[e.traitNodeGroupID]
		local c = tab and type(e.currencyInfos) == "table" and e.currencyInfos[1]
		if c then
			trees[tab].points = Num(c.spent) or 0
		end
	end
	for _, nodeID in ipairs(Call(C_Traits.GetTreeNodes, treeID) or {}) do
		local n = Call(C_Traits.GetNodeInfo, configID, nodeID)
		local tab
		for _, g in ipairs(type(n) == "table" and type(n.groupIDs) == "table" and n.groupIDs or {}) do
			tab = tab or byGroup[g]
		end
		if tab and n.isVisible ~= false then
			local entryID = type(n.activeEntry) == "table" and n.activeEntry.entryID
				or type(n.entryIDs) == "table" and n.entryIDs[1] or nil
			local entry = entryID and Call(C_Traits.GetEntryInfo, configID, entryID)
			local def = type(entry) == "table" and entry.definitionID and Call(C_Traits.GetDefinitionInfo, entry.definitionID)
			local spell = type(def) == "table" and Num(def.spellID) or nil
			local name = type(def) == "table" and type(def.overrideName) == "string" and def.overrideName ~= "" and def.overrideName
				or (spell and SpellName(spell))
			local t = { key = nodeID, tab = tab, name = name, spell = spell, rank = Num(n.currentRank) or 0,
				max = Num(n.maxRanks) or 1, can = n.canPurchaseRank == true }
			local tree = trees[tab]
			tree.talents[nodeID] = t
			if spell then
				tree.bySpell[spell] = nodeID
			end
			if name then
				tree.byName[Lower(name)] = nodeID
			end
		end
	end
	local currency = Call(C_Traits.GetTreeCurrencyInfo, configID, treeID, false)
	local c = type(currency) == "table" and currency[1]
	trees.free = type(c) == "table" and Num(c.quantity) or 0
	return trees
end

-- Un talent Classic : nom, palier, rang, rang max, prérequis remplis.
local function TalentInfo(tab, index)
	local name, icon, tier, _, rank, maxRank, _, available = Call(GetTalentInfo, tab, index)
	if type(name) ~= "string" then
		return nil
	end
	return { key = index, tab = tab, name = name, icon = icon, tier = Num(tier) or 1, rank = Num(rank) or 0,
		max = Num(maxRank) or 1, available = available ~= false }
end

local function ClassicTrees()
	if type(GetTalentInfo) ~= "function" or type(GetNumTalents) ~= "function" then
		return nil
	end
	local trees = { mode = "classic" }
	local spent = 0
	for tab = 1, Num(Call(GetNumTalentTabs)) or 3 do
		local tree = { points = 0, talents = {}, byName = {}, bySpell = {} }
		local tabName = Call(GetTalentTabInfo, tab)
		tree.name = type(tabName) == "string" and tabName or nil
		for index = 1, Num(Call(GetNumTalents, tab)) or 0 do
			local t = TalentInfo(tab, index)
			if t then
				tree.talents[index] = t
				tree.points = tree.points + t.rank
				tree.byName[Lower(t.name)] = index
			end
		end
		spent = spent + tree.points
		trees[tab] = tree
	end
	trees.free = Num(Call(UnitCharacterPoints, "player")) or math.max(0, Level() - 9 - spent)
	for _, tree in ipairs(trees) do
		for _, t in pairs(tree.talents) do
			t.can = t.rank < t.max and t.available and tree.points >= ((t.tier - 1) * 5) and trees.free > 0
		end
	end
	return trees
end

function Auto.Trees()
	local configID, treeID = TraitIDs()
	if configID then
		return TraitTrees(configID, treeID)
	end
	return ClassicTrees()
end

-- Points dépensés par onglet (pour deviner le rôle) : { { name, points }, … } ou nil.
-- (appelé à chaque bulle d'objet : seulement les points par onglet, gardés 2 secondes)
local pointsCache, pointsAt = nil, -10
function Auto.TreePoints()
	if pointsCache and GetTime() - pointsAt < 2 then
		return pointsCache
	end
	local out
	local configID, treeID = TraitIDs()
	if configID then
		local groups, ids, byGroup = {}, {}, {}
		for _, g in ipairs(Call(C_Traits.GetGroupDisplayInfoByTreeID, treeID) or {}) do
			if type(g) == "table" and Num(g.groupID) then
				groups[#groups + 1] = g
			end
		end
		table.sort(groups, function(a, b)
			return (Num(a.orderIndex) or 0) < (Num(b.orderIndex) or 0)
		end)
		out = {}
		for tab, g in ipairs(groups) do
			out[tab] = { name = g.displayName, points = 0 }
			byGroup[g.groupID] = tab
			ids[#ids + 1] = g.groupID
		end
		for _, e in ipairs(Call(C_Traits.GetGroupCurrencyInfo, configID, ids) or {}) do
			local tab = type(e) == "table" and byGroup[e.traitNodeGroupID]
			local c = tab and type(e.currencyInfos) == "table" and e.currencyInfos[1]
			if c then
				out[tab].points = Num(c.spent) or 0
			end
		end
	else
		local trees = ClassicTrees()
		if trees then
			out = {}
			for tab, t in ipairs(trees) do
				out[tab] = { name = t.name, points = t.points }
			end
		end
	end
	pointsCache, pointsAt = out, GetTime()
	return out
end

-- Où est le talent d'un pas du plan : onglet et clé (par son sort, puis le nom de son sort, puis son nom anglais).
local function Resolve(trees, step)
	for tab, t in ipairs(trees) do
		if t.bySpell[step.spell] then
			return tab, t.bySpell[step.spell]
		end
	end
	for _, name in ipairs({ Lower(SpellName(step.spell)), Lower(step.en) }) do
		if name then
			local tree = trees[step.tab]
			if tree and tree.byName[name] then
				return step.tab, tree.byName[name]
			end
			for tab, t in ipairs(trees) do
				if t.byName[name] then
					return tab, t.byName[name]
				end
			end
		end
	end
	return nil
end

local skippedSteps = {} -- [n° du pas] = raison (talent introuvable, refusé par le jeu) : cette session
local snoozedAt -- « Plus tard » : plus de question avant le prochain niveau

-- Le prochain point du plan : { tab, key, name, rank, max, step, plan } ou nil, raison.
-- `extra` = rangs déjà préparés par nous que le jeu ne montre pas encore : { [clé] = n, total = n }.
function Auto.NextTalent(extra)
	extra = extra or { total = 0 }
	local plan = Auto.Plan()
	if not plan then
		return nil, "pas de plan pour ta classe (pour l'instant : guerrier)"
	end
	local trees = Auto.Trees()
	if not trees then
		return nil, "talents illisibles"
	end
	if trees.free - extra.total <= 0 then
		return nil, "aucun point à mettre", plan
	end
	for i, step in ipairs(plan.steps) do
		if not skippedSteps[i] then
			local tab, key = Resolve(trees, step)
			if not tab then
				skippedSteps[i] = "introuvable"
				if step.rank == 1 or not skippedSteps[i - 1] then
					Note("talent introuvable : " .. step.en)
				end
			else
				local t = trees[tab].talents[key]
				local rank = t.rank + (extra[key] or 0)
				if rank < step.rank and rank < t.max and t.can then
					return { tab = tab, key = key, name = t.name or step.en, rank = rank + 1, max = t.max, step = i, plan = plan,
						mode = trees.mode, configID = trees.configID }
				end
			end
		end
	end
	return nil, "plan terminé (ou rien de possible pour l'instant)", plan
end

-------------------------------------------------------------------------------
-- Apprendre
-------------------------------------------------------------------------------
local learning -- Classic : { tab, key, rank, at, name, step } ; Forever : { configID, at, names }
local ourStaged -- Forever : des rangs préparés par nous et pas encore appliqués
local waitStill, waitAccepted -- un point à mettre dès que tu ne bouges plus (Forever : l'incantation demande l'immobilité)

local function Moving()
	local speed = Num(Call(GetUnitSpeed, "player")) or 0
	return speed > 0 or (IsFalling and Call(IsFalling)) or false
end

local function LearnClassic(nextT, why)
	local before = nextT.rank - 1
	learning = { tab = nextT.tab, key = nextT.key, rank = nextT.rank, at = GetTime(), name = nextT.name, step = nextT.step }
	if not pcall(LearnTalent, nextT.tab, nextT.key) then
		skippedSteps[nextT.step] = "refusé"
		learning = nil
		return false
	end
	Note("talent " .. tostring(nextT.name) .. " " .. nextT.rank .. "/" .. nextT.max .. (why and (" (" .. why .. ")") or ""))
	C_Timer.After(1.5, function()
		local l = learning
		if l and l.tab and GetTime() - l.at >= 1.4 then
			local t = TalentInfo(l.tab, l.key)
			if t and t.rank <= before then
				skippedSteps[l.step] = "refusé par le jeu"
				Note("talent refusé par le jeu : " .. tostring(l.name))
				ns.Print("talents : le jeu n'a pas pris « " .. tostring(l.name) .. " » ; je passe au suivant du plan.")
			end
			learning = nil
		end
	end)
	ns.Print("talent appris : |cff00ff00" .. tostring(nextT.name) .. "|r (rang " .. nextT.rank .. "/" .. nextT.max .. ")")
	return true
end

local function NodeRank(configID, nodeID)
	local n = Call(C_Traits.GetNodeInfo, configID, nodeID)
	return type(n) == "table" and Num(n.currentRank) or 0
end

local function Commit(configID)
	if C_ClassTalents and C_ClassTalents.CommitConfig then
		local ok, res = pcall(C_ClassTalents.CommitConfig)
		if ok and res ~= false then
			return true
		end
	end
	if C_Traits.CommitConfig then
		local ok, res = pcall(C_Traits.CommitConfig, configID)
		return ok and res ~= false
	end
	return false
end

-- Forever : prépare tous les points libres du plan, puis les applique en une fois (une seule incantation).
local function LearnTraits(why)
	local configID = TraitIDs()
	if not configID then
		return false
	end
	if Call(C_Traits.ConfigHasStagedChanges, configID) then
		if not ourStaged then
			Note("talents : changements en cours dans la fenêtre des talents, je n'y touche pas")
			return false
		end
		Call(C_Traits.RollbackConfig, configID) -- (les nôtres, restés d'une incantation interrompue)
	end
	local extra, names = { total = 0 }, {}
	for _ = 1, 51 do
		local nextT = Auto.NextTalent(extra)
		if not nextT then
			break
		end
		local before = NodeRank(configID, nextT.key)
		local ok, res = pcall(C_Traits.PurchaseRank, configID, nextT.key)
		if not ok or res == false then
			if #names == 0 then -- (après d'autres points : sans doute plus de point libre, pas un refus)
				skippedSteps[nextT.step] = "refusé"
				Note("talent refusé : " .. tostring(nextT.name))
			end
			break
		end
		ourStaged = true
		if NodeRank(configID, nextT.key) <= before then
			-- (le jeu ne montre pas encore le rang préparé : on le compte nous-mêmes)
			extra[nextT.key] = (extra[nextT.key] or 0) + 1
			extra.total = extra.total + 1
		end
		names[#names + 1] = tostring(nextT.name) .. " " .. nextT.rank .. "/" .. nextT.max
	end
	if #names == 0 then
		return false
	end
	learning = { configID = configID, at = GetTime(), names = names }
	if not Commit(configID) then
		Call(C_Traits.RollbackConfig, configID)
		learning, ourStaged = nil, nil
		Note("talents : le jeu refuse d'appliquer (" .. table.concat(names, ", ") .. ")")
		return false
	end
	Note("talents appliqués : " .. table.concat(names, ", ") .. (why and (" (" .. why .. ")") or ""))
	ns.Print("talents : |cff00ff00" .. table.concat(names, ", ") .. "|r — reste immobile quelques secondes, le jeu les apprend.")
	return true
end

-- Le jeu a appliqué (ou refusé) nos talents.
function Auto.OnTraitsCommitted(configID, failed)
	local l = learning
	if not (l and l.configID) or (Num(configID) and Num(configID) ~= l.configID) then
		return
	end
	learning = nil
	if not failed then
		ourStaged = nil
	end
	if failed then
		Call(C_Traits.RollbackConfig, l.configID)
		ourStaged = nil
		waitStill, waitAccepted = true, true
		Note("talents pas appliqués (incantation interrompue) : nouvel essai quand tu ne bouges plus")
		ns.Print("talents : pas appris (tu as bougé ou été attaqué ?). Je réessaie dès que tu es immobile.")
	end
end

local function Learn(why)
	if InCombat() then
		Auto.pending = true
		return false
	end
	local nextT = Auto.NextTalent()
	if not nextT then
		return false
	end
	if nextT.mode == "traits" then
		if Moving() then
			waitStill = true -- (l'incantation serait interrompue : dès que tu t'arrêtes)
			return false
		end
		return LearnTraits(why)
	end
	return LearnClassic(nextT, why)
end

-- Regarde s'il y a un point à mettre ; le met (mode automatique) ou le propose (mode « demander »).
function Auto.CheckTalents(reason)
	local cfg = Cfg()
	if learning and GetTime() - (learning.at or 0) > 15 then
		learning = nil -- (le jeu n'a rien répondu : on reprend)
	end
	if cfg.talents == "non" or not Allowed("talents") or learning then
		return
	end
	if InCombat() then
		Auto.pending = true
		return
	end
	local nextT = Auto.NextTalent()
	if not nextT then
		return
	end
	if cfg.talents == "auto" or reason == "accepté" then
		Learn(reason)
		return
	end
	if snoozedAt and snoozedAt >= Level() and reason ~= "demande" then
		return
	end
	if Auto.Asking("talent") then
		return
	end
	local trees = Auto.Trees()
	local free = trees and trees.free or 1
	local tabName = trees and trees[nextT.tab] and trees[nextT.tab].name or ("arbre " .. nextT.tab)
	Auto.Ask("talent", string.format("Talent à mettre (%d point%s libre%s) :\n|cffffd200%s|r rang %d/%d (%s)\n|cff888888Plan : %s (autre plan : /iti reglages > Pilote)|r%s",
		free, free > 1 and "s" or "", free > 1 and "s" or "", tostring(nextT.name), nextT.rank, nextT.max, tostring(tabName),
		nextT.plan.label, nextT.mode == "traits" and "\n|cff888888Reste immobile quelques secondes après avoir accepté.|r" or ""), {
		{ label = "Apprendre", func = function()
			if not Learn("accepté") and waitStill then
				waitAccepted = true
				ns.Print("talents : arrête-toi une seconde, je les apprends dès que tu es immobile.")
			end
		end },
		{ label = "Plus tard", func = function()
			snoozedAt = Level()
			ns.Print("talents : je redemande au prochain niveau (ou /iti talents).")
		end },
		{ label = "Toujours", func = function()
			cfg.talents = "auto"
			ns.Print("talents : |cff00ff00automatiques|r (réglage : /iti reglages > Pilote).")
			if not Learn("accepté") and waitStill then
				waitAccepted = true
			end
		end },
	})
end

-- Attente d'immobilité (Forever) : un coup d'œil toutes les demi-secondes, seulement quand il y a un point en attente.
local stillSince
local watcher = CreateFrame("Frame")
local acc = 0
watcher:SetScript("OnUpdate", function(_, elapsed)
	acc = acc + (elapsed or 0)
	if acc < 0.5 or not waitStill then
		return
	end
	acc = 0
	if InCombat() or Moving() then
		stillSince = nil
		return
	end
	stillSince = stillSince or GetTime()
	if GetTime() - stillSince >= 1 then
		waitStill, stillSince = nil, nil
		local accepted = waitAccepted
		waitAccepted = nil
		local ok, err = pcall(Auto.CheckTalents, accepted and "accepté" or "immobile")
		if not ok and ns.OnError then
			ns.OnError("pilote (talents) : " .. tostring(err))
		end
	end
end)

-------------------------------------------------------------------------------
-- Équipement : mettre ce qui t'améliore
-------------------------------------------------------------------------------
local MIN_GAIN = 2 -- points de note
local MIN_PCT = 3 -- et au moins 3 % de mieux (sauf emplacement vide)
local refused = {} -- [itemID] = true : remis à la main ou refusé (cette session)
local lastAuto = {} -- [emplacement] = { id, at }
local equipAt = 0
local pendingBind -- { at } : objet lié quand équipé accepté par le joueur

local function ContainerItem(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		local info = Call(C_Container.GetContainerItemInfo, bag, slot)
		if type(info) == "table" then
			return info.hyperlink, info.itemID, info.isBound, info.isLocked
		end
		return nil
	end
	local _, _, locked, _, _, _, link, _, _, id, bound = Call(rawget(_G, "GetContainerItemInfo"), bag, slot)
	return link, id, bound, locked
end

local function NumSlots(bag)
	local fn = (C_Container and C_Container.GetContainerNumSlots) or rawget(_G, "GetContainerNumSlots")
	return Num(Call(fn, bag)) or 0
end

-- Lié ? true / false / nil (inconnu). Lié quand équipé ? (type de lien 2 dans les infos de l'objet)
local function BindState(link, bound)
	local _, _, _, _, _, _, _, _, _, _, _, _, _, bindType = Call((C_Item and C_Item.GetItemInfo) or rawget(_G, "GetItemInfo"), link)
	local isBound = nil
	if bound == true or bound == false then
		isBound = bound
	end
	return isBound, Num(bindType) == 2
end

local function HasUse(link)
	local fn = (C_Item and C_Item.GetItemSpell) or rawget(_G, "GetItemSpell")
	local spell = Call(fn, link)
	return spell ~= nil
end

local function WornLink(slot)
	return Call(GetInventoryItemLink, "player", slot)
end

local function IdOf(link)
	return tonumber(tostring(link or ""):match("item:(%d+)"))
end

-- Les meilleurs objets des sacs à mettre maintenant : celui qui ne se lie pas (ou l'est déjà), et celui qui se lierait
-- en le mettant (« lié quand équipé ») : { link, id, e (évaluation), bag, slot, boe }.
function Auto.BestUpgrade()
	local G = ns.Gear
	if not (G and G.Evaluate) then
		return nil
	end
	local ignored = G.Config and G.Config().ignored or {}
	local best, bestBoE
	for bag = 0, 4 do
		for slot = 1, NumSlots(bag) do
			local link, id, bound, locked = ContainerItem(bag, slot)
			id = id or IdOf(link)
			if link and id and not locked and not refused[id] and not ignored[id] then
				local e = G.Evaluate(link, { now = true })
				if e and e.gain >= MIN_GAIN and (e.empty or (e.pct or 0) >= MIN_PCT) then
					local worn = WornLink(e.slot)
					if e.empty or not (worn and HasUse(worn)) then -- (un objet à effet « Utiliser » porté : à toi de voir)
						local isBound, boe = BindState(link, bound)
						local u = { link = link, id = id, e = e, bag = bag, slot = slot, boe = boe and isBound ~= true }
						if u.boe then
							if not bestBoE or e.gain > bestBoE.e.gain then
								bestBoE = u
							end
						elseif not best or e.gain > best.e.gain then
							best = u
						end
					end
				end
			end
		end
	end
	return best, bestBoE
end

local function Equip(u)
	if InCombat() or Call(UnitIsDeadOrGhost, "player") then
		Auto.pending = true
		return false
	end
	if Call(rawget(_G, "CursorHasItem")) or Call(rawget(_G, "UnitCastingInfo"), "player") then
		C_Timer.After(2, function()
			Auto.Soon(0)
		end) -- (tu tiens un objet ou tu incantes : plus tard)
		return false
	end
	equipAt = GetTime()
	lastAuto[u.e.slot] = { id = u.id, at = equipAt }
	local ok
	local pickup = C_Container and C_Container.PickupContainerItem
	local toSlot = rawget(_G, "EquipCursorItem")
	if pickup and toSlot then
		-- prendre CET objet-là (deux objets identiques : « par le nom » pourrait prendre l'autre) et le mettre
		ok = pcall(pickup, u.bag, u.slot) and Call(rawget(_G, "CursorHasItem")) and pcall(toSlot, u.e.slot) or false
		if Call(rawget(_G, "CursorHasItem")) then
			Call(rawget(_G, "ClearCursor"))
		end
	else
		local fn = (C_Item and C_Item.EquipItemByName) or rawget(_G, "EquipItemByName")
		ok = pcall(fn, u.link, u.e.slot)
	end
	if ok then
		Note("équipé " .. tostring(u.e.name) .. " (" .. u.e.slotName .. ")")
		ns.Print("équipé : " .. tostring(u.link) .. " |cff00ff00" .. ns.Gear.GainText(u.e) .. "|r (" .. u.e.slotName
			.. ") — remets l'ancien si tu préfères : je n'y toucherai plus.")
	end
	return ok
end

function Auto.CheckGear()
	local cfg = Cfg()
	if not Allowed("equip") then
		return
	end
	if InCombat() then
		Auto.pending = true
		return
	end
	local free, u = Auto.BestUpgrade()
	if free then
		Equip(free) -- (un objet à la fois : la suite au prochain BAG_UPDATE_DELAYED)
		return
	end
	if not u or cfg.equipBoE == "non" then
		return
	end
	if cfg.equipBoE == "auto" then
		pendingBind = { at = GetTime() }
		Equip(u)
		return
	end
	if Auto.Asking("equip" .. u.id) then
		return
	end
	Auto.Ask("equip" .. u.id, string.format("Équiper %s ?\n|cff00ff00%s|r pour toi (%s).\n|cff888888Il deviendra lié à toi (lié quand équipé) : il ne se revendra plus à l'hôtel des ventes.|r",
		tostring(u.link), ns.Gear.GainText(u.e), u.e.slotName), {
		{ label = "Équiper", func = function()
			pendingBind = { at = GetTime() }
			Equip(u)
		end },
		{ label = "Non", func = function()
			refused[u.id] = true
		end },
	})
end

-- Le joueur remet un autre objet là où le pilote vient d'en mettre un : on ne touche plus à cet objet.
function Auto.OnEquipmentChanged(slot)
	slot = Num(slot)
	local mine = slot and lastAuto[slot]
	if not mine or GetTime() - equipAt < 3 then
		return
	end
	local now = IdOf(WornLink(slot))
	if now ~= mine.id then
		refused[mine.id] = true
		lastAuto[slot] = nil
		Note("objet remis à la main : " .. mine.id .. " laissé de côté")
	end
end

-- Blizzard demande de confirmer un objet « lié quand équipé » : le joueur a déjà dit oui dans notre question.
function Auto.OnBindConfirm(slot)
	if pendingBind and GetTime() - pendingBind.at < 3 then
		pendingBind = nil
		local fn = rawget(_G, "EquipPendingItem")
		if type(fn) == "function" and pcall(fn, slot) then
			Call(rawget(_G, "StaticPopup_Hide"), "EQUIP_BIND")
		end -- (sinon la fenêtre du jeu reste : un clic de plus)
	end
end

-------------------------------------------------------------------------------
-- Sacs : un sac des sacs va dans un emplacement de sac libre
-------------------------------------------------------------------------------
local function FreeBagSlot()
	for bag = 1, 4 do
		local fn = (C_Container and C_Container.ContainerIDToInventoryID) or rawget(_G, "ContainerIDToInventoryID")
		local inv = Num(Call(fn, bag))
		if inv and not Call(GetInventoryItemID, "player", inv) then
			return inv
		end
	end
	return nil
end

function Auto.CheckBags()
	if not Allowed("bags") or InCombat() then
		return
	end
	local inv = FreeBagSlot()
	if not inv then
		return
	end
	local best
	for bag = 0, 4 do
		for slot = 1, NumSlots(bag) do
			local link, id, _, locked = ContainerItem(bag, slot)
			if link and not locked then
				local G = ns.Gear
				local inst = G and G.Instant and G.Instant(link)
				local info = G and G.Info and G.Info(link)
				-- (sacs ordinaires seulement : pas de carquois, giberne, sac d'âmes ou de métier)
				if inst and inst.classID == 1 and inst.subclassID == 0 and info then
					if not best or info.ilvl > best.ilvl then
						best = { link = link, id = id, bag = bag, slot = slot, ilvl = info.ilvl }
					end
				end
			end
		end
	end
	if not best then
		return
	end
	local pickup = (C_Container and C_Container.PickupContainerItem) or rawget(_G, "PickupContainerItem")
	if pcall(pickup, best.bag, best.slot) and pcall(PutItemInBag, inv) then
		Note("sac mis : " .. tostring(best.link))
		ns.Print("sac mis : " .. tostring(best.link) .. ".")
	end
	if CursorHasItem and Call(CursorHasItem) then
		Call(ClearCursor)
	end
end

-------------------------------------------------------------------------------
-- Événements
-------------------------------------------------------------------------------
local timer
local function Soon(delay)
	if timer then
		return
	end
	timer = true
	C_Timer.After(delay or 0.6, function()
		timer = nil
		if not ns.ready then
			return
		end
		Auto.pending = false
		for _, fn in ipairs({ Auto.CheckTalents, Auto.CheckGear, Auto.CheckBags }) do
			local ok, err = pcall(fn)
			if not ok and ns.OnError then
				ns.OnError("pilote (talents / équipement) : " .. tostring(err))
			end
		end
	end)
end
Auto.Soon = Soon

local events = CreateFrame("Frame")
local HANDLERS = {
	PLAYER_LEVEL_UP = function()
		Soon(1.5)
	end,
	CHARACTER_POINTS_CHANGED = function()
		learning = nil
		Soon(0.6)
	end,
	BAG_UPDATE_DELAYED = function()
		Soon(0.8)
	end,
	PLAYER_EQUIPMENT_CHANGED = function(slot)
		Auto.OnEquipmentChanged(slot)
	end,
	EQUIP_BIND_CONFIRM = function(slot)
		Auto.OnBindConfirm(slot)
	end,
	AUTOEQUIP_BIND_CONFIRM = function(slot)
		Auto.OnBindConfirm(slot)
	end,
	-- Forever : nos talents appliqués, ou l'incantation interrompue
	TRAIT_CONFIG_UPDATED = function(configID)
		Auto.OnTraitsCommitted(configID, false)
		Soon(0.8)
	end,
	CONFIG_COMMIT_FAILED = function(configID)
		Auto.OnTraitsCommitted(configID, true)
	end,
	PLAYER_REGEN_ENABLED = function()
		if Auto.pending then
			Soon(1)
		end
		ShowNext()
	end,
}
for event in pairs(HANDLERS) do
	pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...)
	local fn = HANDLERS[event]
	if not (fn and ns.ready) then
		return
	end
	local ok, err = pcall(fn, ...)
	if not ok and ns.OnError then
		ns.OnError("pilote (" .. event .. ") : " .. tostring(err))
	end
end)

-- Au démarrage (Questie prêt) : un premier tour quelques secondes après.
function Auto.Init()
	C_Timer.After(6, function()
		Soon(0)
	end)
end

-- /iti talents : où en est le plan.
function Auto.TalentsText()
	local plan, key = Auto.Plan()
	if not plan then
		return "talents : pas encore de plan pour ta classe (guerrier pour l'instant)."
	end
	local nextT, why = Auto.NextTalent()
	local mode = Cfg().talents
	return string.format("talents : plan « %s » · mode %s · %s", plan.label,
		mode == "auto" and "automatique" or mode == "non" and "coupé" or "je demande",
		nextT and ("prochain : " .. tostring(nextT.name) .. " " .. nextT.rank .. "/" .. nextT.max) or tostring(why))
end

function Auto.ReportLine()
	local cfg = Cfg()
	local trees = Auto.Trees()
	local parts = {}
	for tab, t in ipairs(trees or {}) do
		parts[#parts + 1] = tostring(t.name or tab) .. " " .. t.points
	end
	local skipped = {}
	for i, why in pairs(skippedSteps) do
		skipped[#skipped + 1] = i .. "=" .. why
	end
	return Auto.TalentsText() .. " · arbres " .. table.concat(parts, "/") .. (trees and (" · libres " .. trees.free) or "")
		.. (#skipped > 0 and (" · pas sautés " .. table.concat(skipped, ",")) or "")
		.. " · équipement auto " .. (cfg.equip ~= false and "oui" or "non") .. " (lié quand équipé : " .. tostring(cfg.equipBoE) .. ")"
		.. " · sacs " .. (cfg.bags ~= false and "oui" or "non")
		.. (#Auto.log > 0 and ("\n  dernières actions : " .. table.concat(Auto.log, " | ")) or "")
end
