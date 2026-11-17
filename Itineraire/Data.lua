-- Itinéraire : lecture du journal (jeu) et des positions (Questie / QuestieDB).
local _, ns = ...
local Data = {}
ns.Data = Data
local Geo = ns.Geo

local M -- modules Questie

local CLUSTER_RADIUS = 110 -- yards : points regroupés dans une même zone de chasse
local MAX_POINTS = 600

function Data.QuestieReady()
	return type(Questie) == "table" and Questie.started == true and type(QuestieLoader) == "table"
end

function Data.Modules()
	if M then
		return M
	end
	if not Data.QuestieReady() then
		return nil
	end
	local ok = pcall(function()
		M = {
			DB = QuestieLoader:ImportModule("QuestieDB"),
			Zone = QuestieLoader:ImportModule("ZoneDB"),
			XP = QuestieLoader:ImportModule("QuestXP"),
			Avail = QuestieLoader:ImportModule("AvailableQuests"),
		}
	end)
	if not ok or not (M and M.DB and M.Zone) then
		M = nil
	end
	return M
end

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

-- Texte d'objectif lisible : retire les marques de pluriel « |4singulier:pluriel; ».
function Data.CleanText(text)
	if type(text) ~= "string" then
		return ""
	end
	text = text:gsub("|4[^;]*;", ""):gsub("%s+$", ""):gsub("%s+:", " :")
	return text
end

-------------------------------------------------------------------------------
-- Journal de quêtes (vérité du jeu)
-------------------------------------------------------------------------------
function Data.ReadLog()
	local log = {}
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then
		return log
	end
	local n = C_QuestLog.GetNumQuestLogEntries() or 0
	local header
	for i = 1, n do
		local info = C_QuestLog.GetInfo(i)
		if info then
			if info.isHeader then
				header = info.title
			elseif info.questID and info.questID > 0 and not info.isHidden then
				local id = info.questID
				local objectives = Call(C_QuestLog.GetQuestObjectives, id) or {}
				local any, all = false, true
				for _, o in ipairs(objectives) do
					any = true
					if not o.finished then
						all = false
					end
				end
				local complete = Call(C_QuestLog.IsComplete, id) or Call(C_QuestLog.ReadyForTurnIn, id) or (any and all)
				log[#log + 1] = {
					id = id,
					title = info.title or ("#" .. id),
					level = info.level or 0,
					group = info.suggestedGroup or 0,
					header = header,
					objectives = objectives,
					complete = complete and true or false,
					talkOnly = not any,
					failed = Call(C_QuestLog.IsFailed, id) and true or false,
				}
			end
		end
	end
	return log
end

-------------------------------------------------------------------------------
-- Positions
-------------------------------------------------------------------------------
local function IsDungeonArea(areaId)
	local dungeons = M and Call(M.Zone.GetDungeons, M.Zone)
	return dungeons and dungeons[areaId] ~= nil
end

-- spawns = { [areaId] = { {x, y}, ... } } (coordonnées 0-100)
local function AddSpawns(spawns, points, meta, limit)
	limit = limit or MAX_POINTS
	for areaId, list in pairs(spawns or {}) do
		if type(list) == "table" then
			if IsDungeonArea(areaId) then
				meta.dungeons[areaId] = true
			else
				local map = Call(M.Zone.GetUiMapIdByAreaId, M.Zone, areaId)
				for _, s in ipairs(list) do
					if #points >= limit then
						return
					end
					if type(s) == "table" and s[1] and s[2] then
						if s[1] == -1 or s[2] == -1 then
							meta.dungeons[areaId] = true
						elseif map then
							local x, y = s[1] / 100, s[2] / 100
							local wx, wy, inst = Geo.World(map, x, y)
							if wx then
								points[#points + 1] = { map = map, x = x, y = y, wx = wx, wy = wy, inst = inst }
							end
						end
					end
				end
			end
		end
	end
end

-- Rang Questie : 1 = élite, 2 = élite rare, 3 = boss.
local function NoteElite(npc, meta)
	local rank = npc and tonumber(npc.rank)
	if rank and rank >= 1 and rank <= 3 then
		meta.eliteLevel = math.max(meta.eliteLevel or 0, npc.maxLevel or npc.minLevel or 0)
	end
end

local function NpcLevel(id, meta)
	local npc = Call(M.DB.GetNPC, M.DB, id)
	if npc and meta then
		NoteElite(npc, meta)
	end
	return npc and (npc.maxLevel or npc.minLevel)
end

local function SpawnsOfNpc(id, points, meta)
	local npc = Call(M.DB.GetNPC, M.DB, id)
	if npc then
		AddSpawns(npc.spawns, points, meta)
		meta.names[#meta.names + 1] = npc.name
		meta.level = math.max(meta.level or 0, npc.maxLevel or npc.minLevel or 0)
		NoteElite(npc, meta) -- cibles d'objectif (à tuer, ou qui font tomber l'objet)
	end
end

local function SpawnsOfObject(id, points, meta)
	local object = Call(M.DB.GetObject, M.DB, id)
	if object then
		AddSpawns(object.spawns, points, meta)
		meta.names[#meta.names + 1] = object.name
	end
end

-- Repli quand Questie n'a pas encore rempli la liste des apparitions de l'objectif.
local function FromObjectiveData(data, points, meta)
	if type(data) ~= "table" then
		return
	end
	if data.Type == "monster" and data.Id then
		SpawnsOfNpc(data.Id, points, meta)
	elseif data.Type == "killcredit" and type(data.IdList) == "table" then
		for _, id in ipairs(data.IdList) do
			SpawnsOfNpc(id, points, meta)
		end
	elseif data.Type == "object" and data.Id then
		SpawnsOfObject(data.Id, points, meta)
	elseif data.Type == "item" and data.Id then
		local item = Call(M.DB.GetItem, M.DB, data.Id)
		if item then
			for _, id in ipairs(item.npcDrops or {}) do
				SpawnsOfNpc(id, points, meta)
			end
			for _, id in ipairs(item.objectDrops or {}) do
				SpawnsOfObject(id, points, meta)
			end
		end
	elseif data.Type == "event" and data.Coordinates then
		AddSpawns(data.Coordinates, points, meta)
	end
end

-- Points où faire l'objectif `index` de la quête Questie `quest`.
function Data.ObjectivePoints(quest, index)
	local points, meta = {}, { dungeons = {}, names = {} }
	local live = quest and quest.Objectives and quest.Objectives[index]
	if live and type(live.spawnList) == "table" and next(live.spawnList) then
		for _, entry in pairs(live.spawnList) do
			AddSpawns(entry.Spawns, points, meta)
			if entry.Name then
				meta.names[#meta.names + 1] = entry.Name
			end
			if entry.Hostile and entry.Id and not entry.ItemId then
				local lvl = NpcLevel(entry.Id, meta)
				if lvl then
					meta.level = math.max(meta.level or 0, lvl)
				end
			end
		end
	elseif live and live.Coordinates then
		AddSpawns(live.Coordinates, points, meta)
	elseif quest and quest.ObjectiveData then
		FromObjectiveData(quest.ObjectiveData[index], points, meta)
	end
	return points, meta
end

-- Points du personnage (ou objet) qui reçoit la quête.
function Data.FinisherPoints(quest)
	local points, meta = {}, { dungeons = {}, names = {}, npcs = {} }
	local finisher = quest and quest.Finisher
	if not finisher then
		return points, meta
	end
	for _, id in ipairs(finisher.NPC or {}) do
		local npc = Call(M.DB.GetNPC, M.DB, id)
		if npc and npc.spawns and npc.friendly ~= false then
			local before = #points
			AddSpawns(npc.spawns, points, meta)
			for k = before + 1, #points do
				points[k].npc = id
				points[k].name = npc.name
			end
			meta.names[#meta.names + 1] = npc.name
		end
	end
	for _, id in ipairs(finisher.GameObject or {}) do
		local object = Call(M.DB.GetObject, M.DB, id)
		if object and object.spawns then
			local before = #points
			AddSpawns(object.spawns, points, meta)
			for k = before + 1, #points do
				points[k].object = id
				points[k].name = object.name
			end
		end
	end
	return points, meta
end

-------------------------------------------------------------------------------
-- Regroupement des points en zones de chasse
-------------------------------------------------------------------------------
function Data.Clusters(points, radius)
	radius = radius or CLUSTER_RADIUS
	local grid = {}
	local function Cell(p)
		return (p.inst or 0) .. ":" .. math.floor(p.wx / radius) .. ":" .. math.floor(p.wy / radius)
	end
	for idx, p in ipairs(points) do
		local key = Cell(p)
		grid[key] = grid[key] or {}
		table.insert(grid[key], idx)
	end
	local seen, clusters = {}, {}
	for idx in ipairs(points) do
		if not seen[idx] then
			local members, queue = {}, { idx }
			seen[idx] = true
			while #queue > 0 do
				local cur = table.remove(queue)
				members[#members + 1] = cur
				local p = points[cur]
				local cx, cy = math.floor(p.wx / radius), math.floor(p.wy / radius)
				for dx = -1, 1 do
					for dy = -1, 1 do
						local list = grid[(p.inst or 0) .. ":" .. (cx + dx) .. ":" .. (cy + dy)]
						for _, other in ipairs(list or {}) do
							if not seen[other] then
								local q = points[other]
								local ddx, ddy = p.wx - q.wx, p.wy - q.wy
								if ddx * ddx + ddy * ddy <= radius * radius then
									seen[other] = true
									queue[#queue + 1] = other
								end
							end
						end
					end
				end
			end
			-- Centre = le point le plus proche du barycentre (toujours un vrai point de carte).
			local sx, sy = 0, 0
			for _, m in ipairs(members) do
				sx, sy = sx + points[m].wx, sy + points[m].wy
			end
			sx, sy = sx / #members, sy / #members
			local best, bestD, spread = nil, math.huge, 0
			for _, m in ipairs(members) do
				local q = points[m]
				local d = (q.wx - sx) ^ 2 + (q.wy - sy) ^ 2
				if d < bestD then
					best, bestD = q, d
				end
			end
			for _, m in ipairs(members) do
				local q = points[m]
				spread = spread + math.sqrt((q.wx - best.wx) ^ 2 + (q.wy - best.wy) ^ 2)
			end
			spread = spread / #members
			clusters[#clusters + 1] = {
				count = #members,
				map = best.map, x = best.x, y = best.y, wx = best.wx, wy = best.wy, inst = best.inst,
				radius = math.max(25, math.min(150, spread * 1.6)),
			}
		end
	end
	table.sort(clusters, function(a, b)
		return a.count > b.count
	end)
	return clusters
end

-------------------------------------------------------------------------------
-- Quêtes disponibles (pour les prises « au passage »)
-------------------------------------------------------------------------------
function Data.AvailableQuests()
	local list = M and M.Avail and M.Avail.__availableQuests
	return type(list) == "table" and list or {}
end

function Data.Quest(id)
	return M and Call(M.DB.GetQuest, id)
end

function Data.QuestXP(id)
	if not (M and M.XP and M.XP.GetQuestLogRewardXP) then
		return nil
	end
	local xp = Call(M.XP.GetQuestLogRewardXP, M.XP, id)
	if type(xp) == "number" and xp > 0 then
		return xp
	end
	-- Quête sans donnée d'XP (nouveauté Forever) : estimation prudente selon son niveau.
	local quest = Data.Quest(id)
	local level = quest and tonumber(quest.level)
	local player = UnitLevel and UnitLevel("player")
	if not (level and level > 0 and type(player) == "number") then
		return type(xp) == "number" and xp or nil
	end
	local gap = player - level
	local factor = gap >= 6 and 0.1 or gap == 5 and 0.2 or gap == 4 and 0.4 or gap == 3 and 0.6 or gap == 2 and 0.8 or 1
	return math.floor(70 * level * factor)
end

function Data.Flag(name, id)
	local fn = M and M.DB and M.DB[name]
	return Call(fn, id) and true or false
end

function Data.DungeonName(areaId)
	local name = M and Call(M.Zone.GetLocalizedDungeonName, M.Zone, areaId)
	return name or ("Donjon " .. tostring(areaId))
end

-- Entrée du donjon : {map, x, y, wx, wy, inst}
function Data.DungeonEntrance(areaId)
	local locs = M and Call(M.Zone.GetDungeonLocation, M.Zone, areaId)
	for _, loc in ipairs(locs or {}) do
		local map = Call(M.Zone.GetUiMapIdByAreaId, M.Zone, loc[1])
		if map and loc[2] and loc[3] then
			local x, y = loc[2] / 100, loc[3] / 100
			local wx, wy, inst = Geo.World(map, x, y)
			if wx then
				return { map = map, x = x, y = y, wx = wx, wy = wy, inst = inst }
			end
		end
	end
	return nil
end

-------------------------------------------------------------------------------
-- Quêtes pas encore prises (propositions sur le trajet)
-------------------------------------------------------------------------------
function Data.MaxQuests()
	local n = C_QuestLog and Call(C_QuestLog.GetMaxNumQuestsCanAccept)
	return type(n) == "number" and n > 0 and n or 20
end

-- Déjà rendue par le passé (le jeu, sinon Questie).
function Data.Completed(id)
	if C_QuestLog and Call(C_QuestLog.IsQuestFlaggedCompleted, id) then
		return true
	end
	local db = type(Questie) == "table" and Questie.db and Questie.db.char
	return db and type(db.complete) == "table" and db.complete[id] and true or false
end

-- Masque de classe / race : 0 ou nil = tout le monde ; sinon le bit du joueur doit être présent.
local function HasBit(mask, flag)
	return mask % (flag * 2) >= flag
end

local function ClassOK(mask)
	mask = tonumber(mask)
	if not mask or mask <= 0 then
		return true
	end
	local player = Data.QuestieModule("QuestiePlayer")
	local ok = player and Call(player.HasRequiredClass, mask)
	if ok ~= nil then
		return ok and true or false
	end
	-- Questie absent ou pas encore prêt : identifiant de classe du jeu (guerrier = 1 -> bit 1, etc.)
	local classId = UnitClass and select(3, UnitClass("player"))
	if type(classId) ~= "number" or classId < 1 then
		return true -- inconnu : on ne retire rien
	end
	return HasBit(mask, 2 ^ (classId - 1))
end

local function RaceOK(mask)
	mask = tonumber(mask)
	if not mask or mask <= 0 then
		return true
	end
	-- Les races de Forever (bits au-delà de 32) ne sont connues que de Questie : sans lui, on ne retire rien.
	local player = Data.QuestieModule("QuestiePlayer")
	local ok = player and Call(player.HasRequiredRace, mask)
	return ok ~= false
end

-- Module Questie facultatif (QuestiePlayer, QuestieProfessions) : nil s'il manque.
function Data.QuestieModule(name)
	if not (Data.Modules() and QuestieLoader and QuestieLoader.ImportModule) then
		return nil
	end
	local mod = Call(QuestieLoader.ImportModule, QuestieLoader, name)
	return type(mod) == "table" and mod or nil
end

-- Une quête PAS ENCORE PRISE est-elle faisable par ce personnage ? (classe, race, métier,
-- quête exclusive déjà faite ou en cours, refus déjà noté par Questie). Ne sert qu'aux quêtes à
-- prendre (propositions, région, suites, donjons) : les quêtes du journal ne passent jamais ici.
-- `inLog` (facultatif) : ensemble des quêtes du journal. Rend false + la raison.
function Data.CanTake(id, quest, inLog)
	quest = quest or Data.Quest(id)
	if type(quest) ~= "table" then
		return false, "inconnue"
	end
	local black = M and M.DB and type(M.DB.autoBlacklist) == "table" and M.DB.autoBlacklist[id]
	if black then
		return false, tostring(black) -- Questie l'a déjà jugée infaisable (classe, race, métier, réputation)
	end
	if not ClassOK(quest.requiredClasses) then
		return false, "classe"
	end
	if not RaceOK(quest.requiredRaces) then
		return false, "race"
	end
	if type(quest.requiredSkill) == "table" then
		local prof = Data.QuestieModule("QuestieProfessions")
		local has = prof and Call(prof.HasProfessionAndSkillLevel, prof, quest.requiredSkill)
		if has == false then
			return false, "métier"
		end
	end
	if type(quest.exclusiveTo) == "table" then
		for _, other in pairs(quest.exclusiveTo) do
			if type(other) == "number" and (Data.Completed(other) or (inLog and inLog[other])) then
				return false, "exclusive"
			end
		end
	end
	return true
end

-- Nom lisible de l'objectif `index` d'une quête de la base (« Zhévra », « Sabot de zhévra »…).
function Data.ObjectiveLabel(quest, index)
	local data = quest and quest.ObjectiveData and quest.ObjectiveData[index]
	if type(data) ~= "table" then
		return nil, nil
	end
	local name
	if type(data.Text) == "string" and data.Text ~= "" then
		name = data.Text
	elseif data.Type == "monster" and data.Id then
		local npc = Call(M.DB.GetNPC, M.DB, data.Id)
		name = npc and npc.name
	elseif data.Type == "object" and data.Id then
		local object = Call(M.DB.GetObject, M.DB, data.Id)
		name = object and object.name
	elseif data.Type == "item" and data.Id then
		local item = Call(M.DB.GetItem, M.DB, data.Id)
		name = item and item.name
	elseif data.Type == "killcredit" and data.RootId then
		local npc = Call(M.DB.GetNPC, M.DB, data.RootId)
		name = npc and npc.name
	end
	return data.Type, name or "objectif " .. index
end

-- Ce qu'on chasse pour l'objectif `index` : « monster:3245 », « item:4891 »… (pour apprendre ton rythme
-- monstre par monstre, objet par objet). `kind` = le type d'objectif du journal (l'unité mesurée : un
-- monstre tué, un objet obtenu…). nil si la base ne le dit pas.
function Data.ObjectiveTarget(quest, index, kind)
	local data = quest and quest.ObjectiveData and quest.ObjectiveData[index]
	local id
	if type(data) == "table" then
		id = data.Id or data.RootId or (type(data.IdList) == "table" and data.IdList[1])
		kind = kind or data.Type
	end
	local live = quest and quest.Objectives and quest.Objectives[index]
	if type(id) ~= "number" and type(live) == "table" then
		if type(live.Id) == "number" then
			id = live.Id
			kind = kind or live.Type
		elseif type(live.spawnList) == "table" then
			for _, entry in pairs(live.spawnList) do
				local eid = type(entry) == "table" and entry.Id
				if type(eid) == "number" and (type(id) ~= "number" or eid < id) then
					id = eid -- le plus petit : toujours le même d'un calcul à l'autre
				end
			end
		end
	end
	if type(id) == "number" and type(kind) == "string" then
		return kind .. ":" .. id
	end
	return nil
end

-- Nom lisible d'une cible apprise (« monster:3245 » -> « Zhévra »).
function Data.TargetName(key)
	local kind, id = tostring(key):match("^(%a+):(%d+)$")
	id = tonumber(id)
	if not (id and M and M.DB) then
		return tostring(key)
	end
	local entry
	if kind == "object" then
		entry = Call(M.DB.GetObject, M.DB, id)
	elseif kind == "item" then
		entry = Call(M.DB.GetItem, M.DB, id)
	end
	entry = entry or Call(M.DB.GetNPC, M.DB, id) -- (un objet repéré par le monstre qui le donne)
	return entry and entry.name or tostring(key)
end

-- Quantités demandées par une quête pas encore prise, lues dans son texte (« Rapportez 4 sabots de
-- zhévra »). La base Questie n'a pas les nombres ; sans correspondance sûre, l'objectif reste sans nombre.
local COUNTABLE = { monster = true, item = true, killcredit = true, object = true }
function Data.ObjectiveCounts(quest)
	local counts = {}
	local text = quest and quest.objectivesText
	if type(text) == "table" then
		local parts = {}
		for _, line in ipairs(text) do
			if type(line) == "string" then
				parts[#parts + 1] = line
			end
		end
		text = table.concat(parts, " ")
	end
	if type(text) ~= "string" or text == "" then
		return counts
	end
	local lower = text:lower()
	local countable = {}
	for i, data in ipairs(quest.ObjectiveData or {}) do
		if type(data) == "table" and COUNTABLE[data.Type] then
			countable[#countable + 1] = i
		end
	end
	-- 1) un nombre juste avant le nom de l'objectif
	for _, i in ipairs(countable) do
		local _, label = Data.ObjectiveLabel(quest, i)
		local key
		for word in (label or ""):lower():gmatch("[^%s%p%d]+") do
			if #word >= 4 then
				key = word
				break
			end
		end
		local init = 1
		while key and not counts[i] do
			local pos = lower:find(key, init, true)
			if not pos then
				break
			end
			local n = tonumber(lower:sub(math.max(1, pos - 30), pos - 1):match("(%d+)%D*$"))
			if n and n >= 1 and n <= 50 then
				counts[i] = n
			end
			init = pos + #key
		end
	end
	-- 2) un seul objectif à compter et un seul nombre dans le texte
	if #countable == 1 and not counts[countable[1]] then
		local found, n = 0, nil
		for num in lower:gmatch("%d+") do
			found, n = found + 1, tonumber(num)
		end
		if found == 1 and n >= 1 and n <= 50 then
			counts[countable[1]] = n
		end
	end
	return counts
end

-- Habitants des villes (Questie « Townsfolk ») : réparateurs, aubergistes, maîtres de ta classe.
-- Seulement ceux qui sont amicaux, avec leurs positions. Gardé en cache par sorte.
local folkCache = {}

local function TownsfolkIds(kind)
	local ok, townsfolk = pcall(QuestieLoader.ImportModule, QuestieLoader, "Townsfolk")
	if not ok or type(townsfolk) ~= "table" then
		return nil
	end
	if kind == "Class Trainer" then
		local class = UnitClassBase and UnitClassBase("player")
		if not class and UnitClass then
			class = select(2, UnitClass("player"))
		end
		local byClass = type(townsfolk.classSpecificTownsfolk) == "table" and class and townsfolk.classSpecificTownsfolk[class]
		return type(byClass) == "table" and byClass["Class Trainer"] or nil
	end
	return type(townsfolk.townsfolk) == "table" and townsfolk.townsfolk[kind] or nil
end

function Data.TownsfolkPoints(kind, yield)
	if folkCache[kind] then
		return folkCache[kind]
	end
	if not M then
		return {}
	end
	local ids = TownsfolkIds(kind)
	if type(ids) ~= "table" or not ids[1] then
		return {}
	end
	local points, meta = {}, { dungeons = {}, names = {} }
	for i, id in ipairs(ids) do
		if yield and i % 25 == 0 then
			yield()
		end
		local npc = Call(M.DB.GetNPC, M.DB, id)
		if npc and npc.friendly ~= false and npc.spawns then
			local before = #points
			AddSpawns(npc.spawns, points, meta, 4000)
			for k = before + 1, #points do
				points[k].npc = id
				points[k].name = npc.name
			end
		end
	end
	folkCache[kind] = points
	return points
end

function Data.RepairPoints(yield)
	return Data.TownsfolkPoints("Repair", yield)
end

-- Pierre de foyer : prête dans combien de secondes, et où elle ramène (lieu lu chez Shortest Path).
local HEARTHSTONE = 6948
function Data.Hearth()
	local count = GetItemCount and Call(GetItemCount, HEARTHSTONE) or 0
	if type(count) ~= "number" or count < 1 then
		return nil
	end
	local cooldown = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
	local start, duration = Call(cooldown, HEARTHSTONE)
	local ready = 0
	if type(start) == "number" and type(duration) == "number" and start > 0 and duration > 0 then
		ready = math.max(0, start + duration - GetTime())
	end
	local hearth = { ready = ready, name = GetBindLocation and Call(GetBindLocation) or nil }
	local bind = type(ShortestPathForeverCharDB) == "table" and ShortestPathForeverCharDB.bind
	if type(bind) == "table" and type(bind.map) == "number" and type(bind.x) == "number" and type(bind.y) == "number"
		and C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D then
		local uiMap, pos = Call(C_Map.GetMapPosFromWorldPos, bind.map, CreateVector2D(bind.x, bind.y))
		if type(uiMap) == "number" and pos and pos.GetXY then
			local x, y = pos:GetXY()
			local wx, wy, inst = Geo.World(uiMap, x, y)
			if wx then
				hearth.point = { map = uiMap, x = x, y = y, wx = wx, wy = wy, inst = inst }
			end
		end
		hearth.name = hearth.name or (type(bind.name) == "string" and bind.name or nil)
	end
	return hearth
end

-- Quête d'un équipier (partage de groupe), présentée comme une entrée du journal.
-- `entry` vient d'un message réseau déjà validé : { id, complete, objectives = { {have, need} }, members }.
function Data.ExternalQuest(entry)
	local quest = Data.Quest(entry.id)
	if not quest then
		return nil
	end
	local objectives = {}
	for i = 1, #(quest.ObjectiveData or {}) do
		local kind, label = Data.ObjectiveLabel(quest, i)
		local o = entry.objectives[i] or {}
		local need = o.need or 1
		local have = entry.complete and need or (o.have or 0)
		objectives[i] = {
			type = kind, text = label .. " : " .. have .. "/" .. need,
			numFulfilled = have, numRequired = need, finished = have >= need,
		}
	end
	local owners = {}
	for k, name in ipairs(entry.members or {}) do
		owners[k] = name
	end
	return {
		id = entry.id, title = quest.name or ("#" .. entry.id), level = tonumber(quest.level) or 1, group = 0,
		objectives = objectives, complete = entry.complete and true or false, talkOnly = #objectives == 0,
		failed = false, external = true, owners = owners,
	}
end

-------------------------------------------------------------------------------
-- Objets de la base de Questie (équipement : récompenses, vendeurs, butins)
-------------------------------------------------------------------------------
-- Tous les identifiants d'objets connus (table id -> true), ou nil si la base n'est pas prête.
function Data.ItemIds()
	local db = M and M.DB
	if db and type(db.ItemPointers) == "table" then
		return db.ItemPointers
	end
	local lib = rawget(_G, "ItemDB")
	if type(lib) == "table" and type(lib.GetAllIds) == "function" then
		local ok, ids = pcall(lib.GetAllIds, true)
		if ok and type(ids) == "table" then
			return ids
		end
	end
	return nil
end

-- Un champ d'un objet : « class », « subClass », « requiredLevel », « questRewards », « vendors »,
-- « npcDrops », « objectDrops »…
function Data.ItemField(id, key)
	local db = M and M.DB
	if not (db and db.QueryItemSingle) then
		return nil
	end
	return Call(db.QueryItemSingle, id, key)
end

local function Places(entity, id, limit)
	local points, meta = {}, { dungeons = {}, names = {} }
	if not entity then
		return points, nil, meta
	end
	AddSpawns(entity.spawns, points, meta, limit or 200)
	for _, p in ipairs(points) do
		p.name = entity.name
	end
	return points, entity, meta
end

-- Où trouver un PNJ : ses positions (hors donjon), le PNJ lui-même, et meta.dungeons = { [areaId] = true }
-- s'il vit dans un donjon.
function Data.NpcPlaces(id, limit)
	local npc = M and Call(M.DB.GetNPC, M.DB, id)
	local points, entity, meta = Places(npc, id, limit)
	for _, p in ipairs(points) do
		p.npc = id
	end
	return points, entity, meta
end

function Data.ObjectPlaces(id, limit)
	local object = M and Call(M.DB.GetObject, M.DB, id)
	return Places(object, id, limit)
end

-------------------------------------------------------------------------------
-- Données reprises d'autres addons Forever (Donnees/*.lua, rangées dans ns.ext ; voir TIERS.txt)
--   BUTINS (Dropdon/All The Things), OBJETS (idem), ENTREES (DonData), RECETTES (Guildon Crafts),
--   PNJ et MARCHANDISES (Finddon). Les deux dernières sont de longues chaînes décodées à la demande.
-------------------------------------------------------------------------------
local function Ext()
	return type(ns.ext) == "table" and ns.ext or {}
end
Data.Ext = Ext

-- Camp du joueur : « A » ou « H » (un PNJ « N » sert tout le monde).
function Data.Side()
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	return faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
end

local pnj -- [id] = { id, name, title, side, roles = " v r Pb ", level, spots }
local function ParsePNJ()
	pnj = {}
	local data = Ext().PNJ
	if type(data) ~= "string" then
		return
	end
	for line in data:gmatch("[^\n]+") do
		local id, name, title, side, roles, level, spots =
			line:match("^(%d+)%^([^%^]*)%^([^%^]*)%^(%a)%^([^%^]*)%^([^%^]*)%^([^%^]+)")
		id = tonumber(id)
		if id and id < 9000000 then -- (au-delà : feux de cuisine, boîtes aux lettres, enclumes… pas des PNJ)
			pnj[id] = { id = id, name = name, title = title, side = side, level = tonumber(level), spots = spots,
				roles = " " .. (roles:gsub("([CP]?[%l%d])", "%1 ")) }
		end
	end
	Ext().PNJ = nil -- la table remplace la chaîne
end

function Data.ExtNpc(id)
	if not pnj then
		ParsePNJ()
	end
	return pnj[id]
end

function Data.ExtNpcFriendly(npc)
	local side = Data.Side()
	return npc and (npc.side == "N" or not side or npc.side == side) or false
end

-- Positions d'un PNJ de Finddon (« carte:xxyy… », dixièmes de % en base 36) en points du monde (gardées).
function Data.ExtNpcPlaces(npc, limit)
	if npc and npc.points then
		if not limit or limit >= #npc.points then
			return npc.points
		end
		local some = {}
		for k = 1, limit do
			some[k] = npc.points[k]
		end
		return some
	end
	local points = {}
	if not (npc and npc.spots) then
		return points
	end
	local max = limit or 60
	for map, list in npc.spots:gmatch("(%d+):(%w+)") do
		map = tonumber(map)
		for i = 1, #list - 3, 4 do
			local x, y = tonumber(list:sub(i, i + 1), 36), tonumber(list:sub(i + 2, i + 3), 36)
			if map and x and y and #points < max then
				x, y = x / 1000, y / 1000
				local wx, wy, inst = Geo.World(map, x, y)
				if wx then
					points[#points + 1] = { map = map, x = x, y = y, wx = wx, wy = wy, inst = inst, npc = npc.id, name = npc.name }
				end
			end
		end
	end
	if max >= 60 and #points > 0 then
		npc.points = points -- une seule fois par PNJ (pas tant que les cartes ne répondent pas)
	end
	return points
end

-- Les PNJ d'un rôle de Finddon (« Pb » = entraîneur de forge…) amicaux pour toi (gardés par rôle).
local byRole = {}
function Data.ExtNpcsWithRole(code)
	if not pnj then
		ParsePNJ()
	end
	if byRole[code] then
		return byRole[code]
	end
	local out, needle = {}, " " .. code .. " "
	byRole[code] = out
	for _, npc in pairs(pnj) do
		if npc.roles:find(needle, 1, true) and Data.ExtNpcFriendly(npc) then
			out[#out + 1] = npc
		end
	end
	return out
end

local goods -- [itemID] = { npcID, … }
local function ParseGoods()
	goods = {}
	local data = Ext().MARCHANDISES
	if type(data) ~= "string" then
		return
	end
	for line in data:gmatch("[^\n]+") do
		local id, _, _, free, limited = line:match("^(%d+)%^([^%^]+)%^(%l?)%^(%w*)%^(%w*)$")
		id = tonumber(id)
		if id then
			local list = {}
			for _, s in ipairs({ free, limited }) do
				for i = 1, #s - 3, 4 do
					local npc = tonumber(s:sub(i, i + 3), 36)
					if npc then
						list[#list + 1] = npc
					end
				end
			end
			goods[id] = list
		end
	end
	Ext().MARCHANDISES = nil
end

-- Vendeurs d'un objet d'après Finddon (ids de PNJ), ou nil.
function Data.ExtVendors(itemID)
	if not goods then
		ParseGoods()
	end
	return goods[itemID]
end

function Data.ExtGoodsIds()
	if not goods then
		ParseGoods()
	end
	return goods
end

-- Nom / qualité / niveau d'objet / niveau requis de secours (anglais) quand le serveur ne répond pas.
function Data.ItemFallback(id)
	local s = Ext().OBJETS and Ext().OBJETS[id]
	if type(s) ~= "string" then
		return nil
	end
	local name, quality, ilvl, req = s:match("^([^|]*)|?(%d*)|?(%d*)|?(%d*)")
	return { name = name, quality = tonumber(quality), ilvl = tonumber(ilvl), req = tonumber(req) }
end

-- Donjons et raids (Dropdon) : { id, name (langue du jeu si possible), min, max, raid, bosses, entrance }.
local dungeonList
local function Normal(name)
	return tostring(name or ""):lower():gsub("^the ", ""):gsub("^l[ae'] ?", ""):gsub("[^%w]", "")
end

local function QuestieEntranceByName(name)
	local all = M and Call(M.Zone.GetDungeons, M.Zone)
	if type(all) ~= "table" then
		return nil
	end
	local want = Normal(name)
	for areaId, d in pairs(all) do
		if type(d) == "table" and Normal(d[1]) == want then
			return Data.DungeonEntrance(areaId), areaId
		end
	end
	return nil
end

function Data.Dungeons()
	if dungeonList then
		return dungeonList
	end
	local list = {}
	local entrances = Ext().ENTREES or {}
	for id, d in pairs(Ext().BUTINS or {}) do
		if type(d) == "table" then
			local name = d.name
			local info = d.map and C_Map and C_Map.GetMapInfo and Call(C_Map.GetMapInfo, d.map)
			if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
				name = info.name
			end
			local entrance
			local e = type(entrances[id]) == "table" and entrances[id][1]
			if type(e) == "table" and e[1] and e[2] and e[3] then
				local x, y = e[2] / 100, e[3] / 100
				local wx, wy, inst = Geo.World(e[1], x, y)
				if wx then
					entrance = { map = e[1], x = x, y = y, wx = wx, wy = wy, inst = inst }
				end
			end
			local areaId
			if not entrance then
				entrance, areaId = QuestieEntranceByName(d.name)
			end
			list[#list + 1] = { id = id, name = name or ("Donjon " .. id), english = d.name, min = d.min or 1, max = d.max or 60,
				raid = d.raid and true or false, bosses = type(d.bosses) == "table" and d.bosses or {}, entrance = entrance,
				areaId = areaId }
		end
	end
	table.sort(list, function(a, b)
		if a.min ~= b.min then
			return a.min < b.min
		end
		return a.id < b.id
	end)
	dungeonList = list
	return list
end

-- Nom d'un boss : celui de Questie (dans la langue du jeu) quand il le connaît, sinon celui des données.
function Data.BossName(boss)
	if type(boss) ~= "table" then
		return "?"
	end
	if not boss.enc and boss.id and M then
		local npc = Call(M.DB.GetNPC, M.DB, boss.id)
		if npc and type(npc.name) == "string" and npc.name ~= "" then
			return npc.name
		end
	end
	return (tostring(boss.name or "?"):gsub(" <.*>$", ""))
end

-------------------------------------------------------------------------------
-- Repère du jeu pour une quête du journal (quand Questie ne sait pas où aller)
--   1. le point de quête que le jeu dessine sur la carte (C_QuestLog.GetQuestsOnMap, carte du joueur et ses parents) ;
--   2. sa prochaine étape (C_QuestLog.GetNextWaypoint) ;
--   3. DonData, s'il est installé (DonDataAPI : points d'objectifs, lieu du rendu).
-- Lecture seule ; tout est protégé (valeurs « secrètes » de Forever en combat).
-------------------------------------------------------------------------------
local poi, poiAt = {}, -100

local function Num(v)
	return type(v) == "number" and v or nil
end

local function ReadPOI()
	poi, poiAt = {}, GetTime()
	local fn = C_QuestLog and C_QuestLog.GetQuestsOnMap
	local map = C_Map and C_Map.GetBestMapForUnit and Call(C_Map.GetBestMapForUnit, "player")
	if type(fn) ~= "function" or not map then
		return
	end
	for _ = 1, 4 do
		local list = Call(fn, map)
		for _, e in ipairs(type(list) == "table" and list or {}) do
			local ok, id, x, y, indicator = pcall(function()
				return e.questID, e.x, e.y, e.isMapIndicatorQuest
			end)
			id, x, y = ok and Num(id), ok and Num(x), ok and Num(y)
			if id and x and y and not indicator and x > 0 and x <= 1 and y > 0 and y <= 1 and not poi[id] then
				poi[id] = { map = map, x = x, y = y }
			end
		end
		-- puis la carte parente (jusqu'au continent : ses points couvrent les quêtes des autres zones)
		local info = C_Map.GetMapInfo and Call(C_Map.GetMapInfo, map)
		local parent = type(info) == "table" and Num(info.parentMapID) or nil
		local kind = type(info) == "table" and Num(info.mapType) or nil
		if not parent or parent <= 0 or (kind and kind <= 2) then
			break
		end
		map = parent
	end
end

local function Point(map, x, y, source)
	if not (map and x and y) then
		return nil
	end
	local wx, wy, inst = Geo.World(map, x, y)
	if not wx then
		return nil
	end
	return { map = map, x = x, y = y, wx = wx, wy = wy, inst = inst, hint = source }
end

-- Où rendre une quête PAS ENCORE finie quand Questie l'ignore : seulement DonData (le repère du jeu montre
-- les objectifs tant que la quête n'est pas finie).
function Data.TurnInGuess(questID)
	local api = rawget(_G, "DonDataAPI")
	if type(api) ~= "table" or type(api.TurnInPoint) ~= "function" then
		return nil
	end
	local m, x, y = Call(api.TurnInPoint, questID)
	return Num(m) and Point(m, Num(x), Num(y), "DonData") or nil
end

-- `turnin` : la quête est finie (on cherche où la rendre). Rend un point (avec .hint = la source) ou nil.
function Data.QuestHint(questID, turnin)
	if GetTime() - poiAt > 5 then
		ReadPOI()
	end
	local p = poi[questID]
	if p then
		local point = Point(p.map, p.x, p.y, "jeu")
		if point then
			return point
		end
	end
	local waypoint = C_QuestLog and C_QuestLog.GetNextWaypoint
	if type(waypoint) == "function" then
		local m, x, y = Call(waypoint, questID)
		if Num(m) and Num(x) and Num(y) and not (x == 0 and y == 0) then
			local point = Point(m, x, y, "jeu")
			if point then
				return point
			end
		end
	end
	local api = rawget(_G, "DonDataAPI")
	if type(api) == "table" then
		if turnin and type(api.TurnInPoint) == "function" then
			local m, x, y = Call(api.TurnInPoint, questID)
			local point = Num(m) and Point(m, Num(x), Num(y), "DonData")
			if point then
				return point
			end
		elseif not turnin and type(api.ObjectivePoints) == "function" then
			local list = Call(api.ObjectivePoints, questID)
			local e = type(list) == "table" and list[1]
			local point = type(e) == "table" and Point(Num(e.mapID), Num(e.x), Num(e.y), "DonData")
			if point then
				return point
			end
		end
	end
	return nil
end

-- Usure de l'équipement (plus bas % d'un objet, moyenne) et places libres dans les sacs.
function Data.GearState()
	local low, total, count = 1, 0, 0
	if GetInventoryItemDurability then
		for slot = 1, 18 do
			local cur, max = GetInventoryItemDurability(slot)
			if type(cur) == "number" and type(max) == "number" and max > 0 then
				local r = cur / max
				low = math.min(low, r)
				total, count = total + r, count + 1
			end
		end
	end
	local free
	local getFree = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
	if getFree then
		for bag = 0, 4 do
			local n, family = getFree(bag)
			if type(n) == "number" and (family == nil or family == 0) then
				free = (free or 0) + n
			end
		end
	end
	return { low = low, avg = count > 0 and total / count or 1, free = free }
end

function Data.StarterPoints(quest)
	local points, meta = {}, { dungeons = {}, names = {} }
	local starts = quest and quest.Starts
	if not starts then
		return points
	end
	for _, id in ipairs(starts.NPC or {}) do
		local npc = Call(M.DB.GetNPC, M.DB, id)
		if npc and npc.spawns then
			local before = #points
			AddSpawns(npc.spawns, points, meta)
			for k = before + 1, #points do
				points[k].npc = id
				points[k].name = npc.name
			end
		end
	end
	for _, id in ipairs(starts.GameObject or {}) do
		local object = Call(M.DB.GetObject, M.DB, id)
		if object and object.spawns then
			local before = #points
			AddSpawns(object.spawns, points, meta)
			for k = before + 1, #points do
				points[k].name = object.name
			end
		end
	end
	return points
end
