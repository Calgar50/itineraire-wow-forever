-- Moteur interne (3.3.0) sur la VRAIE base QuestieDB de Forever, sans Questie : un tauren guerrier niveau 26 aux
-- Tarides. Lancer avec tests/run_lua_vraie.py. `VRAI_COMPLETES` (facultatif, posé par un test enveloppe hors du
-- dépôt) = quêtes déjà faites d'un vrai personnage ; sinon une petite liste publique.
dofile(TESTS .. "/wow_mock.lua")
dofile(TESTS .. "/vraie_questiedb.lua")
local LQ = ChargerVraieQuestieDB(QUESTIEDB)
if not LQ then
	print("SKIP vraie base absente")
	return
end
local hbd = QuestieLoader:ImportModule("HBD")
Questie, QuestieLoader = nil, nil -- pas de Questie
CreateVector2D = function(x, y) return { x = x, y = y } end
C_Map.GetWorldPosFromMapPos = function(map, v)
	local wx, wy, inst = hbd:GetWorldCoordinatesFromZone(v.x, v.y, map)
	if not wx then return nil end
	return inst, { GetXY = function() return wy, wx end }
end
NOW = 1800000000
time = function() return NOW end
date = function(fmt, t) return os.date(fmt, t or NOW) end
LEVEL = 26
function UnitLevel() return LEVEL end
function UnitClass() return "Guerrier", "WARRIOR", 1 end
function GetMaxPlayerLevel() return 60 end
function GetQuestGreenRange() return 9 end -- (niveau 26 en Classic : vertes jusqu'à 9 niveaux en dessous)
C_QuestLog.GetMaxNumQuestsCanAccept = function() return 25 end
local done = VRAI_COMPLETES or { 844, 845, 871, 869, 872, 5041, 819, 821, 870, 877, 848, 853, 962, 1492, 896, 895, 887,
	890, 892, 888, 891, 894, 900, 901, 902, 881, 3921, 1130, 1131, 1483, 429, 264, 430, 452, 516, 477, 478, 481, 482,
	479, 1098, 1013, 1014, 421, 422, 480, 235, 3281, 867, 865, 878, 5052, 5046, 5043, 1486, 1487 }
local doneList = {}
for k, v in pairs(done) do
	doneList[#doneList + 1] = type(k) == "number" and v == true and k or v
end
C_QuestLog.GetAllCompletedQuestIDs = function() return doneList end
function GetProfessions() return 1, 2, nil, nil, nil end
function GetProfessionInfo(i)
	if i == 1 then return "Minage", "icon", 95, 150, 0, 0, 186 end
	if i == 2 then return "Forge", "icon", 57, 150, 0, 0, 164 end
end
-- Journal : la réclamation de Gann (843) en cours
LOG[1] = { info = { questID = 843, title = "La réclamation de Gann", level = 23, suggestedGroup = 0 },
	objectives = {
		{ text = "Ouvrier de Bael'dun tué : 3/10", type = "monster", finished = false, numFulfilled = 3, numRequired = 10 },
		{ text = "Contremaître de Bael'dun tué : 1/3", type = "monster", finished = false, numFulfilled = 1, numRequired = 3 },
		{ text = "Journal de Khazgorm : 0/1", type = "item", finished = false, numFulfilled = 0, numRequired = 1 } },
	complete = false }
PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.46, 0.60

local ns = LoadAddon(ADDON_DIR, { "Donnees/Politique.lua", "Solver.lua", "Geo.lua", "Moteur.lua", "Data.lua",
	"Planner.lua", "Guide.lua", "UI.lua", "Options.lua", "Group.lua", "Gear.lua", "GearUI.lua", "Pilote.lua",
	"Autonomie.lua", "Montee.lua", "MonteeUI.lua", "Controle.lua", "Tri.lua", "Sacs.lua", "Core.lua" })
local t0 = os.clock()
Fire("ADDON_LOADED", "Itineraire")
Fire("PLAYER_LOGIN")
Advance(10)
assert(ns.Data.Engine() == "interne", "moteur : " .. tostring(ns.Data.Engine()))
print(string.format("prêt en %.2f s (processeur) · %s", os.clock() - t0, ns.Moteur.State()))

-- 1. Quêtes disponibles : plausibles, jamais faites / cachées / grises
local avail = ns.Data.AvailableQuests()
local n, barrens = 0, {}
local hidden = ns.ext.CACHEES
local doneSet = {}
for _, id in ipairs(doneList) do doneSet[id] = true end
for id in pairs(avail) do
	n = n + 1
	assert(not doneSet[id], "quête faite proposée : " .. id)
	assert(not hidden[id], "quête cachée proposée : " .. id)
	local q = ns.Data.Quest(id)
	assert(q and q.name, "quête inconnue : " .. id)
	if (q.zoneOrSort == 17) then
		barrens[#barrens + 1] = string.format("%d [%d] %s", id, q.level or 0, q.name)
	end
	local doable = ns.Data.CanTake(id, q)
	assert(doable, "disponible mais pas faisable : " .. id)
end
table.sort(barrens)
print(n .. " quêtes disponibles, dont aux Tarides :")
for _, line in ipairs(barrens) do print("  " .. line) end
assert(n >= 10 and n <= 600, "nombre de quêtes disponibles invraisemblable : " .. n)
assert(not avail[843], "quête du journal proposée")

-- 2. La quête 843 telle que la base la décrit
local q = ns.Data.Quest(843)
assert(q.ObjectiveData[1].Type == "monster" and q.ObjectiveData[3].Type == "item" and q.ObjectiveData[3].Id == 5006,
	"objectifs de 843")
local pts = ns.Data.ObjectivePoints(q, 3)
assert(#pts >= 1 and pts[1].map == 1413, "Khazgorm introuvable")
local fin = ns.Data.FinisherPoints(q)
assert(#fin >= 1 and fin[1].name == "Gann Stonespire" or fin[1].name, "rendu de 843")
print("843 : XP", ns.Data.QuestXP(843), "· rendu chez", fin[1].name)
assert(ns.Data.QuestXP(843) == 1850, "XP de 843 : " .. tostring(ns.Data.QuestXP(843)))

-- 3. Habitants des villes, maîtres, filons, zones
local repair = ns.Data.RepairPoints()
local inns = ns.Data.TownsfolkPoints("Innkeeper")
local innIds, repairIds = ns.Moteur.Townsfolk("Innkeeper"), ns.Moteur.Townsfolk("Repair")
print("réparateurs :", #repairIds, "PNJ,", #repair, "positions · aubergistes :", #innIds, "PNJ,", #inns,
	"positions (cartes connues du faux WoW seulement)")
assert(#repairIds >= 100 and #innIds >= 30 and #repair >= 20 and #inns >= 3, "habitants des villes")
local tin = ns.Data.ObjectPlaces(1732, 4000)
print("filons d'étain (cartes connues du faux WoW) :", #tin)
assert(#tin >= 10, "filons d'étain")
assert(ns.Data.ZoneOfArea(17) == ns.Geo.Zone(1413) or ns.Data.ZoneOfArea(17) == 1413, "zone des Tarides")

-- 4. Index de la frise, région suivante
local index = ns.Data.QuestIndex()
print("index :", index.count, "quêtes")
assert(index.count > 500, "index de la frise")

-- 5. Un trajet complet, sans Questie
ns.RequestPlan("t", 0)
Advance(5)
assert(ns.plan and #ns.plan.order > 0, "pas de trajet")
for k, s in ipairs(ns.plan.order) do
	if k <= 12 then print(k, s.kind, s.title) end
end
print("OK moteur vrai")
