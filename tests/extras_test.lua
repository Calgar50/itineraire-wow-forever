-- Maître de classe, préparation des donjons, pierre de foyer.
dofile(TESTS .. "/wow_mock.lua")
time = function() return 1800000000 end
function UnitLevel() return 18 end
function UnitClass() return "Guerrier", "WARRIOR" end
ItineraireCharDB = { trainedAt = 16 } -- dernière visite au maître : niveau 16

local function npc(id, name, area, pts, level)
	NPCS[id] = { id = id, name = name, spawns = { [area] = pts }, friendly = true, maxLevel = level }
end
npc(4, "Migi", 1637, { { 50, 60 } })
npc(9, "Sergra Darkthorn", 17, { { 52.2, 31.0 } })
npc(102, "Culte de la Lame ardente", 2437, { { -1, -1 } }, 16)
npc(101, "Chaman Ragefeu", 2437, { { -1, -1 } }, 15)
npc(106, "Zhévra", 17, { { 55, 33 }, { 56, 34 }, { 57, 32 } }, 15)
npc(701, "Sorek", 17, { { 52.0, 30.0 } }) -- maître guerrier de la Croisée
npc(702, "Maître guerrier lointain", 1442, { { 50, 50 } })
npc(801, "Aubergiste Boorand", 17, { { 51.9, 29.8 } })
npc(802, "Aubergiste d'Orgrimmar", 1637, { { 54, 68 } })

LOG[1] = { info = { questID = 5725, title = "Le pouvoir de détruire", level = 16, suggestedGroup = 0 },
	objectives = { { text = "Culte : 0/4", type = "monster", finished = false, numFulfilled = 0, numRequired = 4 } } }
QUESTS[5725] = { Id = 5725, name = "Le pouvoir de détruire", level = 16, xp = 1200, Finisher = { NPC = { 4 } },
	ObjectiveData = { { Type = "monster", Id = 102 } } }
LOG[2] = { info = { questID = 1001, title = "Les zhévras", level = 17, suggestedGroup = 0 },
	objectives = { { text = "Zhévra : 0/6", type = "monster", finished = false, numFulfilled = 0, numRequired = 6 } } }
QUESTS[1001] = { Id = 1001, name = "Les zhévras", level = 17, xp = 1000, Finisher = { NPC = { 9 } },
	Objectives = { { spawnList = { { Id = 106, Name = "Zhévra", Spawns = NPCS[106].spawns, Hostile = true } } } } }
-- Quête de donjon pas encore prise : chez Migi, à Orgrimmar, à faire dans le Gouffre de Ragefeu.
QUESTS[3001] = { Id = 3001, name = "Chamans du Gouffre", level = 16, requiredLevel = 13, xp = 1500,
	Starts = { NPC = { 4 } }, Finisher = { NPC = { 4 } }, ObjectiveData = { { Type = "monster", Id = 101 } },
	objectivesText = { "Tuez 6 Chamans Ragefeu." } }
AVAILABLE[3001] = true

TOWNSFOLK = {
	townsfolk = { Innkeeper = { 801, 802 }, Repair = {} },
	classSpecificTownsfolk = { WARRIOR = { ["Class Trainer"] = { 701, 702 } } },
}
local importModule = QuestieLoader.ImportModule
QuestieLoader.ImportModule = function(self, name)
	if name == "Townsfolk" then return TOWNSFOLK end
	return importModule(self, name)
end
-- Pierre de foyer prête, liée à Orgrimmar (coordonnées « monde » converties par C_Map).
function GetItemCount(id) return id == 6948 and 1 or 0 end
function GetItemCooldown() return 0, 0 end
function GetBindLocation() return BIND_NAME end
BIND_NAME, BIND_MAP, BIND_X, BIND_Y = "Orgrimmar", 1454, 0.54, 0.68
ShortestPathForeverCharDB = { bind = { map = 1, x = 123, y = 456, name = "x" } }
function CreateVector2D(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
C_Map.GetMapPosFromWorldPos = function() return BIND_MAP, CreateVector2D(BIND_X, BIND_Y) end
IS_TRADESKILL = false
function IsTradeskillTrainer() return IS_TRADESKILL end

PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.53, 0.32 -- la Croisée
local ns = LoadAddon(ADDON_DIR, { "Solver.lua", "Geo.lua", "Data.lua", "Planner.lua", "Guide.lua", "UI.lua", "Options.lua", "Group.lua", "Core.lua" })
Fire("ADDON_LOADED", "Itineraire")
Fire("PLAYER_LOGIN")
Advance(5)

local function Show(label)
	print("==== " .. label)
	for k, s in ipairs(ns.plan.order) do
		print(string.format("%2d. [%s] %s  |  %s  (trajet %d s)%s", k, s.kind, s.title, s.subtitle or "", math.floor(s.leg),
			s.hearth and "  << pierre de foyer" or ""))
	end
end
local function Pos(pred)
	for k, s in ipairs(ns.plan.order) do
		if pred(s) then return k, s end
	end
end
Show("niveau 18, maître vu au niveau 16")

-- 1. Maître de classe : le plus pratique (Croisée), icône « trainer » pour la flèche.
local k, trainer = Pos(function(s) return s.kind == "service" and s.service.kind == "trainer" end)
assert(trainer, "pas de visite au maître de classe")
assert(trainer.npcName == "Sorek", "mauvais maître : " .. tostring(trainer.npcName))
local sent
for _, stop in ipairs(SP_ROUTES[#SP_ROUTES]) do
	if stop.title == trainer.title then sent = stop end
end
assert(sent and sent.kind == "trainer", "icône maître non envoyée")

-- 2. Donjon : « Chamans du Gouffre » à prendre chez Migi avant d'entrer.
local pick, p = Pos(function(s) return s.kind == "pickup" and s.candidate and s.candidate.id == 3001 end)
assert(pick, "quête de donjon non proposée")
assert(p.candidate.prepFor, "pas marquée « pour le donjon »")
local dungeon, d = Pos(function(s) return s.kind == "dungeon" and s.questSet[3001] end)
assert(dungeon and dungeon > pick, "prise après le donjon (ou quête pas dans l'étape du donjon)")
assert(d.questSet[5725], "les deux quêtes de donjon doivent être dans la même étape")
assert(p.candidate.objectives[1].numRequired == 6, "quantité lue : " .. tostring(p.candidate.objectives[1].numRequired))

-- 3. Pierre de foyer liée à Orgrimmar : utile pour revenir au donjon / à Migi ?
print("pierre de foyer :", ns.plan.hearth and ("étape " .. ns.plan.hearth.step .. ", gain " .. math.floor(ns.plan.hearth.gain) .. " s") or "aucune")
print("auberge conseillée :", ns.plan.bindAdvice and (ns.plan.bindAdvice.name .. " (+" .. math.floor(ns.plan.bindAdvice.gain) .. " s)") or "aucune")
if ns.plan.hearth then
	local s = ns.plan.order[ns.plan.hearth.step]
	assert(s.hearth and s.leg < 200, "étape pierre de foyer incohérente")
end

-- Liée très loin (Pitons-du-Tonnerre) : l'auberge d'Orgrimmar ou de la Croisée est conseillée.
BIND_NAME, BIND_MAP, BIND_X, BIND_Y = "Les Pitons-du-Tonnerre", 1456, 0.5, 0.5
ns.RequestPlan("t", 0)
Advance(5)
Show("liée aux Pitons-du-Tonnerre")
assert(ns.plan.bindAdvice, "pas de conseil d'auberge alors que la pierre est liée trop loin")
print("auberge conseillée :", ns.plan.bindAdvice.name, ns.plan.bindAdvice.zone, math.floor(ns.plan.bindAdvice.gain))

-- 4. Visite faite (fenêtre du maître de classe ouverte) : l'étape disparaît.
Fire("TRAINER_SHOW")
Advance(5)
assert(ns.char.trainedAt == 18, "niveau de visite non retenu")
assert(not Pos(function(s) return s.kind == "service" and s.service.kind == "trainer" end), "visite encore proposée")
-- Un maître de MÉTIER ne compte pas.
ns.char.trainedAt = 16
IS_TRADESKILL = true
Fire("TRAINER_SHOW")
Advance(5)
assert(ns.char.trainedAt == 16, "un maître de métier ne doit pas valider la visite")
print("OK extras")
