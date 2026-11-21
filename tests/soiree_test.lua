-- Soirée planifiée (3.0.0) : le temps que tu as, les quêtes qui rapportent le plus d'XP, une auberge à la fin, le
-- reste du journal après (aucune quête écartée) ; l'heure passée : l'auberge d'abord (pierre de foyer si prête) ;
-- arrivé à l'auberge : bilan et fin de la soirée.
dofile(TESTS .. "/scenario_setup.lua")
NOW = 1800000000
date = function(fmt, t) return os.date(fmt, t or NOW) end
time = function(t)
	if type(t) == "table" then
		return os.time(t)
	end
	return NOW
end
function UnitLevel() return 16 end
function UnitXP() return 3000 end
function UnitXPMax() return 16000 end
function UnitClass() return "Guerrier", "WARRIOR" end
C_QuestLog.GetMaxNumQuestsCanAccept = function() return 25 end

NPCS[802] = { id = 802, name = "Aubergiste d'Orgrimmar", spawns = { [1637] = { { 54, 68 } } }, friendly = true }
NPCS[803] = { id = 803, name = "Aubergiste de Camp Taurajo", spawns = { [17] = { { 45, 58 } } }, friendly = true }
TOWNSFOLK = { townsfolk = { Innkeeper = { 802, 803 }, Repair = {} }, classSpecificTownsfolk = {} }
local importModule = QuestieLoader.ImportModule
QuestieLoader.ImportModule = function(self, name)
	if name == "Townsfolk" then return TOWNSFOLK end
	return importModule(self, name)
end
HEARTH = 0
function GetItemCount(id) return id == 6948 and HEARTH or 0 end
function GetItemCooldown() return 0, 0 end
function GetBindLocation() return "Orgrimmar" end
ShortestPathForeverCharDB = { bind = { map = 1, x = 123, y = 456, name = "Orgrimmar" } }
function CreateVector2D(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
C_Map.GetMapPosFromWorldPos = function() return 1454, CreateVector2D(0.54, 0.68) end

PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.52, 0.31 -- la Croisée
local ns = LoadAddon(ADDON_DIR, { "Solver.lua", "Geo.lua", "Data.lua", "Planner.lua", "Guide.lua", "UI.lua", "Options.lua",
	"Group.lua", "Montee.lua", "MonteeUI.lua", "Controle.lua", "Core.lua" })
Fire("ADDON_LOADED", "Itineraire")
Fire("PLAYER_LOGIN")
Advance(5)

local function Show(label)
	print("==== " .. label)
	for k, s in ipairs(ns.plan.order) do
		print(string.format("%2d. [%s] tier %s %s%s | eta %d", k, s.kind, tostring(s.tier), s.title,
			s.afterSoiree and "  (après la soirée)" or "", math.floor(s.eta or 0)))
	end
	for _, w in ipairs(ns.plan.warnings or {}) do
		print("AVERTISSEMENT : " .. tostring(w))
	end
end
local function QuestIds(plan)
	local ids = {}
	for _, s in ipairs(plan.order) do
		for _, q in ipairs(s.quests) do
			if not q.candidate then
				ids[q.id] = true
			end
		end
	end
	return ids
end
local function Printed(pattern)
	for _, m in ipairs(PRINTED) do
		if tostring(m):find(pattern) then
			return true
		end
	end
	return false
end

-- 1. Les durées et les heures comprises
assert(ns.ParseSoiree("1h30") == 90 and ns.ParseSoiree("45") == 45 and ns.ParseSoiree("2h") == 120
	and ns.ParseSoiree("45min") == 45, "durées")
local m, at = ns.ParseSoiree("23h")
assert(not m and at and at > NOW and at <= NOW + 86400, "jusqu'à 23 h")
m, at = ns.ParseSoiree("22:30")
assert(not m and at and os.date("%H:%M", at) == "22:30", "jusqu'à 22:30")
m, at = ns.ParseSoiree("à 23h")
assert(at and os.date("%H", at) == "23", "« à 23h »")
assert(ns.ParseSoiree("bla") == nil and ns.ParseSoiree("25h") == nil, "texte refusé")

local full = ns.plan
Show("trajet complet")
local fullIds = QuestIds(full)
assert(not full.soiree, "pas de soirée sans la demander")

-- 2. Une soirée de 30 min
ns.SoireeStart(30)
Advance(5)
local plan = ns.plan
Show("soirée de 30 min")
assert(plan.soiree, "soirée non appliquée : " .. tostring(plan.warnings and plan.warnings[1]))
local innK, inn
for k, s in ipairs(plan.order) do
	if s.kind == "service" and s.service.kind == "inn" then
		innK, inn = k, s
	end
end
assert(innK and plan.soiree.innStep == innK, "pas d'auberge de fin de soirée")
assert(inn.title:find("Fin de soirée"), inn.title)
for k, s in ipairs(plan.order) do
	if k < innK then
		assert(not s.afterSoiree and s.tier < 0.6, "étape " .. k .. " avant l'auberge mais pas de la soirée")
	elseif k > innK then
		assert(s.afterSoiree, "étape " .. k .. " après l'auberge sans la marque « après la soirée »")
	end
end
assert(plan.soiree.chosen >= 1 and plan.soiree.afterCount >= 1, "30 min : une partie seulement du journal")
assert(plan.soiree.endEta <= 30 * 60 * 1.1 + 60 + 300, "auberge trop tard : " .. plan.soiree.endEta)
-- aucune quête du journal écartée
local ids = QuestIds(plan)
for id in pairs(fullIds) do
	assert(ids[id], "quête " .. id .. " écartée par la soirée")
end
-- les quêtes gardées ont un meilleur rendement que celles d'après (en moyenne)
print(string.format("soirée : %d quête(s), auberge étape %d (eta %d s), niveau %.2f, %d étape(s) après",
	plan.soiree.chosen, innK, plan.soiree.endEta, plan.soiree.levelEnd, plan.soiree.afterCount))
-- fenêtre : résumé, bouton allumé, onglet soirée
ns.UI.Refresh(plan)
local summaryOK = false
for _, f in ipairs(FONTS) do
	if tostring(f.text):find("Soirée") and tostring(f.text):find("auberge à l'étape") then
		summaryOK = true
	end
end
assert(summaryOK, "résumé de la soirée absent")
ns.MonteeUI.Toggle(true, "soiree")
local lines = ns.MonteeUI.SoireeLines()
assert(table.concat(lines, "\n"):find("Soirée en cours"), "onglet soirée")
ns.MonteeUI.Toggle(false)
-- rapport
assert(ns.ReportText():find("Soirée : jusqu'à"), "ligne soirée du rapport")

-- 3. Une quête rendue compte dans le bilan
Fire("QUEST_TURNED_IN", 819)
assert(ns.char.soiree.rendues == 1, "quête rendue non comptée")

-- 4. L'heure est passée, pierre de foyer prête : l'auberge d'abord, par la pierre de foyer
HEARTH = 1
NOW = ns.char.soiree.fin + 30
Advance(6)
Advance(3)
plan = ns.plan
Show("heure passée, pierre de foyer prête")
assert(Printed("c'est l'heure"), "pas de message « c'est l'heure »")
local first = plan.order[1]
assert(first.kind == "service" and first.service.kind == "inn", "l'auberge n'est pas l'étape 1 : " .. tostring(first.title))
assert(first.service.hearth and first.leg <= 15 and first.title:find("pierre de foyer"), "pierre de foyer non utilisée")
ids = QuestIds(plan)
for id in pairs(fullIds) do
	assert(ids[id], "quête " .. id .. " écartée (heure passée)")
end

-- 5. Arrivé à l'auberge : bilan, fin de la soirée, trajet complet
PLAYER.map, PLAYER.x, PLAYER.y = first.map, first.x, first.y
Advance(4)
assert(not ns.char.soiree, "soirée pas finie à l'auberge")
assert(Printed("fin de soirée"), "pas de bilan")
Advance(3)
assert(not ns.plan.soiree, "trajet encore en mode soirée")
for _, s in ipairs(ns.plan.order) do
	assert(not (s.kind == "service" and s.service.kind == "inn"), "auberge encore au trajet")
end

-- 6. Arrêt à la main et soirée oubliée longtemps après
ns.SoireeStart(60)
Advance(3)
assert(ns.plan.soiree, "2e soirée")
ns.SoireeStop("test")
Advance(3)
assert(not ns.char.soiree and not ns.plan.soiree, "arrêt")
ns.SoireeStart(45)
NOW = NOW + 45 * 60 + 1801
assert(ns.SoireeActive() == nil and ns.char.soiree == nil, "soirée finie depuis longtemps pas oubliée")
print("OK soirée")
