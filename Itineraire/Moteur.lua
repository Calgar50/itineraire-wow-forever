-- Itinéraire : moteur interne. Il refait ce qu'Itinéraire prenait jusqu'ici dans les modules internes de Questie, en
-- ne lisant que la base publique QuestieDB (LibQuestieDB : bibliothèque séparée, contrat versionné, recommandée par
-- l'équipe de Questie aux autres addons). Questie devient facultatif.
--
-- Logique adaptée de Questie (GPL v3, github.com/Questie/Questie) : QuestieDB.GetQuest / GetNPC / IsDoable,
-- AvailableQuests (+ IsLevelRequirementsFulfilled), zoneDB, QuestieXP, QuestiePlayer, QuestieProfessions,
-- QuestieReputation, Townsfolk et ClassTrainers (WoW Forever). Listes de politique (quêtes cachées, étiquettes) :
-- Donnees/Politique.lua, produit par outils/politique_questie.py.
--
-- Même forme que les modules de Questie qu'il remplace (M.DB, M.Zone, M.XP, M.Avail…) : Data.lua choisit l'un ou
-- l'autre, le reste d'Itinéraire ne voit pas la différence.
local _, ns = ...
local Moteur = {}
ns.Moteur = Moteur

local CONTRACT = 4 -- version du contrat QuestieDB pour laquelle ce moteur est écrit
local L, why

local function Call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c = pcall(fn, ...)
	if ok then
		return a, b, c
	end
	return nil
end

-- La bibliothèque QuestieDB, si elle est là et compatible (sinon nil, et Moteur.Why() dit pourquoi).
function Moteur.Lib()
	if L then
		return L
	end
	local lib = rawget(_G, "LibQuestieDB")
	if type(lib) ~= "table" then
		why = "QuestieDB absent (l'addon QuestieDB est-il activé ?)"
		return nil
	end
	if type(lib.RequireContract) == "function" then
		local ok, good, msg = pcall(lib.RequireContract, CONTRACT)
		if not ok or not good then
			why = "QuestieDB incompatible : " .. tostring(msg or good)
			return nil
		end
	end
	for _, entity in ipairs({ "Quest", "Npc", "Object", "Item" }) do
		local e = lib[entity]
		if type(e) ~= "table" or type(e.Get) ~= "function" or type(e.GetAllIds) ~= "function" then
			why = "QuestieDB : API incomplète (" .. entity .. ")"
			return nil
		end
	end
	L, why = lib, nil
	return L
end

function Moteur.Ready()
	return Moteur.Lib() ~= nil
end

function Moteur.Why()
	return why
end

local function Get(entity, id, key)
	if not (L and type(id) == "number") then
		return nil
	end
	return Call(L[entity].Get, id, key)
end

local function Q(id, key)
	return Get("Quest", id, key)
end

-- Bit d'un masque (arithmétique : les races de Forever dépassent les 32 bits des opérations bit à bit).
local function HasBit(mask, flag)
	return mask % (flag * 2) >= flag
end

-- Noms des champs d'une entité, dans l'ordre de la base.
local names = {}
local function Names(entity, field)
	if names[entity] then
		return names[entity]
	end
	local meta = L and L.Meta and L.Meta[entity .. "Meta"]
	local keys = meta and meta[field]
	local pairsList = {}
	for name, index in pairs(type(keys) == "table" and keys or {}) do
		if type(name) == "string" and type(index) == "number" then
			pairsList[#pairsList + 1] = { index, name }
		end
	end
	table.sort(pairsList, function(a, b)
		return a[1] < b[1]
	end)
	local list = {} -- (sans trou : GetAll compte les champs avec #)
	for k, p in ipairs(pairsList) do
		list[k] = p[2]
	end
	names[entity] = list
	return list
end

local function Fill(entity, field, id, out)
	local list = Names(entity, field)
	local raw = Call(L[entity].GetAll, id, list)
	if type(raw) ~= "table" then
		return nil
	end
	for i, name in ipairs(list) do
		out[name] = raw[i]
	end
	return out
end

-------------------------------------------------------------------------------
-- Joueur : race, classe, métiers, réputations, sorts
-------------------------------------------------------------------------------
local Player = {}
Moteur.Player = Player

local function RaceFlag()
	local raceId = UnitRace and select(3, UnitRace("player"))
	local masks = L and L.Enum and L.Enum.raceMaskById
	return type(masks) == "table" and masks[raceId] or nil
end

function Player.HasRequiredRace(mask)
	mask = tonumber(mask)
	if not mask or mask == 0 then
		return true
	end
	local flag = RaceFlag()
	if not flag then
		return true -- race inconnue de la base : on ne retire rien
	end
	return HasBit(mask, flag)
end

function Player.HasRequiredClass(mask)
	mask = tonumber(mask)
	if not mask or mask == 0 then
		return true
	end
	local classId = UnitClass and select(3, UnitClass("player"))
	if type(classId) ~= "number" or classId < 1 then
		return true
	end
	return HasBit(mask, 2 ^ (classId - 1))
end

-- Métiers : { [ligne de compétence] = { rank, max } } (lus par Gear, quelques secondes en cache).
local profs, profsAt = nil, -100
local function Professions()
	local now = GetTime and GetTime() or 0
	if profs and now - profsAt < 5 then
		return profs
	end
	local out = {}
	local ok, skills = pcall(function()
		return ns.Gear.ReadProfessions()
	end)
	for line, s in pairs(ok and type(skills) == "table" and skills or {}) do
		if type(s) == "table" then
			out[line] = { rank = tonumber(s.rank) or 0, max = tonumber(s.max) or 0 }
		end
	end
	profs, profsAt = out, now
	return out
end

local ProfessionsModule = {}
Moteur.Professions = ProfessionsModule
function ProfessionsModule:HasProfessionAndSkillLevel(required)
	if type(required) ~= "table" then
		return true, true
	end
	local p = Professions()[required[1]]
	return p ~= nil, p ~= nil and p.rank >= (tonumber(required[2]) or 0)
end

-- Rangs de métier (1 apprenti, 2 compagnon, 3 expert, 4 artisan…) d'après la compétence maximum.
local function RankOf(p)
	return p and math.floor((p.max or 0) / 75) or 0
end

function ProfessionsModule:HasProfessionAndRankLevel(ranks)
	if type(ranks) ~= "table" then
		return true, true, false
	end
	local has, hasRank, negative = false, false, false
	for _, r in ipairs(ranks) do
		local p = Professions()[r[1]]
		local level = tonumber(r[2]) or 0
		if level < 0 then
			negative = true
			level = -level
			if p then
				has = true
				hasRank = hasRank or RankOf(p) == level
			end
		elseif p then
			has = true
			hasRank = hasRank or RankOf(p) >= level
		end
	end
	if negative and has then
		hasRank = not hasRank
	end
	return has, hasRank, negative
end

-- Réputation (valeur absolue de la barre, comme Questie ; faction inconnue = 0).
local function RepValue(factionId)
	if GetFactionInfoByID then
		local ok, name, _, _, _, _, bar = pcall(GetFactionInfoByID, factionId)
		if ok and name and type(bar) == "number" then
			return bar
		end
	end
	if C_Reputation and C_Reputation.GetFactionDataByID then
		local data = Call(C_Reputation.GetFactionDataByID, factionId)
		if type(data) == "table" and type(data.currentStanding) == "number" then
			return data.currentStanding
		end
	end
	return 0
end

local function ReputationOK(minRep, maxRep)
	if type(minRep) == "table" and RepValue(minRep[1]) < (tonumber(minRep[2]) or 0) then
		return false
	end
	if type(maxRep) == "table" and RepValue(maxRep[1]) >= (tonumber(maxRep[2]) or 0) then
		return false
	end
	return true
end

local function SpellKnown(id)
	if C_SpellBook and C_SpellBook.IsSpellKnown and Call(C_SpellBook.IsSpellKnown, id) then
		return true
	end
	if IsSpellKnown and Call(IsSpellKnown, id) then
		return true
	end
	return IsPlayerSpell and Call(IsPlayerSpell, id) and true or false
end

-------------------------------------------------------------------------------
-- Quêtes faites, quêtes du journal
-------------------------------------------------------------------------------
local completed
local turnedIn = {} -- rendues pendant la session (le jeu peut tarder à les compter)
local function Completed()
	if completed then
		return completed
	end
	completed = {}
	for id in pairs(turnedIn) do
		completed[id] = true
	end
	local ids = C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs and Call(C_QuestLog.GetAllCompletedQuestIDs)
	if type(ids) == "table" then
		for _, id in ipairs(ids) do
			completed[id] = true
		end
	elseif GetQuestsCompleted then
		local ok, map = pcall(GetQuestsCompleted)
		for id, v in pairs(ok and type(map) == "table" and map or {}) do
			if v then
				completed[id] = true
			end
		end
	end
	return completed
end

function Moteur.IsCompleted(id)
	if Completed()[id] then
		return true
	end
	return C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and Call(C_QuestLog.IsQuestFlaggedCompleted, id) and true
		or false
end

local function ActiveQuests()
	local active, failed = {}, {}
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then
		return active, failed
	end
	for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and info.questID then
			active[info.questID] = true
			if C_QuestLog.IsFailed and Call(C_QuestLog.IsFailed, info.questID) then
				failed[info.questID] = true
			end
		end
	end
	return active, failed
end

-------------------------------------------------------------------------------
-- Politique : quêtes cachées, étiquettes (élite, donjon, raid, JcJ)
-------------------------------------------------------------------------------
local function Hidden()
	return ns.ext and type(ns.ext.CACHEES) == "table" and ns.ext.CACHEES or {}
end

function Moteur.Hidden(id)
	return Hidden()[id] and true or false
end

local tags = {}
local function Tag(id)
	local t = tags[id]
	if t ~= nil then
		return t
	end
	local fix = ns.ext and type(ns.ext.TAGS) == "table" and ns.ext.TAGS[id]
	if fix then
		tags[id] = fix
		return fix
	end
	local tag
	if C_QuestLog and C_QuestLog.GetQuestTagInfo then
		local info = Call(C_QuestLog.GetQuestTagInfo, id)
		tag = type(info) == "table" and info.tagID or nil
	elseif GetQuestTagInfo then
		tag = Call(GetQuestTagInfo, id)
	end
	if type(tag) == "number" then
		tags[id] = tag -- (rien de connu : redemandé la prochaine fois, le jeu charge la quête entre-temps)
	end
	return tag
end

-------------------------------------------------------------------------------
-- Entités : quêtes, PNJ, objets du monde, objets (même forme que QuestieDB de Questie)
-------------------------------------------------------------------------------
local DB = { autoBlacklist = {} }
Moteur.DB = DB

local function Effective(level, required, playerLevel)
	level, required = tonumber(level), tonumber(required) or 0
	if level == -1 then
		playerLevel = playerLevel or (UnitLevel and UnitLevel("player")) or 1
		if required > playerLevel then
			return required, required
		end
		return playerLevel, playerLevel
	end
	return level, required
end

local function First(name)
	local t = L and L.ObjectiveFirst and L.ObjectiveFirst[name]
	return type(t) == "table" and t or {}
end

local function ObjectiveData(id, objectives, triggerEnd)
	local data = {}
	local function Add(entry, first)
		if first then
			table.insert(data, 1, entry)
		else
			data[#data + 1] = entry
		end
	end
	objectives = type(objectives) == "table" and objectives or {}
	for _, o in pairs(objectives[1] or {}) do
		Add({ Type = "monster", Id = o[1], Text = o[2] })
	end
	for _, o in pairs(objectives[2] or {}) do
		Add({ Type = "object", Id = o[1], Text = o[2] }, First("objectObjectiveFirst")[id])
	end
	for _, o in pairs(objectives[3] or {}) do
		Add({ Type = "item", Id = o[1], Text = o[2] }, First("itemObjectiveFirst")[id])
	end
	if type(objectives[4]) == "table" and objectives[4][1] then
		Add({ Type = "reputation", Id = objectives[4][1], RequiredRepValue = objectives[4][2] })
	end
	if type(objectives[5]) == "table" then
		for _, o in pairs(objectives[5]) do
			Add({ Type = "killcredit", IdList = o[1], RootId = o[2], Text = o[3] }, First("killCreditObjectiveFirst")[id])
		end
	end
	for _, o in pairs(objectives[6] or {}) do
		Add({ Type = "spell", Id = o[1], Text = o[2], ItemSourceId = o[3] }, First("spellObjectiveFirst")[id])
	end
	if type(triggerEnd) == "table" then
		Add({ Type = "event", Text = triggerEnd[1], Coordinates = triggerEnd[2] }, First("eventObjectiveFirst")[id])
	end
	return data
end

local questCache = {}
function DB.GetQuest(id)
	if not (Moteur.Lib() and type(id) == "number") then
		return nil
	end
	local cached = questCache[id]
	if cached then
		return cached
	end
	local quest = Fill("Quest", "questKeys", id, { Id = id })
	if not quest then
		return nil
	end
	quest.level, quest.requiredLevel = Effective(quest.questLevel, quest.requiredLevel)
	local starts, finish = type(quest.startedBy) == "table" and quest.startedBy or {},
		type(quest.finishedBy) == "table" and quest.finishedBy or {}
	quest.Starts = { NPC = starts[1], GameObject = starts[2], Item = starts[3] }
	quest.Finisher = { NPC = finish[1], GameObject = finish[2] }
	quest.isHidden = Moteur.Hidden(id)
	quest.IsRepeatable = (tonumber(quest.specialFlags) or 0) % 2 == 1
	quest.Description = quest.objectivesText
	quest.ObjectiveData = ObjectiveData(id, quest.objectives, quest.triggerEnd)
	quest.Objectives, quest.SpecialObjectives = {}, {} -- (positions : Data les tire d'ObjectiveData)
	questCache[id] = quest
	return quest
end

local function Friendly(side)
	if not side or side == "AH" then
		return true
	end
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	return (side == "H" and faction == "Horde") or (side == "A" and faction == "Alliance")
end

local npcCache = {}
function DB:GetNPC(id)
	if not (Moteur.Lib() and type(id) == "number") then
		return nil
	end
	if npcCache[id] then
		return npcCache[id]
	end
	local npc = Fill("Npc", "npcKeys", id, { id = id, type = "monster" })
	if not npc then
		return nil
	end
	npc.friendly = Friendly(npc.friendlyToFaction)
	npcCache[id] = npc
	return npc
end

function DB:GetObject(id)
	if not (Moteur.Lib() and type(id) == "number") then
		return nil
	end
	local object = Fill("Object", "objectKeys", id, { id = id, type = "object" })
	if not object then
		return nil
	end
	-- Questie vide les positions des filons et des plantes dans la base partagée (il ne les affiche pas) : on reprend
	-- alors celles de la base d'origine.
	if (type(object.spawns) ~= "table" or next(object.spawns) == nil) and L.Object.GetRaw then
		local raw = Call(L.Object.GetRaw, id, "spawns")
		if type(raw) == "table" and next(raw) then
			object.spawns = raw
		end
	end
	return object
end

local itemCache = {}
function DB:GetItem(id)
	if not (Moteur.Lib() and type(id) == "number" and id ~= 0) then
		return nil
	end
	if itemCache[id] then
		return itemCache[id]
	end
	local item = Fill("Item", "itemKeys", id, { Id = id, Sources = {} })
	if not item then
		return nil
	end
	itemCache[id] = item
	return item
end

function DB.QueryQuestSingle(id, key)
	return Get("Quest", id, key)
end
function DB.QueryNPCSingle(id, key)
	return Get("Npc", id, key)
end
function DB.QueryItemSingle(id, key)
	return Get("Item", id, key)
end
function DB.QueryObjectSingle(id, key)
	return Get("Object", id, key)
end

function DB.IsRepeatable(id)
	return (tonumber(Q(id, "specialFlags")) or 0) % 2 == 1
end
function DB.IsGroupQuest(id)
	return Tag(id) == 1
end
function DB.IsPvPQuest(id)
	return Tag(id) == 41
end
function DB.IsDungeonQuest(id)
	return Tag(id) == 81
end
function DB.IsRaidQuest(id)
	local t = Tag(id)
	return t == 62 or t == 88 or t == 89
end

-------------------------------------------------------------------------------
-- Zones (tables de QuestieDB : zones -> cartes, sous-zones, donjons)
-------------------------------------------------------------------------------
local Zone = {}
Moteur.Zone = Zone
local zones

local function Decode(v)
	if type(v) == "table" then
		return v
	end
	if type(v) == "string" and loadstring then
		local fn = loadstring(v)
		local ok, t = pcall(fn or error)
		if ok and type(t) == "table" then
			return t
		end
	end
	return {}
end

local function Zones()
	if zones then
		return zones
	end
	local support = L and L.Support and Call(L.Support.Get, "ZoneDB")
	local p = type(support) == "table" and type(support.private) == "table" and support.private or {}
	local toMap = Decode(p.areaIdToUiMapId)
	for k, v in pairs(Decode(p.areaIdToUiMapIdOverride)) do
		toMap[k] = v
	end
	local parent = Decode(p.subZoneToParentZone)
	for k, v in pairs(Decode(p.subZoneToParentZoneOverride)) do
		parent[k] = v
	end
	local dungeons = Decode(p.dungeons)
	local alt = {}
	for areaId, d in pairs(dungeons) do
		for _, other in ipairs(type(d) == "table" and type(d[2]) == "table" and d[2] or {}) do
			alt[other] = areaId
		end
	end
	zones = { toMap = toMap, parent = parent, dungeons = dungeons, alt = alt }
	return zones
end

function Zone:GetUiMapIdByAreaId(areaId)
	local map = Zones().toMap[areaId]
	return map ~= 0 and map or nil
end

function Zone:GetDungeons()
	return Zones().dungeons
end

local function Dungeon(areaId)
	local z = Zones()
	return z.dungeons[areaId] or (z.alt[areaId] and z.dungeons[z.alt[areaId]]), z.alt[areaId] or areaId
end

function Zone:GetDungeonLocation(areaId)
	local d = Dungeon(areaId)
	return type(d) == "table" and d[4] or nil
end

function Zone:GetLocalizedDungeonName(areaId)
	local d, real = Dungeon(areaId)
	if type(d) ~= "table" then
		return nil
	end
	local name = C_Map and C_Map.GetAreaInfo and Call(C_Map.GetAreaInfo, real)
	return name or d[1]
end

function Zone:GetParentZoneId(areaId)
	local z = Zones()
	return z.alt[areaId] or z.parent[areaId]
end

-------------------------------------------------------------------------------
-- XP des quêtes (table de QuestieDB, règles de cmangos reprises de QuestieXP)
-------------------------------------------------------------------------------
local XP = {}
Moteur.XP = XP

function XP:GetQuestLogRewardXP(id, ignorePlayerLevel)
	local support = L and L.Support and Call(L.Support.Get, "QuestXP")
	local db = type(support) == "table" and type(support.db) == "table" and support.db or {}
	local e = db[id]
	local qLevel, xp = type(e) == "table" and tonumber(e[1]), type(e) == "table" and tonumber(e[2])
	if not (qLevel and xp and qLevel > 0 and xp > 0) then
		return 0
	end
	local char = UnitLevel and UnitLevel("player") or 1
	local maxLevel = GetMaxPlayerLevel and Call(GetMaxPlayerLevel) or 60
	if char >= maxLevel and not ignorePlayerLevel then
		return 0
	end
	local mult = math.max(1, math.min(10, 2 * (qLevel - char) + 20))
	xp = xp * mult / 10
	if xp <= 100 then
		xp = 5 * math.floor((xp + 2) / 5)
	elseif xp <= 500 then
		xp = 10 * math.floor((xp + 5) / 10)
	elseif xp <= 1000 then
		xp = 25 * math.floor((xp + 12) / 25)
	else
		xp = 50 * math.floor((xp + 25) / 50)
	end
	return math.floor(xp)
end

-------------------------------------------------------------------------------
-- Quêtes que tu peux prendre maintenant (AvailableQuests + IsDoable de Questie)
-------------------------------------------------------------------------------
local Avail = { __availableQuests = {} }
Moteur.Avail = Avail

local function GreenMin(level)
	local range = GetQuestGreenRange and Call(GetQuestGreenRange, "player")
	if type(range) == "number" then
		return level - range
	end
	local gray = ns.Planner and ns.Planner.GrayLevel and ns.Planner.GrayLevel(level)
	return type(gray) == "number" and gray + 1 or level - 8
end

local function PreSingleOK(list, done)
	if type(list) ~= "table" or next(list) == nil then
		return true
	end
	for _, pre in ipairs(list) do
		if done[pre] then
			return true
		end
	end
	return false
end

local function PreGroupOK(list, done)
	if type(list) ~= "table" or next(list) == nil then
		return true
	end
	for _, pre in ipairs(list) do
		if pre < 0 then
			if not done[-pre] then
				return false
			end
		elseif not done[pre] then
			-- une quête exclusive à la quête requise, déjà faite, compte aussi
			local any = false
			for _, other in ipairs(Q(pre, "exclusiveTo") or {}) do
				any = any or done[other] and true or false
			end
			if not any then
				return false
			end
		end
	end
	return true
end

local function LevelOK(id, minLevel, maxLevel, level, active)
	local qLevel, req = Effective(Q(id, "questLevel"), Q(id, "requiredLevel"), level)
	if not qLevel then
		return false
	end
	if req == 0 then
		req = qLevel
	end
	local parent = Q(id, "parentQuest")
	if parent and parent ~= 0 and active[parent] then
		return true
	end
	if maxLevel >= qLevel then
		if minLevel > qLevel then
			return false -- trop basse (grise)
		end
	elseif maxLevel < req then
		return false
	end
	if maxLevel < req then
		return false
	end
	local reqMax = tonumber(Q(id, "requiredMaxLevel")) or 0
	return not (reqMax ~= 0 and level > reqMax)
end

-- Une quête pas encore prise : faisable par ce personnage maintenant ? (ordre de QuestieDB.IsDoable)
local function Doable(id, done, active)
	if not Player.HasRequiredRace(Q(id, "requiredRaces")) then
		return false, "race"
	end
	local single = Q(id, "preQuestSingle")
	if single and not PreSingleOK(single, done) then
		return false, "prérequis"
	end
	if not Player.HasRequiredClass(Q(id, "requiredClasses")) then
		return false, "classe"
	end
	local minRep, maxRep = Q(id, "requiredMinRep"), Q(id, "requiredMaxRep")
	if (minRep or maxRep) and not ReputationOK(minRep, maxRep) then
		return false, "réputation"
	end
	local skill = Q(id, "requiredSkill")
	if skill then
		local has, level = ProfessionsModule:HasProfessionAndSkillLevel(skill)
		if not (has and level) then
			return false, "métier"
		end
	end
	local ranks = Q(id, "requiredRanks")
	if ranks then
		local has, rank, negative = ProfessionsModule:HasProfessionAndRankLevel(ranks)
		if (not negative and not (has and rank)) or (negative and has and not rank) then
			return false, "rang de métier"
		end
	end
	if not single and not PreGroupOK(Q(id, "preQuestGroup"), done) then
		return false, "prérequis"
	end
	local parent = Q(id, "parentQuest")
	if parent and parent ~= 0 and not active[parent] then
		return false, "quête parente"
	end
	local nextQ = Q(id, "nextQuestInChain")
	if nextQ and nextQ ~= 0 and (done[nextQ] or active[nextQ]) then
		return false, "suite déjà faite"
	end
	for _, other in ipairs(Q(id, "exclusiveTo") or {}) do
		if done[other] or active[other] then
			return false, "exclusive"
		end
	end
	local spell = tonumber(Q(id, "requiredSpell"))
	if spell and spell ~= 0 then
		local known = SpellKnown(math.abs(spell))
		if (spell > 0 and not known) or (spell < 0 and known) then
			return false, "sort"
		end
	end
	local crumbFor = Q(id, "breadcrumbForQuestId")
	if crumbFor and crumbFor ~= 0 and (done[crumbFor] or active[crumbFor]) then
		return false, "piste déjà suivie"
	end
	for _, crumb in ipairs(Q(id, "breadcrumbs") or {}) do
		if active[crumb] then
			return false, "piste en cours"
		end
	end
	local disabledBy = Q(id, "disabledByQuest")
	if disabledBy and disabledBy ~= 0 and active[disabledBy] then
		return false, "bloquée"
	end
	local untilDone = Q(id, "availableUntilCompleted")
	if untilDone and untilDone ~= 0 and done[untilDone] then
		return false, "plus disponible"
	end
	local startingWith = Q(id, "availableStartingWith")
	if startingWith and startingWith ~= 0 and not (done[startingWith] or active[startingWith]) then
		return false, "pas encore disponible"
	end
	return true
end
Moteur.Doable = Doable

-- Suites d'une quête du journal (« childQuests ») : disponibles tant que la quête parente est en cours.
local function Children(id, done, active, hidden, out)
	for _, child in ipairs(Q(id, "childQuests") or {}) do
		if not (done[child] or active[child] or hidden[child]) and Player.HasRequiredRace(Q(child, "requiredRaces")) then
			local blocked = false
			for _, other in ipairs(Q(child, "exclusiveTo") or {}) do
				blocked = blocked or done[other] or active[other] or false
			end
			if not blocked then
				local single = Q(child, "preQuestSingle")
				local ok
				if single then
					ok = PreSingleOK(single, done)
				else
					ok = PreGroupOK(Q(child, "preQuestGroup"), done)
				end
				if ok then
					out[child] = true
				end
			end
		end
	end
end

-- Recalcule toute la liste (toute la base : à lancer dans une coroutine avec `yield`).
function Moteur.ComputeAvailable(yield)
	local lib = Moteur.Lib()
	if not lib then
		return nil
	end
	completed = nil
	local done = Completed()
	local active, failed = ActiveQuests()
	local hidden = Hidden()
	local level = UnitLevel and UnitLevel("player") or 1
	local minLevel, maxLevel = GreenMin(level), level
	local out, n, count = {}, 0, 0
	for id in pairs(Call(lib.Quest.GetAllIds, true) or {}) do
		n = n + 1
		if yield and n % 60 == 0 then
			yield()
		end
		if type(id) == "number" then
			if active[id] then
				Children(id, done, active, hidden, out)
			elseif not (done[id] or hidden[id]) and not DB.IsRepeatable(id)
				and LevelOK(id, minLevel, maxLevel, level, active) and Doable(id, done, active)
				and not DB.IsPvPQuest(id) and not DB.IsRaidQuest(id) then
				out[id] = true
			end
		end
	end
	for id in pairs(failed) do
		out[id] = true -- (une quête échouée se reprend)
	end
	for _ in pairs(out) do
		count = count + 1
	end
	Avail.__availableQuests = out
	Moteur.availCount, Moteur.availLevel = count, level
	Moteur.availAt = GetTime and GetTime() or 0
	return out
end

-------------------------------------------------------------------------------
-- Habitants des villes : réparateurs, aubergistes, maîtres de vol (drapeaux des PNJ), maîtres de classe
-------------------------------------------------------------------------------
-- Maîtres de classe de WoW Forever (ClassTrainers.lua de Questie).
local CLASS_TRAINERS = {
	WARRIOR = { 911, 912, 913, 914, 985, 1229, 1901, 2119, 2131, 3041, 3042, 3043, 3059, 3063, 3153, 3169, 3353, 3354,
		3408, 3593, 3598, 4087, 4089, 4593, 4594, 4595, 5113, 5114, 5479, 5480, 7315, 8141, 16387, 251964, 252377, 254088,
		270278 },
	PALADIN = { 925, 926, 927, 928, 1232, 5147, 5148, 5149, 5491, 5492, 8140, 244808, 246152, 246344, 246389, 260093 },
	HUNTER = { 895, 987, 1231, 1404, 3038, 3039, 3040, 3061, 3065, 3154, 3171, 3352, 3406, 3407, 3596, 3601, 3963, 4138,
		4146, 4205, 5115, 5116, 5117, 5501, 5515, 5516, 5517, 8308, 10930, 248415, 251376, 251507, 252389, 254084, 270280,
		543, 2878, 2879, 3306, 3545, 3620, 3622, 3624, 3688, 3698, 4320, 10086, 10088, 10089, 10090, 3702, 254411, 258930 },
	ROGUE = { 915, 916, 917, 918, 1234, 1411, 2122, 2130, 3155, 3170, 3327, 3328, 3401, 3594, 3599, 4163, 4214, 4215, 4582,
		4583, 4584, 5165, 5166, 5167, 13283, 205729, 251389, 252379, 254087 },
	PRIEST = { 375, 376, 377, 837, 1226, 2123, 2129, 3044, 3045, 3046, 3595, 3600, 3706, 3707, 4090, 4091, 4092, 4606,
		4607, 4608, 5141, 5142, 5143, 5484, 5489, 5994, 6014, 6018, 11397, 11401, 11406, 258785 },
	SHAMAN = { 986, 3030, 3031, 3032, 3062, 3066, 3157, 3173, 3344, 3403, 13417, 251374, 252382, 254082, 257446, 258098,
		258113, 262558, 270263 },
	MAGE = { 198, 313, 328, 331, 944, 1228, 2124, 2128, 3047, 3048, 3049, 4566, 4567, 4568, 5144, 5145, 5146, 5497, 5498,
		5880, 5882, 5883, 5884, 5885, 7311, 7312, 246797, 251379, 252373, 254086 },
	WARLOCK = { 459, 460, 461, 906, 988, 2126, 2127, 3156, 3172, 3324, 3325, 3326, 4563, 4564, 4565, 5171, 5172, 5173,
		5495, 5496, 5612, 5520, 5749, 5750, 5753, 5815, 6027, 6328, 6373, 6374, 6376, 6382, 12776, 12807 },
	DRUID = { 3033, 3034, 3036, 3060, 3064, 3597, 3602, 4217, 4218, 4219, 5504, 5505, 5506, 8142, 9465, 12042, 251373,
		252359, 254081, 262560, 270459 },
}

local FOLK = { Repair = "REPAIR", Innkeeper = "INNKEEPER", ["Flight Master"] = "FLIGHT_MASTER", Vendor = "VENDOR" }
local folk

function Moteur.BuildTownsfolk(yield)
	local lib = Moteur.Lib()
	local flags = lib and lib.Enum and lib.Enum.npcFlags
	if type(flags) ~= "table" then
		return nil
	end
	local out, masks = {}, {}
	for kind, key in pairs(FOLK) do
		if type(flags[key]) == "number" and flags[key] > 0 then
			out[kind], masks[kind] = {}, flags[key]
		end
	end
	local n = 0
	for id in pairs(Call(lib.Npc.GetAllIds, true) or {}) do
		n = n + 1
		if yield and n % 200 == 0 then
			yield()
		end
		local f = tonumber(Get("Npc", id, "npcFlags"))
		if f and f > 0 then
			for kind, mask in pairs(masks) do
				if HasBit(f, mask) then
					local name = Get("Npc", id, "name")
					if type(name) == "string" and name:sub(1, 5) ~= "[DND]" then
						local list = out[kind]
						list[#list + 1] = id
					end
				end
			end
		end
	end
	folk = out
	return out
end

-- Identifiants des PNJ d'une sorte (« Repair », « Innkeeper », « Flight Master », « Class Trainer »), ou nil tant que
-- la liste n'est pas prête (elle se construit en tâche de fond après la connexion).
function Moteur.Townsfolk(kind)
	if kind == "Class Trainer" then
		local class = UnitClassBase and UnitClassBase("player") or (UnitClass and select(2, UnitClass("player")))
		return class and CLASS_TRAINERS[class] or nil
	end
	return folk and folk[kind] or nil
end

-------------------------------------------------------------------------------
-- Tâche de fond : liste des quêtes disponibles (et habitants des villes une fois), recalculée quand il le faut
-------------------------------------------------------------------------------
local runner = CreateFrame("Frame")
runner:Hide()
local job, deadline, again = nil, 0, false
local BUDGET_MS = 4
local started = false

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
	deadline = debugprofilestop() + BUDGET_MS
	local ok, err = coroutine.resume(job)
	if not ok then
		job = nil
		self:Hide()
		Moteur.error = tostring(err)
		if ns.OnError then
			ns.OnError("moteur : " .. tostring(err))
		end
		return
	end
	if coroutine.status(job) == "dead" then
		job = nil
		self:Hide()
		if ns.RequestPlan then
			ns.RequestPlan("moteur", 0.5)
		end
		if again then
			again = false
			Moteur.Refresh(1)
		end
	end
end)

local function Run()
	if job then
		again = true
		return
	end
	job = coroutine.create(function()
		Moteur.ComputeAvailable(Yield)
		if not folk then
			Moteur.BuildTownsfolk(Yield)
		end
	end)
	runner:Show()
end

local timer
-- Recalcul de la liste dans `delay` secondes (plusieurs demandes rapprochées n'en font qu'un).
function Moteur.Refresh(delay)
	if not started then
		return
	end
	if timer then
		timer:Cancel()
	end
	timer = C_Timer.NewTimer(delay or 2, function()
		timer = nil
		Run()
	end)
end

function Moteur.Busy()
	return job ~= nil
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "QUEST_TURNED_IN" and type(arg1) == "number" then
		turnedIn[arg1] = true
		Completed()[arg1] = true
	end
	if event == "PLAYER_LEVEL_UP" then
		questCache = {} -- (niveaux « à ton niveau » des quêtes qui suivent le joueur)
	end
	Moteur.Refresh(event == "UPDATE_FACTION" and 10 or 2)
end)

-- Démarre la tâche de fond (appelé par Data quand il choisit ce moteur).
function Moteur.Start()
	if started or not Moteur.Lib() then
		return
	end
	started = true
	for _, e in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED",
		"UPDATE_FACTION", "LEARNED_SPELL_IN_TAB" }) do
		pcall(events.RegisterEvent, events, e)
	end
	Run()
end

-- Les modules au format de Questie, pour Data.lua.
local modules
function Moteur.Modules()
	if modules then
		return modules
	end
	local lib = Moteur.Lib()
	if not lib then
		return nil
	end
	DB.QuestPointers = Call(lib.Quest.GetAllIds, true) or {}
	DB.NPCPointers = Call(lib.Npc.GetAllIds, true) or {}
	DB.ItemPointers = Call(lib.Item.GetAllIds, true) or {}
	DB.ObjectPointers = Call(lib.Object.GetAllIds, true) or {}
	modules = { DB = DB, Zone = Zone, XP = XP, Avail = Avail, Player = Player, Professions = ProfessionsModule,
		interne = true }
	Moteur.Start()
	return modules
end

-- État pour /iti controle et /iti rapport.
function Moteur.State()
	if not Moteur.Lib() then
		return "indisponible : " .. tostring(why)
	end
	local version = C_AddOns and C_AddOns.GetAddOnMetadata and Call(C_AddOns.GetAddOnMetadata, "QuestieDB", "Version")
	local state = job and "calcul en cours" or (Moteur.availAt and "prêt" or "pas encore calculé")
	return string.format("QuestieDB %s (contrat %s) · %s · %s quêtes disponibles · %s", tostring(version or "?"),
		tostring(L.contractVersion or "?"), state, tostring(Moteur.availCount or "?"),
		folk and "habitants des villes prêts" or "habitants des villes en attente")
end
