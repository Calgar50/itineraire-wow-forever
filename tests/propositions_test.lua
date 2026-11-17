-- Quêtes proposées sur le trajet, suites de quêtes, arrêt réparer / vendre.
dofile(TESTS .. "/wow_mock.lua")

local function npc(id, name, area, pts, level, friendly)
	NPCS[id] = { id = id, name = name, spawns = { [area] = pts }, friendly = friendly ~= false, maxLevel = level }
end
-- La Croisée (Tarides, 1 % = 100 yards)
npc(8, "Thork", 17, { { 51.5, 30.3 } })
npc(9, "Sergra Darkthorn", 17, { { 52.2, 31.0 } })
npc(13, "Gazrog", 17, { { 51.7, 29.9 } })
npc(106, "Zhévra", 17, { { 55, 33 }, { 56, 34 }, { 57, 32 }, { 55.5, 33.5 } }, 12)
npc(111, "Harpie Ensorçaile", 17, { { 39, 13 }, { 40, 14 }, { 39.5, 12.5 } }, 14)
npc(113, "Tranchecrin voleur", 17, { { 55, 36 }, { 56, 36.5 } }, 15)
npc(120, "Kodo égaré", 17, { { 30, 85 }, { 31, 86 } }, 15)
npc(601, "Forgeron de la Croisée", 17, { { 52.6, 29.6 } })
npc(602, "Forgeron lointain", 17, { { 45, 75 } })
npc(603, "Forgeron de l'Alliance", 17, { { 52.0, 30.5 } }, nil, false)
OBJECTS[501] = { id = 501, name = "Caisse égarée", spawns = { [17] = { { 56.5, 33.2 }, { 56.8, 33.6 } } } }

local function logQuest(id, title, level, objectives, complete)
	LOG[#LOG + 1] = { info = { questID = id, title = title, level = level, suggestedGroup = 0 }, objectives = objectives or {}, complete = complete }
end
-- Journal : 3 quêtes
logQuest(1001, "Les zhévras", 15, { { text = "Zhévra tué : 0/6", type = "monster", finished = false, numFulfilled = 0, numRequired = 6 } })
QUESTS[1001] = {
	Id = 1001, name = "Les zhévras", level = 15, xp = 900, Finisher = { NPC = { 9 } }, nextQuestInChain = 1002,
	Objectives = { { spawnList = { { Id = 106, Name = "Zhévra", Spawns = NPCS[106].spawns, Hostile = true } } } },
}
logQuest(1003, "Message pour Thork", 15, {}, true)
QUESTS[1003] = { Id = 1003, name = "Message pour Thork", level = 15, xp = 300, Finisher = { NPC = { 8 } } }
logQuest(1004, "Les harpies", 15, { { text = "Griffe : 0/8", type = "item", finished = false, numFulfilled = 0, numRequired = 8 } })
QUESTS[1004] = {
	Id = 1004, name = "Les harpies", level = 15, xp = 1100, Finisher = { NPC = { 13 } },
	Objectives = { { spawnList = { { Id = 111, Name = "Harpie", Spawns = NPCS[111].spawns, Hostile = true } } } },
}
-- Suite de 1001 : se prend chez Sergra, à faire juste à côté
QUESTS[1002] = {
	Id = 1002, name = "Les voleurs Tranchecrin", level = 15, requiredLevel = 12, xp = 1000,
	Starts = { NPC = { 9 } }, Finisher = { NPC = { 9 } }, preQuestSingle = { 1001 },
	ObjectiveData = { { Type = "monster", Id = 113 } },
}
-- Quêtes disponibles
QUESTS[2001] = { -- sur le trajet : à prendre chez Gazrog, objet à côté des zhévras
	Id = 2001, name = "Caisses égarées", level = 15, requiredLevel = 10, xp = 850,
	Starts = { NPC = { 13 } }, Finisher = { NPC = { 13 } }, ObjectiveData = { { Type = "object", Id = 501 } },
}
QUESTS[2002] = { -- loin du trajet
	Id = 2002, name = "Le kodo égaré", level = 15, requiredLevel = 10, xp = 700,
	Starts = { NPC = { 8 } }, Finisher = { NPC = { 8 } }, ObjectiveData = { { Type = "monster", Id = 120 } },
}
QUESTS[2003] = { -- trop haut niveau
	Id = 2003, name = "Trop dur", level = 25, requiredLevel = 20, xp = 3000,
	Starts = { NPC = { 13 } }, Finisher = { NPC = { 13 } }, ObjectiveData = { { Type = "monster", Id = 106 } },
}
AVAILABLE[2001], AVAILABLE[2002], AVAILABLE[2003] = true, true, true

-- Équipement : un objet à 20 % -> réparer (pas urgent)
DURABILITY = { [1] = { 80, 100 }, [5] = { 20, 100 } }
function GetInventoryItemDurability(slot)
	local d = DURABILITY[slot]
	if d then return d[1], d[2] end
end
C_Container = { GetContainerNumFreeSlots = function(bag) return bag == 0 and 10 or 0, 0 end }
TOWNSFOLK = { townsfolk = { Repair = { 601, 602, 603 } } }
local importModule = QuestieLoader.ImportModule
QuestieLoader.ImportModule = function(self, name)
	if name == "Townsfolk" then return TOWNSFOLK end
	return importModule(self, name)
end

PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.515, 0.303
local ns = LoadAddon(ADDON_DIR, { "Solver.lua", "Geo.lua", "Data.lua", "Planner.lua", "Guide.lua", "UI.lua", "Options.lua", "Group.lua", "Core.lua" })
Fire("ADDON_LOADED", "Itineraire")
Fire("PLAYER_LOGIN")
Advance(5)

local function Show(label)
	local plan = ns.plan
	print("==== " .. label .. " : " .. #plan.order .. " étapes, trajet " .. math.floor(plan.travel) .. " s")
	for k, s in ipairs(plan.order) do
		print(string.format("%2d. [%s] %s  |  %s", k, s.kind, s.title, s.subtitle or ""))
	end
end
local function Pos(pred)
	for k, s in ipairs(ns.plan.order) do
		if pred(s) then return k end
	end
end
local function Check()
	-- prise avant objectifs et rendu de chaque quête proposée ; suite après le rendu de la quête d'avant
	for _, q in ipairs(ns.plan.candidates) do
		local pick = Pos(function(s) return s.kind == "pickup" and s.candidate == q end)
		assert(pick, "pas d'étape de prise pour " .. q.title)
		for k, s in ipairs(ns.plan.order) do
			if s.kind ~= "pickup" and s.questSet[q.id] then
				assert(k > pick, "étape de « " .. q.title .. " » avant sa prise")
			end
		end
		if q.chainOf then
			local prev = Pos(function(s) return s.kind == "turnin" and s.questSet[q.chainOf.id] end)
			assert(prev and prev < pick, "suite prise avant le rendu de la quête d'avant")
		end
	end
end

Show("départ")
local names = {}
for _, q in ipairs(ns.plan.candidates) do names[q.id] = true end
assert(names[1002], "la suite 1002 devrait être proposée")
assert(names[2001], "la quête 2001 (sur le trajet) devrait être proposée")
assert(not names[2002], "2002 est loin : pas proposée")
assert(not names[2003], "2003 est trop dure : pas proposée")
Check()
local repair = Pos(function(s) return s.kind == "service" end)
assert(repair, "pas d'arrêt réparer")
assert(ns.plan.order[repair].npcName == "Forgeron de la Croisée", "mauvais réparateur : " .. tostring(ns.plan.order[repair].npcName))
assert(SP_ROUTES[#SP_ROUTES][repair].kind == nil, "« vendor » fait planter Shortest Path 1.37 : ne pas l'envoyer")
print("advice ok:", ns.plan.errands[1].label)

-- Le joueur prend « Caisses égarées » : elle devient une quête normale du journal.
logQuest(2001, "Caisses égarées", 15, { { text = "Caisse égarée : 0/1", type = "object", finished = false, numFulfilled = 0, numRequired = 1 } })
QUESTS[2001].Objectives = { { spawnList = { { Id = 501, Name = "Caisse égarée", Spawns = OBJECTS[501].spawns } } } }
AVAILABLE[2001] = nil
Fire("QUEST_ACCEPTED", 2001)
Advance(5)
Show("après avoir pris 2001")
assert(not Pos(function(s) return s.kind == "pickup" and s.pickups[1].id == 2001 end), "2001 encore à prendre")
assert(Pos(function(s) return s.kind == "turnin" and s.questSet[2001] end), "2001 pas rendue sur le trajet")
Check()

-- Le joueur refuse la suite (clic droit > passer).
ns.SkipStop(ns.plan.order[Pos(function(s) return s.kind == "pickup" and s.candidate and s.candidate.id == 1002 end)].key)
Advance(5)
assert(not Pos(function(s) return s.candidate and s.candidate.id == 1002 end), "la suite refusée revient")

-- Passage chez le forgeron : l'arrêt disparaît.
DURABILITY[5] = { 100, 100 }
Fire("UPDATE_INVENTORY_DURABILITY")
Advance(5)
assert(not Pos(function(s) return s.kind == "service" end), "arrêt réparer encore là après réparation")
-- Sacs pleins : arrêt urgent en premier.
C_Container.GetContainerNumFreeSlots = function() return 0, 0 end
Fire("BAG_UPDATE_DELAYED")
Advance(5)
Show("sacs pleins")
assert(ns.plan.order[1].kind == "service" and ns.plan.order[1].service.urgent, "sacs pleins : vendre d'abord")
Fire("MERCHANT_CLOSED")
Advance(5)
assert(not Pos(function(s) return s.kind == "service" end), "arrêt vendre encore là après le marchand")
print("OK propositions")
