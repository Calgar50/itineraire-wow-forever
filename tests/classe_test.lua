-- Quêtes à prendre réservées à une autre classe (ou race, métier, quête exclusive) : jamais proposées.
dofile(TESTS .. "/wow_mock.lua")

local function npc(id, name, area, pts, level)
	NPCS[id] = { id = id, name = name, spawns = { [area] = pts }, friendly = true, maxLevel = level }
end
npc(9, "Sergra Darkthorn", 17, { { 52.2, 31.0 } })
npc(13, "Gazrog", 17, { { 51.7, 29.9 } })
npc(106, "Zhévra", 17, { { 55, 33 }, { 56, 34 }, { 57, 32 }, { 55.5, 33.5 } }, 12)
npc(113, "Tranchecrin voleur", 17, { { 55, 36 }, { 56, 36.5 } }, 15)
OBJECTS[501] = { id = 501, name = "Caisse égarée", spawns = { [17] = { { 56.5, 33.2 }, { 56.8, 33.6 } } } }

LOG[1] = {
	info = { questID = 1001, title = "Les zhévras", level = 15, suggestedGroup = 0 },
	objectives = { { text = "Zhévra tué : 0/6", type = "monster", finished = false, numFulfilled = 0, numRequired = 6 } },
}
QUESTS[1001] = {
	Id = 1001, name = "Les zhévras", level = 15, xp = 900, Finisher = { NPC = { 9 } }, nextQuestInChain = 1002,
	Objectives = { { spawnList = { { Id = 106, Name = "Zhévra", Spawns = NPCS[106].spawns, Hostile = true } } } },
}
-- Suite réservée aux voleurs (masque 8) : ne doit pas être proposée à un guerrier.
QUESTS[1002] = {
	Id = 1002, name = "Leçon de voleur", level = 15, requiredLevel = 12, xp = 1000, requiredClasses = 8,
	Starts = { NPC = { 9 } }, Finisher = { NPC = { 9 } }, preQuestSingle = { 1001 },
	ObjectiveData = { { Type = "monster", Id = 113 } },
}
-- Sur le trajet : réservée aux mages (masque 128).
QUESTS[2004] = {
	Id = 2004, name = "Le grimoire du mage", level = 15, requiredLevel = 10, xp = 1500, requiredClasses = 128,
	Starts = { NPC = { 13 } }, Finisher = { NPC = { 13 } }, ObjectiveData = { { Type = "object", Id = 501 } },
}
-- Sur le trajet : pour guerriers et paladins (masque 1 + 2) -> proposée.
QUESTS[2005] = {
	Id = 2005, name = "Caisses du guerrier", level = 15, requiredLevel = 10, xp = 1200, requiredClasses = 3,
	Starts = { NPC = { 13 } }, Finisher = { NPC = { 13 } }, ObjectiveData = { { Type = "object", Id = 501 } },
}
-- Réservée à une race (masque 1 = humain) et exclusive avec 1001 (dans le journal).
QUESTS[2006] = {
	Id = 2006, name = "Pour les humains", level = 15, requiredLevel = 10, xp = 1400, requiredRaces = 1,
	Starts = { NPC = { 13 } }, Finisher = { NPC = { 13 } }, ObjectiveData = { { Type = "object", Id = 501 } },
}
QUESTS[2007] = {
	Id = 2007, name = "L'autre choix", level = 15, requiredLevel = 10, xp = 1400, exclusiveTo = { 1001 },
	Starts = { NPC = { 13 } }, Finisher = { NPC = { 13 } }, ObjectiveData = { { Type = "object", Id = 501 } },
}
AVAILABLE[2004], AVAILABLE[2005], AVAILABLE[2006], AVAILABLE[2007] = true, true, true, true

-- QuestiePlayer simulé : ALL = vrai -> tout le monde peut tout faire (pour prouver que le test mord).
ALL = true
local PLAYER_MOD = {
	HasRequiredClass = function(mask) return ALL or not mask or mask == 0 or mask % 2 >= 1 end, -- guerrier = bit 1
	HasRequiredRace = function(mask) return ALL or not mask or mask == 0 or mask % 4 >= 2 end, -- orc = bit 2
}
local importModule = QuestieLoader.ImportModule
QuestieLoader.ImportModule = function(self, name)
	if name == "QuestiePlayer" then return PLAYER_MOD end
	return importModule(self, name)
end
function UnitClass() return "Guerrier", "WARRIOR", 1 end

PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.515, 0.303
local ns = LoadAddon(ADDON_DIR, { "Solver.lua", "Geo.lua", "Data.lua", "Planner.lua", "Guide.lua", "UI.lua", "Options.lua", "Group.lua", "Core.lua" })
Fire("ADDON_LOADED", "Itineraire")
Fire("PLAYER_LOGIN")
Advance(5)

local function Names()
	local names = {}
	for _, q in ipairs(ns.plan.candidates or {}) do
		names[q.id] = true
	end
	return names
end
local function Proposed()
	local list = {}
	for id in pairs(Names()) do list[#list + 1] = id end
	table.sort(list)
	return table.concat(list, ",")
end

-- 1. Sans contrôle de classe, le décor propose bien ces quêtes (sinon le test ne prouverait rien).
local names = Names()
print("tout autorisé :", Proposed())
assert(names[1002], "décor : la suite 1002 devrait être proposée quand tout est permis")
assert(names[2004] or names[2005] or names[2006], "décor : une quête sur le trajet devrait être proposée")

-- 2. Guerrier orc : plus aucune quête d'une autre classe / race, ni la quête exclusive.
ALL = false
ns.RequestPlan("test", 0)
Advance(5)
names = Names()
print("guerrier orc :", Proposed())
assert(not names[1002], "suite réservée aux voleurs proposée à un guerrier")
assert(not names[2004], "quête de mage proposée à un guerrier")
assert(not names[2006], "quête d'une autre race proposée")
assert(not names[2007], "quête exclusive d'une quête du journal proposée")
for _, s in ipairs(ns.plan.order) do
	for _, p in ipairs(s.pickups or {}) do
		assert(p.id ~= 2004 and p.id ~= 1002 and p.id ~= 2006 and p.id ~= 2007, "étape « prendre » interdite : " .. p.id)
	end
end
assert(names[2005], "la quête ouverte aux guerriers doit rester proposée")

-- 3. Les raisons, et le repli sans Questie (classe lue dans le jeu ; race inconnue -> on garde).
local D = ns.Data
assert(select(2, D.CanTake(2004)) == "classe")
assert(select(2, D.CanTake(2006)) == "race")
assert(select(2, D.CanTake(2007)) == "exclusive" or not D.CanTake(2007, nil, { [1001] = true }))
assert(D.CanTake(2005) == true)
PLAYER_MOD.HasRequiredClass, PLAYER_MOD.HasRequiredRace = nil, nil
assert(D.CanTake(2004) == false, "repli UnitClass : quête de mage refusée")
assert(D.CanTake(2005) == true, "repli UnitClass : quête de guerrier acceptée")
assert(D.CanTake(2006) == true, "sans Questie, la race est inconnue : on ne retire rien")
UnitClass = nil
assert(D.CanTake(2004) == true, "classe inconnue : on ne retire rien")
print("OK classe")
