-- Ma montée (3.0.0) : index des quêtes par zone, frise jusqu'au 60, région suivante quand le journal se vide, filons
-- de minage à deux pas du trajet, plan de forge, contrôle en jeu.
dofile(TESTS .. "/wow_mock.lua")
NOW = 1800000000
time = function(t)
	if type(t) == "table" then
		return os.time(t)
	end
	return NOW
end
date = function(fmt, t) return os.date(fmt, t or NOW) end
LEVEL = 20
function UnitLevel() return LEVEL end
function UnitClass() return "Guerrier", "WARRIOR" end
C_QuestLog.GetMaxNumQuestsCanAccept = function() return 25 end
MAPS[1443] = { name = "Désolace", ox = -12000, oy = 0, s = 8000, inst = 1 }
AREA_TO_MAP[405] = 1443

-- Base Questie : les champs lus un par un (QueryQuestSingle) et la liste de toutes les quêtes.
local DB = QuestieLoader:ImportModule("QuestieDB")
DB.QuestPointers = {}
local FIELDS = { questLevel = "level", requiredLevel = "requiredLevel", zoneOrSort = "zone", specialFlags = "specialFlags",
	requiredRaces = "requiredRaces", requiredClasses = "requiredClasses", requiredSkill = "requiredSkill" }
DB.QueryQuestSingle = function(id, field)
	local q = QUESTS[id]
	return q and FIELDS[field] and q[FIELDS[field]] or nil
end

local function npc(id, name, area, pts)
	NPCS[id] = { id = id, name = name, spawns = { [area] = pts }, friendly = true }
end
npc(9, "Sergra", 17, { { 52.2, 31.0 } })
npc(601, "Donneur des Serres", 406, { { 47, 61 } })
npc(602, "Autre donneur des Serres", 406, { { 47.3, 61.2 } })
npc(603, "Donneur des Tarides", 17, { { 51, 30 } })
npc(604, "Donneur de Désolace", 405, { { 50, 50 } })
local function base(id, name, zone, level, req, starter, xp, available)
	QUESTS[id] = { Id = id, name = name, level = level, requiredLevel = req, zone = zone, xp = xp or level * 70,
		Starts = { NPC = { starter } }, Finisher = { NPC = { starter } } }
	DB.QuestPointers[id] = true
	if available then
		AVAILABLE[id] = true
	end
end
-- Tarides (10-25) : peu de quêtes encore à prendre à ce niveau.
base(1001, "Tarides 1", 17, 19, 15, 603, nil, true)
base(1002, "Tarides 2", 17, 20, 16, 603, nil, true)
for i = 0, 5 do
	base(1010 + i, "Tarides haute " .. i, 17, 23 + i % 3, 20 + i % 3, 603)
end
-- Serres-Rocheuses (15-27) : 7 quêtes de ton niveau à prendre.
for i = 0, 6 do
	base(2000 + i, "Serres " .. i, 406, 19 + i % 3, 16, i % 2 == 0 and 601 or 602, nil, true)
end
for i = 0, 4 do
	base(2010 + i, "Serres haute " .. i, 406, 24 + i % 3, 21, 601)
end
-- Désolace (30-40) : pour plus tard.
for i = 0, 9 do
	base(3000 + i, "Désolace " .. i, 405, 30 + i % 6, 27 + i % 4, 604)
end
-- Durotar : grises à ton niveau ; une quête répétable et une de métier, jamais comptées.
for i = 0, 3 do
	base(4000 + i, "Durotar " .. i, 14, 4 + i, 1, 603)
end
base(4100, "Répétable", 406, 20, 15, 601, nil, true)
QUESTS[4100].specialFlags = 1
base(4101, "Métier", 406, 20, 15, 601, nil, true)
QUESTS[4101].requiredSkill = { 186, 50 }

-- Journal presque vide : une quête terminée à rendre à la Croisée.
LOG[1] = { info = { questID = 1500, title = "À rendre", level = 20, suggestedGroup = 0 }, objectives = {}, complete = true }
QUESTS[1500] = { Id = 1500, name = "À rendre", level = 20, xp = 1400, Finisher = { NPC = { 9 } } }

-- Métiers : minage 70/150 (étain orange, cuivre vert), forge 30/75.
function GetProfessions() return 1, 2, nil, nil, nil end
function GetProfessionInfo(i)
	if i == 1 then return "Minage", "icon", 70, 150, 0, 0, 186 end
	if i == 2 then return "Forge", "icon", 30, 75, 0, 0, 164 end
end
OBJECTS[1732] = { name = "Tin Vein", spawns = { [17] = { { 52.6, 31.4 }, { 52.7, 31.5 }, { 52.65, 31.45 } } } }
OBJECTS[1731] = { name = "Copper Vein", spawns = { [17] = { { 51.5, 30.5 }, { 51.6, 30.6 } } } }
OBJECTS[2040] = { name = "Mithril Deposit", spawns = { [17] = { { 52.5, 31.2 }, { 52.55, 31.25 } } } }

PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.52, 0.31
local ns = LoadAddon(ADDON_DIR, { "Solver.lua", "Geo.lua", "Data.lua", "Planner.lua", "Guide.lua", "UI.lua", "Options.lua",
	"Group.lua", "Gear.lua", "GearUI.lua", "Pilote.lua", "Autonomie.lua", "Montee.lua", "MonteeUI.lua", "Controle.lua",
	"Core.lua" })
ns.ext = ns.ext or {}
ns.ext.RECETTES = {
	[2663] = { 164, 0, "t", 0, 2853, 1, "2840:2", 4, 3, "", "", 2 },
	[2737] = { 164, 15, "t", 0, 2844, 1, "2840:6,2880:1,2589:2", 2, 4, "", "", 4 },
	[3115] = { 164, 0, "t", 0, 3239, 1, "2835:1", 7, 0, "", "", 1 },
	[2664] = { 164, 65, "t", 0, 2854, 1, "2840:10,3470:3", 4, 3, "", "", 14 },
	[2657] = { 186, 0, "t", 0, 2840, 1, "2770:1", 7, 7, "", "", 0 },
}
Fire("ADDON_LOADED", "Itineraire")
Fire("PLAYER_LOGIN")
Advance(5)
local M = ns.Montee

local function Show(label)
	print("==== " .. label)
	for k, s in ipairs(ns.plan.order) do
		print(string.format("%2d. [%s] tier %s %s | %s", k, s.kind, tostring(s.tier), s.title, s.subtitle or ""))
	end
	for _, w in ipairs(ns.plan.warnings or {}) do
		print("AVERTISSEMENT : " .. tostring(w))
	end
end
local function Find(kind)
	for k, s in ipairs(ns.plan.order) do
		if s.kind == "service" and s.service.kind == kind then
			return k, s
		end
	end
end

-- 1-2. L'index se construit en tâche de fond dès que le trajet en a besoin (ou 20 s après la connexion), puis le
-- trajet est recalculé
Show("au démarrage")
Advance(30)
local state, count, zones = M.IndexState()
print("index :", state, count, zones)
assert(state == "prêt", "index pas prêt : " .. tostring(state))
local index = ns.Data.QuestIndex()
assert(index.zones[1413] and index.zones[1442] and index.zones[1443] and index.zones[1411], "zones manquantes")
for _, list in pairs(index.zones) do
	for _, e in ipairs(list) do
		assert(e.id ~= 4100 and e.id ~= 4101, "quête répétable ou de métier indexée")
	end
end
assert(#index.zones[1442] == 12, "Serres : " .. #index.zones[1442])

-- 3. Région suivante : journal presque vide, Tarides presque finies -> les Serres-Rocheuses
Advance(5)
Show("journal presque vide")
local kRegion, region = Find("region")
assert(region, "pas de région suivante")
assert(region.title:find("Serres"), "mauvaise région : " .. region.title)
assert(region.map == 1442, "point de rassemblement hors de la zone")
local kTurn
for k, s in ipairs(ns.plan.order) do
	if s.kind == "turnin" and s.questSet[1500] then
		kTurn = k
	end
end
assert(kTurn and kTurn < kRegion, "le journal d'abord, la région suivante ensuite")
assert(ns.UI and true)
-- passée : plus proposée pour la session
ns.SkipStop(region.key)
Advance(3)
assert(not Find("region"), "région suivante passée mais encore là")
ns.ResetChoices()
Advance(3)
assert(Find("region"), "région suivante pas revenue après « réafficher »")

-- 4. Filons : étain (orange à 70) près du trajet ; cuivre (vert) et mithril (pas encore) ignorés
local kMine, mine = Find("mine")
assert(mine, "pas de filon sur le trajet")
assert(mine.title:find("étain") and mine.title:find("orange"), mine.title)
for _, s in ipairs(ns.plan.order) do
	if s.kind == "service" and s.service.kind == "mine" then
		assert(not s.title:find("cuivre") and not s.title:find("mithril"), "filon inutile proposé : " .. s.title)
	end
end
assert(M.OreColor(1, 70) == "vert" and M.OreColor(65, 70) == "orange" and M.OreColor(175, 70) == nil
	and M.OreColor(65, 120) == "vert" and M.OreColor(65, 170) == "gris" and M.OreColor(125, 160) == "jaune", "couleurs")
-- arrivé sur place : validé après quelques secondes
PLAYER.map, PLAYER.x, PLAYER.y = mine.map, mine.x, mine.y
Advance(10)
assert(not Find("mine") or Find("mine") ~= kMine or select(2, Find("mine")).key ~= mine.key, "filon pas validé en arrivant")
for _, s in ipairs(ns.plan.order) do
	assert(s.key ~= mine.key, "filon encore au trajet après y être passé")
end
-- option coupée : plus de filons
PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.52, 0.31
ns.ResetChoices()
Advance(3)
assert(Find("mine"), "filon pas revenu")
ns.db.includeMining = false
ns.RequestPlan("t", 0)
Advance(3)
assert(not Find("mine"), "filons malgré l'option coupée")
ns.db.includeMining = true

-- 5. Frise jusqu'au 60
local frise = M.Frise()
assert(frise and #frise.rows >= 2, "frise vide")
for i, row in ipairs(frise.rows) do
	print(string.format("frise %d : %.2f -> %.2f %s (%d quêtes, %d XP)", i, row.from, row.to, row.name, row.quests, row.xp))
	assert(row.to >= row.from, "frise à l'envers")
	if i > 1 then
		assert(row.from >= frise.rows[i - 1].to - 0.001, "frise pas dans l'ordre")
	end
end
assert(frise.rows[1].zone == 1413 or frise.rows[1].zone == 1442, "1re zone : " .. tostring(frise.rows[1].name))
local deso
for _, row in ipairs(frise.rows) do
	if row.zone == 1443 then
		deso = row
	end
	assert(row.zone ~= 1411, "Durotar (gris) dans la frise")
end
assert(deso and deso.from >= 26, "Désolace pas au bon moment")
local text = table.concat(M.FriseLines(), "\n")
assert(text:find("Désolace") and text:find("Estimation"), "texte de la frise")

-- 6. Forge 30/75 : orange d'abord, puis les jaunes les moins chères ; la recette au-dessus de ta compétence, non
local recipes = M.ForgeRecipes()
local ids = {}
for i, r in ipairs(recipes) do
	ids[i] = r.spell .. ":" .. r.color
end
print("forge :", table.concat(ids, " "))
assert(#recipes == 3 and recipes[1].spell == 2737 and recipes[1].color == "orange", "ordre des recettes")
assert(recipes[2].spell == 3115 and recipes[3].spell == 2663, "jaunes par coût")
-- couleur lue dans la fenêtre de forge (exacte) et recette connue : en tête
ns.Gear.Config().recipes[2663] = true
ns.Gear.Config().recipeDiff = { [2663] = 0 }
recipes = M.ForgeRecipes()
assert(recipes[1].spell == 2663 and recipes[1].exact and recipes[1].color == "orange", "recette connue, couleur exacte")
local craft = table.concat(M.CraftLines(), "\n")
print(craft)
assert(craft:find("Minage : 70/150") and craft:find("Forge : 30/75") and craft:find("étain"), "onglet minage et forge")

-- 7. La fenêtre « Ma montée » : les trois onglets s'affichent sans erreur
for _, tab in ipairs({ "frise", "soiree", "metiers" }) do
	ns.MonteeUI.Toggle(true, tab)
	assert(ns.MonteeUI.Shown(), "fenêtre fermée : " .. tab)
end
ns.MonteeUI.Toggle(false)
assert(not ns.MonteeUI.Shown(), "fenêtre pas fermée")

-- 8. Contrôle en jeu : tout passe, rien ne plante
local report, counts = ns.Controle.Run()
print(report:sub(1, 2500))
assert(not report:find("erreur Lua"), "un contrôle a planté")
assert(counts.ok >= 8, "trop peu de contrôles OK : " .. counts.ok)
assert(report:find("Base de quêtes") and report:find("Métiers") and report:find("=== Rapport Itinéraire"), "compte rendu incomplet")
ns.Controle.Show()

-- 9. Commandes
SlashCmdList.ITINERAIRE("montee")
assert(ns.MonteeUI.Shown(), "/iti montee")
SlashCmdList.ITINERAIRE("controle")
SlashCmdList.ITINERAIRE("soiree 1h")
assert(ns.char.soiree and ns.char.soiree.minutes == 60, "/iti soiree 1h")
SlashCmdList.ITINERAIRE("soiree stop")
assert(not ns.char.soiree, "/iti soiree stop")
print("OK montée")
