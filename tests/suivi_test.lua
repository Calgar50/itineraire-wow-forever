-- Suivi des quêtes (3.2.1).
-- 1. Objet déjà dans les sacs que le journal du jeu ne compte pas (vu sur Forever : « Journal de Khazgorm : 0/1 » avec
--    le journal dans les sacs) : pas renvoyé le chercher, une seule annonce, confiance au jeu après 20 min.
-- 2. Filons : jamais l'argent (ses emplacements sont presque toujours vides), pause de 10 min après un coin, et le même
--    coin gardé d'un calcul à l'autre.
dofile(TESTS .. "/wow_mock.lua")
SKEW = 0
local baseGetTime = GetTime
GetTime = function() return baseGetTime() + SKEW end
NOW = 1800000000
time = function() return NOW end
date = function(fmt, t) return os.date(fmt, t or NOW) end
function UnitLevel() return 25 end
function UnitClass() return "Guerrier", "WARRIOR" end
C_QuestLog.GetMaxNumQuestsCanAccept = function() return 25 end

NPCS[9] = { id = 9, name = "Gann", spawns = { [17] = { { 52.2, 31.0 } } }, friendly = true }
NPCS[700] = { id = 700, name = "Khazgorm", spawns = { [17] = { { 47.0, 85.0 } } } }
NPCS[701] = { id = 701, name = "Zhévra", spawns = { [17] = { { 53.0, 33.0 }, { 53.2, 33.1 } } } }
QUESTS[843] = { Id = 843, name = "La réclamation de Gann", level = 23, xp = 1500, Finisher = { NPC = { 9 } },
	ObjectiveData = { { Type = "item", Id = 5006 } },
	Objectives = { { spawnList = { [700] = { Id = 700, Name = "Khazgorm", Spawns = NPCS[700].spawns, Hostile = true } } } } }
QUESTS[900] = { Id = 900, name = "Zhévras", level = 24, xp = 1200, Finisher = { NPC = { 9 } },
	ObjectiveData = { { Type = "monster", Id = 701 } },
	Objectives = { { spawnList = { [701] = { Id = 701, Name = "Zhévra", Spawns = NPCS[701].spawns, Hostile = true } } } } }
local function journal(have)
	LOG[1] = { info = { questID = 843, title = "La réclamation de Gann", level = 23, suggestedGroup = 0 },
		objectives = { { text = "Journal de Khazgorm : " .. have .. "/1", type = "item", finished = have >= 1,
			numFulfilled = have, numRequired = 1 } }, complete = have >= 1 }
end
journal(0)
LOG[2] = { info = { questID = 900, title = "Zhévras", level = 24, suggestedGroup = 0 },
	objectives = { { text = "Zhévra tué : 2/8", type = "monster", finished = false, numFulfilled = 2, numRequired = 8 } },
	complete = false }

-- Les sacs : le journal est là (le jeu ne l'a pas compté)
BAG = { [5006] = 1 }
C_Item = {
	GetItemCount = function(id) return BAG[id] or 0 end,
	GetItemNameByID = function(id) return id == 5006 and "Journal de Khazgorm" or nil end,
}

-- Minage 80/150 : étain orange, argent orange (mais rare), cuivre vert.
function GetProfessions() return 1, nil, nil, nil, nil end
function GetProfessionInfo(i)
	if i == 1 then return "Minage", "icon", 80, 150, 0, 0, 186 end
end
OBJECTS[1733] = { name = "Silver Vein", spawns = { [17] = { { 52.45, 31.2 }, { 52.5, 31.25 }, { 52.47, 31.22 } } } }
OBJECTS[1732] = { name = "Tin Vein", spawns = { [17] = { { 52.7, 31.9 }, { 52.75, 31.95 } } } }

PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.52, 0.31
local ns = LoadAddon(ADDON_DIR, { "Solver.lua", "Geo.lua", "Data.lua", "Planner.lua", "Guide.lua", "UI.lua", "Options.lua",
	"Group.lua", "Gear.lua", "GearUI.lua", "Pilote.lua", "Autonomie.lua", "Montee.lua", "MonteeUI.lua", "Controle.lua",
	"Tri.lua", "Sacs.lua", "Core.lua" })
Fire("ADDON_LOADED", "Itineraire")
Fire("PLAYER_LOGIN")
Advance(5)

local function Show(tag)
	print("--- " .. tag)
	for k, s in ipairs(ns.plan.order) do
		print(k, s.kind, s.key, s.title)
	end
end
local function Has(pattern)
	for k, s in ipairs(ns.plan.order) do
		if tostring(s.key):find(pattern) then
			return k, s
		end
	end
end
local function Told(pattern)
	local n = 0
	for _, m in ipairs(PRINTED) do
		if tostring(m):find(pattern) then
			n = n + 1
		end
	end
	return n
end

-- 1. Le journal est dans les sacs : pas d'étape « Khazgorm », le rendu chez Gann, une annonce
Show("journal dans les sacs")
for _, s in ipairs(ns.plan.order) do
	for _, t in ipairs(s.tasks or {}) do
		assert(not (t.q.id == 843 and t.index), "renvoyé chercher le journal déjà dans les sacs : " .. tostring(s.title))
	end
end
local kT = Has("^T:.*843")
assert(kT, "pas de rendu pour la quête dont l'objet est dans les sacs")
assert(Told("Journal de Khazgorm est dans tes sacs") == 1, "annonce absente")
assert(ns.plan.inBags and ns.plan.inBags[1].key == "843:5006", "plan.inBags")
ns.RequestPlan("t", 0)
Advance(3)
assert(Told("Journal de Khazgorm est dans tes sacs") == 1, "annonce répétée")
assert(ns.ReportText():find("pas compté par le jeu"), "rapport sans la ligne")

-- 20 min plus tard, toujours 0/1 : le jeu a raison, retour à l'objectif
NOW = NOW + 1201
ns.RequestPlan("t", 0)
Advance(3)
Show("20 min plus tard")
local back = false
for _, s in ipairs(ns.plan.order) do
	for _, t in ipairs(s.tasks or {}) do
		back = back or (t.q.id == 843 and t.index == 1)
	end
end
assert(back, "toujours pas renvoyé chercher l'objet après 20 min")
assert(Told("refait confiance au jeu") == 1, "pas d'annonce après 20 min")

-- le jeu le compte enfin : plus rien de retenu
journal(1)
ns.RequestPlan("t", 0)
Advance(3)
assert(not next(ns.char.inBags), "souvenir gardé alors que le jeu compte l'objet")

-- même nom mais pas assez d'exemplaires : rien
journal(0)
BAG[5006] = 0
ns.RequestPlan("t", 0)
Advance(3)
assert(not ns.plan.inBags, "objet absent des sacs compté quand même")
BAG[5006] = 1

-- 2. Filons : l'étain, jamais l'argent
local kMine, mine = Has("^S:mine:")
Show("filons")
assert(mine, "pas de filon sur le trajet")
assert(mine.key:find("etain"), "filon : " .. mine.key)
assert(not Has("^S:mine:argent"), "filon d'argent proposé")
-- le même coin d'un calcul à l'autre
ns.RequestPlan("t", 0)
Advance(3)
assert(select(2, Has("^S:mine:")) and select(2, Has("^S:mine:")).key == mine.key, "le coin à filons a changé")
-- arrivé (le coin en 1re étape, comme par un clic gauche) : validé, puis plus de détour de minage pendant 10 min
ns.session.pinned = mine.key
ns.RequestPlan("t", 0)
Advance(3)
assert(ns.plan.order[1].key == mine.key, "coin pas en tête")
PLAYER.x, PLAYER.y = mine.x, mine.y
Advance(10)
assert(not Has("^S:mine:"), "un autre filon tout de suite après")
SKEW = 400 -- (horloge du jeu avancée sans faire tourner 400 s de minuteurs)
ns.RequestPlan("t", 0)
Advance(3)
assert(not Has("^S:mine:"), "filon avant la fin de la pause")
SKEW = 700
ns.RequestPlan("t", 0)
Advance(3)
-- (le coin visité reste passé pour la session ; un autre peut revenir, aucun ici)
assert(not Has(mine.key:gsub("%p", "%%%0")), "coin visité revenu")
-- « réafficher » : tout revient, pause comprise
ns.ResetChoices()
Advance(3)
assert(Has("^S:mine:etain"), "filon pas revenu après « réafficher »")
print("OK suivi")
