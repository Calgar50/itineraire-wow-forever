-- Itinéraire : lecture de DungeonJournal (par ExehnTV, curseforge.com/wow/addons/dungeonjournal) PENDANT le jeu.
--
-- Rien de DungeonJournal n'est copié dans Itinéraire : quand l'addon est installé et chargé, ses données
-- (donjons de Forever, boss, butins, quêtes de donjon, où les prendre et les rendre, entrées) sont lues dans
-- sa table ForeverDungeonJournal_NS. Elles suivent donc ses mises à jour (quasi quotidiennes) sans attendre
-- une version d'Itinéraire. Utilisé avec l'autorisation de son auteur ; tous droits sur DungeonJournal et
-- ses données réservés à leur auteur (voir TIERS.txt).
--
-- Lecture seule, tout est protégé (pcall) : si DungeonJournal change sa structure, Itinéraire s'en passe.
local _, ns = ...
local DJ = {}
ns.DJ = DJ

DJ.ADDON = "ForeverDungeonJournal"
DJ.URL = "curseforge.com/wow/addons/dungeonjournal"
DJ.SOURCE = "DungeonJournal"

local function Call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c, d = pcall(fn, ...)
	if ok then
		return a, b, c, d
	end
	return nil
end

-- La table de DungeonJournal, ou nil s'il n'est pas chargé.
function DJ.NS()
	local fdj = rawget(_G, "ForeverDungeonJournal_NS")
	if type(fdj) == "table" and type(rawget(fdj, "DB")) == "table" then
		return fdj
	end
	return nil
end

-- Version installée (lue dans son .toc, même s'il est désactivé), ou nil s'il n'est pas installé.
function DJ.Version()
	local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or rawget(_G, "GetAddOnMetadata")
	local v = Call(get, DJ.ADDON, "Version")
	return type(v) == "string" and v ~= "" and v or nil
end

-------------------------------------------------------------------------------
-- Textes dans la langue du jeu (DungeonJournal traduit ses noms de donjons, de boss et de quêtes)
-------------------------------------------------------------------------------
local function Localized(fn, ...)
	local fdj = DJ.NS()
	local v = fdj and Call(fdj[fn], ...)
	return type(v) == "string" and v ~= "" and v or nil
end

function DJ.DungeonName(key)
	return Localized("LocalizeDungeonName", key) or tostring(key or "?")
end

function DJ.QuestName(q)
	if type(q) ~= "table" then
		return "?"
	end
	return Localized("LocalizeQuestField", q.id, "name", q.name) or tostring(q.name or ("#" .. tostring(q.id)))
end

function DJ.BossName(name)
	return Localized("LocalizeBossName", name) or tostring(name or "?")
end

function DJ.Text(text)
	if type(text) ~= "string" then
		return nil
	end
	return Localized("LocalizeFreeText", text) or text
end

-------------------------------------------------------------------------------
-- Lieux
-------------------------------------------------------------------------------
-- Un repère de DungeonJournal ({ mapID, x, y, label, targetName }, x et y entre 0 et 1) en point d'Itinéraire.
local function Point(spot)
	if type(spot) ~= "table" then
		return nil
	end
	local map, x, y = tonumber(spot.mapID), tonumber(spot.x), tonumber(spot.y)
	if not (map and x and y) or x <= 0 or y <= 0 or x > 1 or y > 1 then
		return nil
	end
	local wx, wy, inst = ns.Geo.World(map, x, y)
	if not wx then
		return nil
	end
	local name = type(spot.targetName) == "string" and spot.targetName ~= "" and spot.targetName or nil
	if not name and type(spot.label) == "string" then
		name = spot.label:match("^(.-) \226\128\148 ") -- « Nom — lieu »
	end
	return { map = map, x = x, y = y, wx = wx, wy = wy, inst = inst, hint = DJ.SOURCE, name = name }
end
DJ.Point = Point

local function Dungeon(key)
	local fdj = DJ.NS()
	local d = fdj and type(key) == "string" and fdj.DB[key]
	return type(d) == "table" and d or nil
end

function DJ.Entrance(key)
	local d = Dungeon(key)
	local p = d and Point(d.entrance)
	if p then
		p.name = nil -- (« Entrée de … » : pas un PNJ)
	end
	return p
end

local function StartSpot(q)
	local fdj = DJ.NS()
	if type(q.startMap) == "table" then
		return q.startMap
	end
	local maps = fdj and fdj.QUEST_START_MAPS
	return type(maps) == "table" and maps[q.id] or nil
end

-- Où prendre la quête : le repère de DungeonJournal, ou l'entrée du donjon si elle commence dedans.
function DJ.StartPoint(q, key)
	if type(q) ~= "table" then
		return nil
	end
	local p = Point(StartSpot(q))
	if p then
		return p
	end
	if q.startsInDungeon then
		return DJ.Entrance(key)
	end
	return nil
end

-- Où la rendre : son repère, sinon l'entrée si on la rend dans le donjon, sinon le donneur s'il est aussi le
-- destinataire (« Thom Filch, near the dungeon entrance » après l'avoir prise chez Thom Filch).
function DJ.TurnInPoint(q, key)
	if type(q) ~= "table" then
		return nil
	end
	local p = Point(q.turninMap)
	if p then
		return p
	end
	if type(q.turnin) ~= "string" or q.turnin == "" then
		return nil
	end
	local fdj = DJ.NS()
	if fdj and Call(fdj.TurnInInsideDungeon, q.turnin, key) then
		return DJ.Entrance(key)
	end
	local start = Point(StartSpot(q))
	if start and start.name and q.turnin:sub(1, #start.name) == start.name then
		return start
	end
	return nil
end

-- Où sont les objectifs : son repère, sinon l'entrée du donjon (c'est une quête de donjon).
function DJ.ObjectivePoint(q, key)
	if type(q) ~= "table" then
		return nil
	end
	local p = Point(q.objectiveMap)
	if p then
		return p
	end
	local d = Dungeon(key)
	if d and not d.questChainPage then
		return DJ.Entrance(key)
	end
	return nil
end

-------------------------------------------------------------------------------
-- Quêtes
-------------------------------------------------------------------------------
local index, indexDB, indexAt -- [questID] = { q, key } (la première page qui la cite)
local function Index()
	local fdj = DJ.NS()
	if not fdj then
		index, indexDB = nil, nil
		return {}
	end
	local now = GetTime and GetTime() or 0
	if index and indexDB == fdj.DB and now - (indexAt or 0) < 30 then
		return index
	end
	index, indexDB, indexAt = {}, fdj.DB, now
	for key, d in pairs(fdj.DB) do
		if type(key) == "string" and type(d) == "table" and type(d.quests) == "table" then
			for _, q in ipairs(d.quests) do
				if type(q) == "table" and type(q.id) == "number" and not index[q.id] then
					index[q.id] = { q = q, key = key }
				end
			end
		end
	end
	return index
end

-- La quête telle que DungeonJournal la connaît, et la page (donjon) où il la range.
function DJ.Quest(questID)
	local e = Index()[questID]
	if e then
		return e.q, e.key
	end
	return nil
end

local function FactionOK(faction)
	if faction ~= "Alliance" and faction ~= "Horde" then
		return true
	end
	local mine = Call(UnitFactionGroup, "player")
	return type(mine) ~= "string" or mine == "" or mine == faction
end
DJ.FactionOK = FactionOK

local function ClassOK(classOnly)
	if not classOnly then
		return true
	end
	local _, token = Call(UnitClass, "player")
	if type(token) ~= "string" or token == "" then
		return true
	end
	if type(classOnly) == "table" then
		for _, c in ipairs(classOnly) do
			if tostring(c):upper() == token:upper() then
				return true
			end
		end
		return false
	end
	-- « PALADIN », ou plusieurs classes dans une même chaîne
	for c in tostring(classOnly):upper():gmatch("%u+") do
		if c == token:upper() then
			return true
		end
	end
	return false
end

-- État d'une quête de DungeonJournal pour toi :
--   "log" (dans ton journal), "fait", "non" (pas pour toi : camp, classe, race, métier, retirée du jeu),
--   "plus tard" (niveau requis : 2e valeur), "chaîne" (quêtes préalables à finir), "maintenant".
-- `inLog` : [questID] = true (ton journal).
function DJ.QuestState(q, inLog)
	if type(q) ~= "table" or type(q.id) ~= "number" or q.unavailable then
		return "non"
	end
	if inLog and inLog[q.id] then
		return "log"
	end
	if not FactionOK(q.faction) then
		return "non"
	end
	local fdj = DJ.NS()
	local ok, counts = false, nil
	if fdj and type(fdj.QuestCountsForCharacter) == "function" then
		ok, counts = pcall(fdj.QuestCountsForCharacter, q) -- (classe et métier, comme dans le journal)
	end
	if ok then
		if counts == false then
			return "non"
		end
	elseif not ClassOK(q.classOnly) then
		return "non"
	end
	if type(q.unavailableRaces) == "table" then
		local _, race = Call(UnitRace, "player")
		if type(race) == "string" and q.unavailableRaces[race] then
			return "non"
		end
	end
	if not q.repeatable and ns.Data.Completed(q.id) then
		return "fait"
	end
	local req = tonumber(q.requires) or 1
	local level = Call(UnitLevel, "player") or 1
	if level < req then
		return "plus tard", req
	end
	if fdj and type(fdj.PrereqChainOf) == "function" and type(fdj.QuestChainUnlocked) == "function" then
		local chain = Call(fdj.PrereqChainOf, q.id)
		if type(chain) == "table" and #chain > 0 then
			local okChain, unlocked = pcall(fdj.QuestChainUnlocked, q)
			if okChain and unlocked == false then
				return "chaîne", req
			end
		end
	end
	return "maintenant", req
end

-- Les quêtes d'une page de DungeonJournal pour toi : { { q, state, req }, … } (sans celles qui ne sont pas pour toi).
function DJ.QuestsFor(key, inLog)
	local out = {}
	local d = Dungeon(key)
	for _, q in ipairs(d and type(d.quests) == "table" and d.quests or {}) do
		local state, req = DJ.QuestState(q, inLog)
		if state ~= "non" and state ~= "fait" then
			out[#out + 1] = { q = q, state = state, req = req }
		end
	end
	return out
end

-- Repère pour une quête de ton journal que Questie ne sait pas placer (voir Data.QuestHint).
function DJ.Hint(questID, turnin)
	local q, key = DJ.Quest(questID)
	if not q then
		return nil
	end
	if turnin then
		return DJ.TurnInPoint(q, key)
	end
	return DJ.ObjectivePoint(q, key)
end

-------------------------------------------------------------------------------
-- Donjons, boss et butins
-------------------------------------------------------------------------------
-- « 13-20 » -> 13, 20 ; « 45+ » -> 45, 60.
local function Range(text)
	text = tostring(text or "")
	local a, b = text:match("(%d+)%s*%-%s*(%d+)")
	if a then
		return tonumber(a), tonumber(b)
	end
	a = text:match("(%d+)")
	return tonumber(a) or 1, 60
end

-- { { key, english, name, min, max, chain (page de chaîne de quêtes, pas un donjon), entrance, quests,
--     bosses = { { name, english, id, items = { itemID… }, trash, rare, dj = true, djIndex } } }, … }
-- Les boss d'un seul camp (factionOnly) qui n'est pas le tien sont laissés de côté.
function DJ.Dungeons()
	local fdj = DJ.NS()
	if not fdj then
		return {}
	end
	local out = {}
	for key, d in pairs(fdj.DB) do
		if type(key) == "string" and type(d) == "table" and (type(d.bosses) == "table" or d.questChainPage) then
			local min, max = Range(d.level)
			local e = {
				key = key, english = key, name = DJ.DungeonName(key), min = min, max = max,
				chain = d.questChainPage and true or false, entrance = DJ.Entrance(key),
				quests = type(d.quests) == "table" and d.quests or {}, bosses = {},
			}
			for i, b in ipairs(type(d.bosses) == "table" and d.bosses or {}) do
				if type(b) == "table" and FactionOK(b.factionOnly) then
					local items = {}
					for _, it in ipairs(type(b.loot) == "table" and b.loot or {}) do
						local id = type(it) == "table" and tonumber(it[1])
						if id then
							items[#items + 1] = id
						end
					end
					e.bosses[#e.bosses + 1] = {
						name = DJ.BossName(b.name), english = b.name, id = tonumber(b.npcID), items = items,
						trash = b.trash and true or nil, rare = b.rare and true or nil, dj = true, djIndex = i,
					}
				end
			end
			out[#out + 1] = e
		end
	end
	table.sort(out, function(a, b)
		if a.min ~= b.min then
			return a.min < b.min
		end
		return a.key < b.key
	end)
	return out
end

-------------------------------------------------------------------------------
-- Ouvrir le journal sur une page
-------------------------------------------------------------------------------
-- Sans page : ouvre seulement le journal. Rend false si DungeonJournal n'est pas chargé.
function DJ.Open(key, questID, bossIndex)
	local fdj = DJ.NS()
	if not fdj then
		return false
	end
	local frame = rawget(_G, "ForeverDungeonJournalFrame")
	if type(frame) == "table" and frame.IsShown then
		if not frame:IsShown() then
			pcall(frame.Show, frame)
		end
	elseif type(fdj.ToggleJournal) == "function" then
		pcall(fdj.ToggleJournal)
	end
	if Dungeon(key) then
		if questID and type(fdj.OpenQuestPage) == "function" then
			pcall(fdj.OpenQuestPage, key, questID)
		elseif type(fdj.OpenBossPage) == "function" then
			pcall(fdj.OpenBossPage, key, bossIndex)
		end
	end
	return true
end

-- Un donjon d'après son nom ou un bout de son nom (dans la langue du jeu ou en anglais) : sa clé, ou nil. Marche
-- aussi dans l'autre sens (« Les Mortemines » de Questie trouve « Mortemines »).
function DJ.Find(text)
	local want = tostring(text or ""):lower()
	if want == "" then
		return nil
	end
	local list = DJ.Dungeons()
	for _, d in ipairs(list) do
		if d.name:lower() == want or d.english:lower() == want then
			return d.key
		end
	end
	for _, d in ipairs(list) do
		if d.name:lower():find(want, 1, true) or d.english:lower():find(want, 1, true) then
			return d.key
		end
	end
	for _, d in ipairs(list) do
		local n, e = d.name:lower(), d.english:lower()
		if (#n >= 5 and want:find(n, 1, true)) or (#e >= 5 and want:find(e, 1, true)) then
			return d.key
		end
	end
	return nil
end

-- Le donjon qui t'intéresse maintenant : celui où tu es, sinon le premier donjon de ton trajet. Clé et raison
-- (« ici », « trajet »), ou nil.
function DJ.CurrentKey()
	if Call(rawget(_G, "IsInInstance")) then
		local name = Call(rawget(_G, "GetInstanceInfo"))
		local key = type(name) == "string" and DJ.Find(name) or nil
		if key then
			return key, "ici"
		end
	end
	local plan = ns.plan
	for _, s in ipairs(type(plan) == "table" and type(plan.order) == "table" and plan.order or {}) do
		for _, task in ipairs(type(s) == "table" and type(s.tasks) == "table" and s.tasks or {}) do
			if type(task) == "table" and task.kind == "dungeon" and task.areaId and ns.Data and ns.Data.DungeonName then
				local key = DJ.Find(ns.Data.DungeonName(task.areaId))
				if key then
					return key, "trajet"
				end
			end
		end
	end
	return nil
end

-- Le bouton « Journal des donjons » (fenêtre d'Itinéraire, raccourci clavier) : clic = le donjon où tu es, sinon
-- celui de ton trajet, sinon l'accueil du journal ; `menu` = choisir parmi les donjons de ton niveau.
function DJ.Button(menu)
	if not DJ.NS() then
		ns.Print(DJ.ReportLine() .. ". Relance l'installateur d'Itinéraire (il l'installe et le tient à jour) ou prends-le sur "
			.. DJ.URL .. ".")
		return false
	end
	local current = DJ.CurrentKey()
	if not menu then
		return DJ.Open(current)
	end
	local level = Call(rawget(_G, "UnitLevel"), "player")
	level = type(level) == "number" and level or 1
	local items = { { text = "Journal des donjons (niveau " .. level .. ")", title = true } }
	local list = DJ.Dungeons()
	table.sort(list, function(a, b)
		if a.min ~= b.min then
			return (a.min or 0) < (b.min or 0)
		end
		return a.name < b.name
	end)
	for _, d in ipairs(list) do
		local fits = not d.chain and level >= (d.min or 1) - 3 and level <= (d.max or 60) + 2
		if fits or d.key == current then
			items[#items + 1] = { text = d.name .. " (" .. tostring(d.min) .. "-" .. tostring(d.max) .. ")",
				checked = d.key == current, func = function()
					DJ.Open(d.key)
				end }
		end
	end
	items[#items + 1] = { text = "Tous les donjons (accueil du journal)", func = function()
		DJ.Open(nil)
	end }
	items[#items + 1] = { text = "Fermer" }
	ns.UI.ShowMenu(items)
	return true
end

-------------------------------------------------------------------------------
-- Rapport
-------------------------------------------------------------------------------
function DJ.Stats()
	local dungeons, pages, quests, loot = 0, 0, 0, 0
	for _, d in ipairs(DJ.Dungeons()) do
		if d.chain then
			pages = pages + 1
		else
			dungeons = dungeons + 1
		end
		for _, q in ipairs(d.quests) do
			if type(q) == "table" and type(q.id) == "number" then
				quests = quests + 1
			end
		end
		for _, b in ipairs(d.bosses) do
			loot = loot + #b.items
		end
	end
	return { dungeons = dungeons, pages = pages, quests = quests, loot = loot }
end

function DJ.ReportLine()
	local version = DJ.Version()
	if DJ.NS() then
		local s = DJ.Stats()
		return string.format("DungeonJournal %s : lu (%d donjons, %d quêtes, %d butins de boss)", tostring(version or "?"),
			s.dungeons, s.quests, s.loot)
	elseif version then
		return "DungeonJournal " .. version .. " : installé mais pas chargé (désactivé dans la liste des addons ?)"
	end
	return "DungeonJournal : pas installé (l'installateur d'Itinéraire l'installe et le tient à jour)"
end
