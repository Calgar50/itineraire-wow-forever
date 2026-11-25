-- Moteur interne (3.3.0) : Itinéraire sans Questie, avec seulement la base publique QuestieDB (LibQuestieDB simulée).
-- Quêtes disponibles (règles de QuestieDB.IsDoable / AvailableQuests), forme des quêtes, zones, XP, habitants des
-- villes, positions des filons, puis un vrai trajet calculé sans aucun module de Questie.
dofile(TESTS .. "/wow_mock.lua")
local hbd = QuestieLoader:ImportModule("HBD")
Questie, QuestieLoader = nil, nil -- pas de Questie du tout
CreateVector2D = function(x, y) return { x = x, y = y } end
C_Map.GetWorldPosFromMapPos = function(map, v)
	local wx, wy, inst = hbd:GetWorldCoordinatesFromZone(v.x, v.y, map)
	if not wx then return nil end
	return inst, { GetXY = function() return wy, wx end }
end
NOW = 1800000000
time = function() return NOW end
date = function(fmt, t) return os.date(fmt, t or NOW) end
function UnitLevel() return 25 end
function UnitClass() return "Guerrier", "WARRIOR", 1 end
function UnitClassBase() return "WARRIOR" end
function UnitRace() return "Tauren", "Tauren", 6 end
function UnitFactionGroup() return "Horde" end
function GetMaxPlayerLevel() return 60 end
C_QuestLog.GetMaxNumQuestsCanAccept = function() return 25 end
C_QuestLog.GetAllCompletedQuestIDs = function() return { 200 } end
function GetProfessions() return 1, 2, nil, nil, nil end
function GetProfessionInfo(i)
	if i == 1 then return "Minage", "icon", 95, 150, 0, 0, 186 end
	if i == 2 then return "Forge", "icon", 57, 150, 0, 0, 164 end
end

-- Base simulée (forme publique de LibQuestieDB)
local function Copy(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = Copy(x) end
	return t
end
local function Entity(rows, raw)
	local e = {}
	function e.Get(id, key) local r = rows[id] return r and Copy(r[key]) or nil end
	function e.GetAll(id, list)
		if not rows[id] then return nil end
		local out = { n = #list }
		for i, k in ipairs(list) do out[i] = e.Get(id, k) end
		return out
	end
	function e.GetAllIds() local m = {} for id in pairs(rows) do m[id] = true end return m end
	function e.GetRaw(id, key) local r = (raw or rows)[id] return r and Copy(r[key]) or nil end
	function e.Exists(id) return rows[id] ~= nil end
	return e
end
local function Keys(list)
	local k = {}
	for i, name in ipairs(list) do k[name] = i end
	return k
end
local QKEYS = { "name", "startedBy", "finishedBy", "requiredLevel", "questLevel", "requiredRaces", "requiredClasses",
	"objectivesText", "triggerEnd", "objectives", "sourceItemId", "preQuestGroup", "preQuestSingle", "childQuests",
	"inGroupWith", "exclusiveTo", "zoneOrSort", "requiredSkill", "requiredMinRep", "requiredMaxRep",
	"requiredSourceItems", "nextQuestInChain", "questFlags", "specialFlags", "parentQuest", "breadcrumbForQuestId",
	"breadcrumbs", "requiredMaxLevel" }
local NKEYS = { "name", "minLevel", "maxLevel", "rank", "spawns", "friendlyToFaction", "npcFlags", "subName" }
local OKEYS = { "name", "spawns" }
local IKEYS = { "name", "npcDrops", "objectDrops", "vendors" }

local QROWS = {}
local function quest(id, level, req, extra)
	local q = { name = "Quête " .. id, questLevel = level, requiredLevel = req, startedBy = { { 9 } },
		finishedBy = { { 9 } }, zoneOrSort = 17 }
	for k, v in pairs(extra or {}) do q[k] = v end
	QROWS[id] = q
end
quest(100, 24, 20)                                  -- disponible
quest(101, 15, 10)                                  -- grise
quest(102, 31, 30)                                  -- niveau requis trop haut
quest(103, 24, 20, { requiredRaces = 1 })           -- humains seulement
quest(104, 24, 20, { requiredClasses = 128 })       -- mages seulement
quest(105, 24, 20, { requiredClasses = 1 })         -- guerriers : oui
quest(106, 24, 20, { preQuestSingle = { 100 } })    -- prérequis pas fait
quest(107, 24, 20, { preQuestSingle = { 200 } })    -- prérequis fait : oui
quest(108, 24, 20, { preQuestGroup = { 200, 201 } }) -- un des deux manque
quest(109, 24, 20, { exclusiveTo = { 200 } })       -- exclusive d'une quête faite
quest(110, 24, 20, { nextQuestInChain = 200 })      -- suite déjà faite
quest(111, 24, 20)                                  -- cachée (politique)
quest(112, 24, 20, { specialFlags = 1 })            -- répétable
quest(113, 24, 20, { preQuestGroup = { 200, -202 } }) -- -202 : pas faite -> non
quest(115, 40, 38)                                  -- suite d'une quête du journal : oui malgré le niveau
quest(116, 24, 20, { requiredSkill = { 186, 50 } }) -- minage 95 : oui
quest(117, 24, 20, { requiredSkill = { 164, 100 } }) -- forge 57 : non
quest(118, 24, 20, { breadcrumbForQuestId = 300 })  -- piste vers une quête déjà au journal
quest(119, -1, 20)                                  -- niveau « comme toi » : oui
quest(200, 22, 18)                                  -- déjà faite
quest(300, 24, 20, { childQuests = { 115 }, objectives = { [3] = { { 5006, "Journal" } } },
	triggerEnd = { "Explorer", { [17] = { { 50, 50 } } } } })
local NROWS = {
	[9] = { name = "Gann", spawns = { [17] = { { 52.2, 31.0 } } }, friendlyToFaction = "H", npcFlags = 4096 + 2 },
	[10] = { name = "Aubergiste", spawns = { [17] = { { 51.8, 29.9 } } }, friendlyToFaction = "AH", npcFlags = 65536 },
	[11] = { name = "[DND] Réparateur", spawns = { [17] = { { 51.0, 29.0 } } }, npcFlags = 4096 },
	[700] = { name = "Khazgorm", spawns = { [17] = { { 47.0, 35.0 } } }, minLevel = 25, maxLevel = 25, rank = 1 },
}
local OROWS = { [1732] = { name = "Filon d'étain", spawns = {} } }
local ORAW = { [1732] = { name = "Filon d'étain", spawns = { [17] = { { 53, 33 }, { 53.1, 33.1 } } } } }
local IROWS = { [5006] = { name = "Journal de Khazgorm", npcDrops = { 700 } } }

LibQuestieDB = {
	contractVersion = 4, readMode = "baked",
	RequireContract = function(v) return v == 4 end,
	Quest = Entity(QROWS), Npc = Entity(NROWS), Object = Entity(OROWS, ORAW), Item = Entity(IROWS),
	Meta = { QuestMeta = { questKeys = Keys(QKEYS) }, NpcMeta = { npcKeys = Keys(NKEYS) },
		ObjectMeta = { objectKeys = Keys(OKEYS) }, ItemMeta = { itemKeys = Keys(IKEYS) } },
	Enum = { raceMaskById = { [1] = 1, [2] = 2, [6] = 32 }, npcFlags = { REPAIR = 4096, INNKEEPER = 65536,
		FLIGHT_MASTER = 8192, VENDOR = 128 } },
	ObjectiveFirst = {},
	Support = { Get = function(name)
		if name == "ZoneDB" then
			return { private = { areaIdToUiMapId = "return { [17] = 1413, [14] = 1411 }", areaIdToUiMapIdOverride = "return {}",
				subZoneToParentZone = "return { [380] = 17 }", subZoneToParentZoneOverride = "return {}",
				dungeons = { [491] = { "Razorfen Kraul", { 1717 }, 17, { { 17, 42.9, 90.2 } } } } } }
		elseif name == "QuestXP" then
			return { db = { [100] = { 24, 1650 }, [300] = { 24, 1500 } } }
		end
	end },
}

LOG[1] = { info = { questID = 300, title = "Quête 300", level = 24, suggestedGroup = 0 },
	objectives = { { text = "Journal : 0/1", type = "item", finished = false, numFulfilled = 0, numRequired = 1 } },
	complete = false }
PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.52, 0.31

local ns = LoadAddon(ADDON_DIR, { "Donnees/Politique.lua", "Solver.lua", "Geo.lua", "Moteur.lua", "Data.lua",
	"Planner.lua", "Guide.lua", "UI.lua", "Options.lua", "Group.lua", "Gear.lua", "GearUI.lua", "Pilote.lua",
	"Autonomie.lua", "Montee.lua", "MonteeUI.lua", "Controle.lua", "Tri.lua", "Sacs.lua", "Core.lua" })
assert(ns.ext and ns.ext.CACHEES and next(ns.ext.CACHEES), "liste des quêtes cachées absente")
ns.ext.CACHEES[111] = true
Fire("ADDON_LOADED", "Itineraire")
Fire("PLAYER_LOGIN")
Advance(8)

-- 1. Le moteur choisi : interne, sans Questie
assert(ns.Data.Engine() == "interne", "moteur : " .. tostring(ns.Data.Engine()))
assert(ns.ready, "Itinéraire pas prêt sans Questie")
print("état :", ns.Moteur.State())

-- 2. Quêtes disponibles
local avail = ns.Data.AvailableQuests()
local function Is(id, want)
	assert((avail[id] and true or false) == want, "quête " .. id .. (want and " pas disponible" or " disponible à tort"))
end
for _, id in ipairs({ 100, 105, 107, 115, 116, 119 }) do Is(id, true) end
for _, id in ipairs({ 101, 102, 103, 104, 106, 108, 109, 110, 111, 112, 113, 117, 118, 200, 300 }) do Is(id, false) end
assert(ns.Moteur.availCount == 6, "nombre : " .. tostring(ns.Moteur.availCount))

-- 3. Forme des quêtes (comme QuestieDB.GetQuest)
local q = ns.Data.Quest(300)
assert(q.level == 24 and q.Finisher.NPC[1] == 9 and q.Starts.NPC[1] == 9, "quête 300")
assert(q.ObjectiveData[1].Type == "item" and q.ObjectiveData[1].Id == 5006, "objectif objet")
assert(q.ObjectiveData[2].Type == "event" and q.ObjectiveData[2].Coordinates[17], "objectif événement")
assert(ns.Data.Quest(119).level == 25, "niveau -1 = niveau du joueur")
local points = ns.Data.ObjectivePoints(q, 1)
assert(#points == 1 and points[1].map == 1413, "positions de l'objectif (Khazgorm)")
assert(ns.Data.CanTake(103, ns.Data.Quest(103)) == false and ns.Data.CanTake(105, ns.Data.Quest(105)), "CanTake")
assert(ns.Data.Completed(200) and not ns.Data.Completed(100), "quêtes faites")

-- 4. Zones, donjons, XP
assert(ns.Data.ZoneOfArea(380) == ns.Geo.Zone(1413) or ns.Data.ZoneOfArea(380) == 1413, "sous-zone -> Tarides")
assert(ns.Data.DungeonName(1717) == "Razorfen Kraul", "donjon (zone alternative)")
local entrance = ns.Data.DungeonEntrance(491)
assert(entrance and entrance.map == 1413, "entrée du donjon")
assert(ns.Data.QuestXP(100) == 1650, "XP : " .. tostring(ns.Data.QuestXP(100)))

-- 5. Habitants des villes (drapeaux des PNJ ; pas les [DND]) et maîtres de classe
local repair = ns.Data.RepairPoints()
assert(#repair == 1 and repair[1].npc == 9, "réparateurs : " .. #repair)
assert(#ns.Data.TownsfolkPoints("Innkeeper") == 1, "aubergistes")
assert(type(ns.Moteur.Townsfolk("Class Trainer")) == "table" and ns.Moteur.Townsfolk("Class Trainer")[1] == 911, "maîtres")

-- 6. Filons : positions de la base d'origine quand la base partagée les a vidées
local ore = ns.Data.ObjectPlaces(1732, 100)
assert(#ore == 2, "positions du filon : " .. #ore)

-- 7. Un vrai trajet, sans Questie
assert(ns.plan and #ns.plan.order > 0, "pas de trajet")
for k, s in ipairs(ns.plan.order) do print(k, s.kind, s.key, s.title) end

-- 8. Un rendu change la liste : la suite d'une quête faite n'est plus proposée, la quête rendue non plus
Fire("QUEST_TURNED_IN", 100)
Advance(6)
avail = ns.Data.AvailableQuests()
Is(100, false)
Is(106, true) -- son prérequis (100) est maintenant fait
print("OK moteur")
