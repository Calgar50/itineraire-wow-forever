-- Précision : rythme mesuré (chasse et déplacements), XP de repos, groupe/élites, quantités lues, horloge.
dofile(TESTS .. "/wow_mock.lua")
time = function() return 1800000000 end

local function npc(id, name, area, pts, level, rank)
	NPCS[id] = { id = id, name = name, spawns = { [area] = pts }, friendly = true, maxLevel = level, rank = rank }
end
npc(9, "Sergra Darkthorn", 17, { { 52.2, 31.0 } })
npc(13, "Gazrog", 17, { { 51.7, 29.9 } })
npc(106, "Zhévra", 17, { { 55, 33 }, { 56, 34 }, { 57, 32 }, { 55.5, 33.5 } }, 12)
npc(130, "Chef Kolkar", 17, { { 47, 36 } }, 16, 1) -- élite de ton niveau
OBJECTS[501] = { id = 501, name = "Caisse égarée", spawns = { [17] = { { 53.5, 31.2 }, { 53.8, 31.6 } } } }

local function logQuest(id, title, level, objectives, group)
	LOG[#LOG + 1] = { info = { questID = id, title = title, level = level, suggestedGroup = group or 0 }, objectives = objectives or {} }
end
logQuest(1001, "Les zhévras", 15, { { text = "Zhévra tué : 0/6", type = "monster", finished = false, numFulfilled = 0, numRequired = 6 } })
QUESTS[1001] = {
	Id = 1001, name = "Les zhévras", level = 15, xp = 900, Finisher = { NPC = { 9 } },
	Objectives = { { spawnList = { { Id = 106, Name = "Zhévra", Spawns = NPCS[106].spawns, Hostile = true } } } },
}
logQuest(1005, "Le chef kolkar", 16, { { text = "Chef Kolkar tué : 0/1", type = "monster", finished = false, numFulfilled = 0, numRequired = 1 } })
QUESTS[1005] = {
	Id = 1005, name = "Le chef kolkar", level = 16, xp = 1200, Finisher = { NPC = { 9 } },
	Objectives = { { spawnList = { { Id = 130, Name = "Chef Kolkar", Spawns = NPCS[130].spawns, Hostile = true } } } },
}
QUESTS[2001] = {
	Id = 2001, name = "Caisses égarées", level = 15, requiredLevel = 10, xp = 850,
	Starts = { NPC = { 13 } }, Finisher = { NPC = { 13 } }, ObjectiveData = { { Type = "object", Id = 501 } },
	objectivesText = { "Rapportez 5 caisses égarées à Gazrog, à la Croisée." },
}
AVAILABLE[2001] = true

PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.515, 0.303
local ns = LoadAddon(ADDON_DIR, { "Solver.lua", "Geo.lua", "Data.lua", "Planner.lua", "Guide.lua", "UI.lua", "Options.lua", "Group.lua", "Core.lua" })
Fire("ADDON_LOADED", "Itineraire")
Fire("PLAYER_LOGIN")
Advance(5)

local function StopOf(pred)
	for _, s in ipairs(ns.plan.order) do
		if pred(s) then return s end
	end
end
local function Quest(id)
	for _, q in ipairs(ns.plan.quests) do
		if q.id == id then return q end
	end
end

-- 1. Élites de ton niveau : la quête passe « plus tard » (groupe conseillé), pas d'avance automatique.
local kolkar = Quest(1005)
assert(kolkar.late and kolkar.late:find("^élites"), "élites non détectées : " .. tostring(kolkar.late))
assert(not kolkar.needLevel, "une quête d'élites ne doit pas être avancée au niveau")
-- 2. Quantité lue dans le texte de la quête proposée.
local crate = ns.plan.candidates[1]
assert(crate and crate.id == 2001, "quête 2001 pas proposée")
assert(crate.objectives[1].numRequired == 5, "quantité lue : " .. tostring(crate.objectives[1].numRequired))
-- 3. Horloge : heure de fin dans le résumé.
local summary
for _, f in ipairs(FONTS) do
	if tostring(f.text):find("fin vers") then summary = f.text end
end
assert(summary, "pas d'heure de fin dans le résumé")
print("résumé :", summary)

-- 4. Rythme de chasse : un zhévra toutes les 20 s.
local zhevra = LOG[1].objectives[1]
local defaultWork = StopOf(function(s) return s.kind == "area" and s.questSet[1001] end).work
Fire("QUEST_LOG_UPDATE") -- 1re lecture : 0/6
Advance(100)
local function Kill()
	zhevra.numFulfilled = zhevra.numFulfilled + 1
	zhevra.text = "Zhévra tué : " .. zhevra.numFulfilled .. "/6"
	Fire("QUEST_LOG_UPDATE")
end
Kill() -- 1er : compte le trajet, pas mesuré
for _ = 1, 3 do
	Advance(20)
	Kill()
end
Advance(5)
local rates = ns.Rates()
assert(rates.monster and math.abs(rates.monster - 20) < 0.5, "rythme monstre : " .. tostring(rates.monster))
local work = StopOf(function(s) return s.kind == "area" and s.questSet[1001] end).work
print("travail zhévras : " .. defaultWork .. " s par défaut (6 restants) -> " .. work .. " s mesurés (2 restants)")
assert(math.abs(work - 40) < 1, "travail recalculé avec le rythme mesuré : " .. work)

-- 5. Rythme de déplacement : 1,5 fois plus lent que prévu, sur 3 trajets.
ns.ready = false -- pas de recalcul pendant la mesure
for k = 1, 3 do
	local wx, wy, inst = ns.Geo.World(1413, 0.60, 0.30)
	ns.plan = { order = { { key = "X" .. k, leg = 60, legWalk = true, radius = 10, map = 1413, x = 0.60, y = 0.30, wx = wx, wy = wy, inst = inst } } }
	PLAYER.x, PLAYER.y = 0.55, 0.30
	Advance(1)
	Advance(89)
	PLAYER.x, PLAYER.y = 0.60, 0.30
	Advance(1)
end
local pace = ns.Pace()
assert(math.abs(pace - 1.5) < 0.05, "rythme de déplacement : " .. tostring(pace))
print("rythme :", ns.PaceText())
ns.ready = true
PLAYER.x, PLAYER.y = 0.515, 0.303
ns.RequestPlan("t", 0)
Advance(5)
local a, b = { wx = 0, wy = 0, inst = 1 }, { wx = 700, wy = 0, inst = 1 }
assert(math.abs(ns.Geo.Walk(a, b, 7) - 700 * 1.25 * 1.5 / 7) < 0.01, "marche non ajustée au rythme")

-- 6. XP de repos : le niveau prévu en fin de trajet monte.
local before = ns.plan.levelEnd
function GetXPExhaustion() return 4000 end
ns.RequestPlan("t", 0)
Advance(5)
assert(ns.plan.levelEnd > before, "repos ignoré : " .. before .. " -> " .. ns.plan.levelEnd)
print(string.format("niveau prévu : %.2f sans repos, %.2f avec repos", before, ns.plan.levelEnd))

-- 7. En groupe : la quête d'élites revient sur le trajet.
function IsInGroup() return true end
function GetNumGroupMembers() return 3 end
Fire("GROUP_ROSTER_UPDATE")
Advance(5)
assert(not Quest(1005).late, "en groupe, les élites ne sont plus « plus tard »")

-- 8. Commande /iti rythme
SlashCmdList.ITINERAIRE("rythme")
SlashCmdList.ITINERAIRE("rythme reset")
assert(ns.Pace() == 1 and not next(ns.Rates()), "remise à zéro du rythme")

-- 9. Étape en cours : le vrai temps restant de la flèche (affichage seulement).
-- (deux calculs : le 1er fixe l'étape en cours, le 2e reprend le temps de la flèche pour elle)
ShortestPathForever.API.Journey = function() return { owner = "Itineraire", secondsLeft = 432 } end
ns.RequestPlan("t", 0)
Advance(3)
ns.RequestPlan("t", 0)
Advance(3)
local first = ns.plan.order[1]
assert(first.leg == 432 and first.legExact, "temps exact non repris : " .. tostring(first.leg) .. " key " .. tostring(first.key) .. " prev " .. tostring(ns.session.previous) .. " err " .. tostring(ns.char.lastError and ns.char.lastError.text))
assert(first.legModel ~= 432, "le modèle doit garder sa propre estimation")
print("OK rythme")
