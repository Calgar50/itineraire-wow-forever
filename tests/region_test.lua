-- Mode région (toute la région d'abord, ses quêtes à prendre comprises, journal limité) et route des rendus.
dofile(TESTS .. "/wow_mock.lua")
time = function() return 1800000000 end
function UnitLevel() return 15 end
C_QuestLog.GetMaxNumQuestsCanAccept = function() return 6 end

local function npc(id, name, area, pts, level)
	NPCS[id] = { id = id, name = name, spawns = { [area] = pts }, friendly = true, maxLevel = level }
end
-- La Croisée et les Tarides (zone 17), Durotar (14), Orgrimmar (1637)
npc(8, "Thork", 17, { { 51.5, 30.3 } })
npc(9, "Sergra Darkthorn", 17, { { 52.2, 31.0 } })
npc(13, "Gazrog", 17, { { 51.7, 29.9 } })
npc(4, "Migi", 1637, { { 50, 60 } })
npc(106, "Zhévra", 17, { { 55, 33 }, { 56, 34 } }, 13)
npc(140, "Scorpide de Durotar", 14, { { 40, 50 }, { 41, 51 } }, 10)
for i = 1, 6 do
	npc(150 + i, "Bête " .. i, 17, { { 45 + i, 25 + i }, { 45.5 + i, 25.5 + i } }, 13)
end

local function logQuest(id, title, objectives, complete)
	LOG[#LOG + 1] = { info = { questID = id, title = title, level = 15, suggestedGroup = 0 }, objectives = objectives or {}, complete = complete }
end
local function spawnList(id)
	return { { spawnList = { { Id = id, Name = NPCS[id].name, Spawns = NPCS[id].spawns, Hostile = true } } } }
end
-- A : tout dans la région ; B : rendu ici mais objectif en Durotar ; C : finie, à rendre à Orgrimmar ;
-- D : finie, à rendre à la Croisée.
logQuest(101, "A zhévras", { { text = "Zhévra : 0/4", type = "monster", finished = false, numFulfilled = 0, numRequired = 4 } })
QUESTS[101] = { Id = 101, name = "A zhévras", level = 15, xp = 900, Finisher = { NPC = { 9 } }, Objectives = spawnList(106) }
logQuest(102, "B scorpides", { { text = "Scorpide : 0/5", type = "monster", finished = false, numFulfilled = 0, numRequired = 5 } })
QUESTS[102] = { Id = 102, name = "B scorpides", level = 15, xp = 900, Finisher = { NPC = { 8 } }, Objectives = spawnList(140) }
logQuest(103, "C pour Migi", {}, true)
QUESTS[103] = { Id = 103, name = "C pour Migi", level = 15, xp = 500, Finisher = { NPC = { 4 } } }
logQuest(104, "D pour Gazrog", { { text = "Objet : 1/1", type = "item", finished = true, numFulfilled = 1, numRequired = 1 } }, true)
QUESTS[104] = { Id = 104, name = "D pour Gazrog", level = 15, xp = 700, Finisher = { NPC = { 13 } } }
-- 6 quêtes à prendre dans la région (plus que les 4 proposées d'habitude), journal : 4 + 2 places.
for i = 1, 6 do
	local id = 200 + i
	QUESTS[id] = { Id = id, name = "Région " .. i, level = 15, requiredLevel = 10, xp = 800,
		Starts = { NPC = { i % 2 == 0 and 8 or 13 } }, Finisher = { NPC = { i % 2 == 0 and 8 or 13 } },
		ObjectiveData = { { Type = "monster", Id = 150 + i } }, objectivesText = { "Tuez 3 bêtes." } }
	AVAILABLE[id] = true
end

PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.52, 0.31
local ns = LoadAddon(ADDON_DIR, { "Solver.lua", "Geo.lua", "Data.lua", "Planner.lua", "Guide.lua", "UI.lua", "Options.lua", "Group.lua", "Core.lua" })
Fire("ADDON_LOADED", "Itineraire")
Fire("PLAYER_LOGIN")
Advance(5)

local function Show(label)
	print("==== " .. label)
	for k, s in ipairs(ns.plan.order) do
		print(string.format("%2d. [%s] %s  |  %s%s", k, s.kind, s.title, s.subtitle or "", s.away and "  (après la région)" or ""))
	end
end
local function Pos(pred)
	for k, s in ipairs(ns.plan.order) do
		if pred(s) then return k, s end
	end
end
Show("mode région")
local plan = ns.plan

-- 1. Journal 4/6 : 2 places + 2 rendus dans la région = 4 quêtes de la région proposées tout de suite
--    (les autres viendront au fil des rendus), regroupées par donneur.
assert(#plan.candidates == 4, "quêtes de la région proposées : " .. #plan.candidates)
local pickups = 0
for _, s in ipairs(plan.order) do
	if s.kind == "pickup" then pickups = pickups + 1 end
end
assert(pickups <= 4, "prises non regroupées par donneur : " .. pickups)

-- 2. Région d'abord : aucune étape « ailleurs » avant une étape de la région.
local lastHere, firstAway = 0, math.huge
for k, s in ipairs(plan.order) do
	if s.away then firstAway = math.min(firstAway, k) elseif s.tier <= 0 then lastHere = k end
end
assert(lastHere < firstAway, "une étape ailleurs passe avant la fin de la région")
-- Le rendu de B (à la Croisée) dépend d'un objectif en Durotar : il passe après, lui aussi.
local kB, tB = Pos(function(s) return s.kind == "turnin" and s.questSet[102] end)
assert(tB and tB.away, "rendu de B : devrait passer après la région (objectif en Durotar)")
local kC, tC = Pos(function(s) return s.kind == "turnin" and s.questSet[103] end)
assert(tC and tC.away, "rendu de C (Orgrimmar) : après la région")

-- 3. Journal : jamais plus de 6 quêtes en même temps.
local count, peak = 4, 4
for _, s in ipairs(plan.order) do
	if s.kind == "pickup" then
		count = count + #(s.candidates or { 1 })
	elseif s.kind == "turnin" then
		for _, q in ipairs(s.quests) do count = count - 1 end
	end
	peak = math.max(peak, count)
end
assert(peak <= 6, "journal dépassé : " .. peak)
print("journal au plus haut :", peak, "/ 6")

-- 3b. Journal plus grand : les 6 quêtes de la région (au-delà des 4 proposées d'habitude).
C_QuestLog.GetMaxNumQuestsCanAccept = function() return 12 end
ns.RequestPlan("t", 0)
Advance(5)
assert(#ns.plan.candidates == 6, "toutes les quêtes de la région : " .. #ns.plan.candidates)
C_QuestLog.GetMaxNumQuestsCanAccept = function() return 6 end
ns.RequestPlan("t", 0)
Advance(5)

-- 4. Route des rendus : seulement C et D (la région d'abord : D à la Croisée, puis C à Orgrimmar).
SlashCmdList.ITINERAIRE("rendus")
Advance(5)
Show("route des rendus")
plan = ns.plan
assert(plan.turninOnly and #plan.order == 2, "route des rendus : " .. #plan.order .. " étapes")
assert(plan.order[1].questSet[104] and plan.order[2].questSet[103], "ordre des rendus")
local summary
for _, f in ipairs(FONTS) do
	if tostring(f.text):find("Rendus seulement") then summary = f.text end
end
assert(summary, "résumé : rendus seulement")
-- Tout rendu : retour automatique au trajet complet.
for i = #LOG, 1, -1 do
	if LOG[i].complete then table.remove(LOG, i) end
end
Fire("QUEST_TURNED_IN", 104)
Advance(5)
assert(not ns.plan.turninOnly and #ns.plan.order > 0, "pas de retour au trajet complet")
local said
for _, m in ipairs(PRINTED) do
	if m:find("tout est rendu") then said = true end
end
assert(said, "message « tout est rendu » absent")
print("OK région et rendus")
