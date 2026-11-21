-- Zones trop hautes pour le niveau du joueur (niveau 20, les Tarides 10-25, Désolace 30-40) : une quête du journal dont
-- les objectifs ou le rendu n'existent que là passe à la fin du trajet (jamais écartée) ; un objectif présent aussi
-- dans une zone de ton niveau s'y fait ; une quête à prendre, un marchand ou une auberge là-bas ne sont pas proposés.
dofile(TESTS .. "/wow_mock.lua")
time = function() return 1800000000 end
function UnitLevel() return 20 end
C_QuestLog.GetMaxNumQuestsCanAccept = function() return 20 end
MAPS[1443] = { name = "Désolace", ox = -12000, oy = 0, s = 8000, inst = 1 }
AREA_TO_MAP[405] = 1443

local function npc(id, name, spawns, level)
	NPCS[id] = { id = id, name = name, spawns = spawns, friendly = true, maxLevel = level }
end
npc(9, "Sergra", { [17] = { { 52.2, 31.0 } } })
npc(10, "Donneur de Désolace", { [405] = { { 50, 50 } } })
npc(106, "Zhévra", { [17] = { { 55, 33 }, { 56, 34 } } }, 18)
npc(107, "Kodo de Désolace", { [405] = { { 40, 40 }, { 41, 41 } } }, 19)
npc(108, "Raptor", { [17] = { { 48, 40 }, { 48.5, 40.5 } }, [405] = { { 60, 60 }, { 61, 61 } } }, 18)

local function logQuest(id, title, objectives, complete)
	LOG[#LOG + 1] = { info = { questID = id, title = title, level = 20, suggestedGroup = 0 }, objectives = objectives or {},
		complete = complete }
end
local function spawnList(id)
	return { { spawnList = { { Id = id, Name = NPCS[id].name, Spawns = NPCS[id].spawns, Hostile = true } } } }
end
local function obj(text) return { { text = text, type = "monster", finished = false, numFulfilled = 0, numRequired = 4 } } end
logQuest(301, "Ici", obj("Zhévra : 0/4"))
QUESTS[301] = { Id = 301, name = "Ici", level = 20, xp = 900, Finisher = { NPC = { 9 } }, Objectives = spawnList(106) }
logQuest(302, "Là-bas", obj("Kodo : 0/4"))
QUESTS[302] = { Id = 302, name = "Là-bas", level = 20, xp = 900, Finisher = { NPC = { 9 } }, Objectives = spawnList(107) }
logQuest(303, "Rendu là-bas", {}, true)
QUESTS[303] = { Id = 303, name = "Rendu là-bas", level = 20, xp = 900, Finisher = { NPC = { 10 } } }
logQuest(304, "Des deux côtés", obj("Raptor : 0/4"))
QUESTS[304] = { Id = 304, name = "Des deux côtés", level = 20, xp = 900, Finisher = { NPC = { 9 } }, Objectives = spawnList(108) }
-- à prendre : une en Désolace (pas proposée), une ici
QUESTS[401] = { Id = 401, name = "Offre de Désolace", level = 20, requiredLevel = 15, xp = 800, Starts = { NPC = { 10 } },
	Finisher = { NPC = { 10 } }, ObjectiveData = { { Type = "monster", Id = 107 } }, objectivesText = { "Tuez 3 kodos." } }
QUESTS[402] = { Id = 402, name = "Offre d'ici", level = 20, requiredLevel = 15, xp = 800, Starts = { NPC = { 9 } },
	Finisher = { NPC = { 9 } }, ObjectiveData = { { Type = "monster", Id = 106 } }, objectivesText = { "Tuez 3 zhévras." } }
AVAILABLE[401], AVAILABLE[402] = true, true

PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.52, 0.31
local ns = LoadAddon(ADDON_DIR, { "Solver.lua", "Geo.lua", "Data.lua", "Planner.lua", "Guide.lua", "UI.lua", "Options.lua",
	"Group.lua", "Core.lua" })
Fire("ADDON_LOADED", "Itineraire")
Fire("PLAYER_LOGIN")
Advance(5)

local D = ns.Data
-- 1. Les niveaux des zones
assert(D.ZoneDanger(1443, 20) == 30 and D.ZoneDanger(1443, 26) == 30 and D.ZoneDanger(1443, 27) == nil, "Désolace")
assert(D.ZoneDanger(1413, 20) == nil and D.ZoneDanger(1454, 1) == nil, "Tarides ou capitale comptées trop hautes")
assert(D.ZoneDanger(1450, 10) == nil, "Reflet-de-Lune compté trop haut (druides)")
local safe, danger = D.SafePoints({ { map = 1443 }, { map = 1413 } }, 20)
assert(#safe == 1 and safe[1].map == 1413 and not danger, "points sûrs")
safe, danger = D.SafePoints({ { map = 1443 } }, 20)
assert(#safe == 1 and danger and danger.low == 30 and D.DangerText(danger) == "zone niveau 30-40 : Désolace", "zone seule")

-- 2. Le trajet
local plan = ns.plan
local function Stop(pred)
	for k, s in ipairs(plan.order) do
		if pred(s) then return k, s end
	end
end
for k, s in ipairs(plan.order) do
	print(string.format("%2d. [%s] tier %s %s | %s", k, s.kind, tostring(s.tier), s.title, s.lateWhy or ""))
end
local kHere = Stop(function(s) return s.kind == "area" and s.questSet[301] end)
local kFar, sFar = Stop(function(s) return s.kind == "area" and s.questSet[302] end)
assert(kHere and kFar and sFar.tier == 1 and kFar > kHere, "objectif en Désolace : pas à la fin")
assert(sFar.lateWhy and sFar.lateWhy:find("zone niveau 30%-40 : Désolace"), "raison : " .. tostring(sFar.lateWhy))
local _, sTurn = Stop(function(s) return s.kind == "turnin" and s.questSet[303] end)
assert(sTurn and sTurn.tier == 1 and sTurn.lateWhy and sTurn.lateWhy:find("Désolace"), "rendu en Désolace : pas à la fin")
local _, sBoth = Stop(function(s) return s.kind == "area" and s.questSet[304] end)
assert(sBoth and sBoth.map == 1413 and sBoth.tier ~= 1, "objectif des deux côtés : pas fait ici, maintenant")
-- aucune quête du journal écartée
for _, id in ipairs({ 301, 302, 303, 304 }) do
	assert(Stop(function(s) return s.questSet[id] end), "quête " .. id .. " absente du trajet")
end
-- quêtes à prendre : celle de Désolace jamais proposée
for _, s in ipairs(plan.order) do
	for _, p in ipairs(s.pickups or {}) do
		assert(p.id ~= 401, "quête à prendre en Désolace proposée")
	end
	assert(not (s.candidate and s.candidate.id == 401), "quête de Désolace proposée")
end
print("OK zones trop hautes")
