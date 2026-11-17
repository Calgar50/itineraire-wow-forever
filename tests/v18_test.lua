-- v1.8 : rapport à copier, bandeau « prochaine étape », assistant de départ, réglages Questie / Shortest Path,
-- rythme par cible et par zone, fourchettes, chemin détaillé (vol, bateau…).
dofile(TESTS .. "/wow_mock.lua")
time = function() return 1800000000 end

local function npc(id, name, area, pts, level, rank)
	NPCS[id] = { id = id, name = name, spawns = { [area] = pts }, friendly = true, maxLevel = level, rank = rank }
end
npc(9, "Sergra Darkthorn", 17, { { 52.2, 31.0 } })
npc(13, "Gazrog", 17, { { 51.7, 29.9 } })
npc(106, "Zhévra", 17, { { 55, 33 }, { 56, 34 }, { 57, 32 }, { 55.5, 33.5 } }, 12)
npc(107, "Lion des savanes", 17, { { 45, 50 }, { 46, 51 } }, 13)
npc(20, "Thrall", 1637, { { 31.7, 37.8 } })

local function logQuest(id, title, level, objectives)
	LOG[#LOG + 1] = { info = { questID = id, title = title, level = level, suggestedGroup = 0 }, objectives = objectives or {} }
end
logQuest(1001, "Les zhévras", 15, { { text = "Zhévra tué : 0/6", type = "monster", finished = false, numFulfilled = 0, numRequired = 6 } })
QUESTS[1001] = {
	Id = 1001, name = "Les zhévras", level = 15, xp = 900, Finisher = { NPC = { 9 } },
	ObjectiveData = { { Type = "monster", Id = 106 } },
	Objectives = { { spawnList = { [106] = { Id = 106, Name = "Zhévra", Spawns = NPCS[106].spawns, Hostile = true } } } },
}
logQuest(1002, "Les lions", 15, { { text = "Lion des savanes tué : 0/5", type = "monster", finished = false, numFulfilled = 0, numRequired = 5 } })
QUESTS[1002] = {
	Id = 1002, name = "Les lions", level = 15, xp = 900, Finisher = { NPC = { 13 } },
	ObjectiveData = { { Type = "monster", Id = 107 } },
	Objectives = { { spawnList = { [107] = { Id = 107, Name = "Lion des savanes", Spawns = NPCS[107].spawns, Hostile = true } } } },
}
-- une quête à rendre loin (Orgrimmar) : le trajet y va en « vol »
logQuest(1003, "Message pour Thrall", 14, {})
LOG[#LOG].complete = true
QUESTS[1003] = { Id = 1003, name = "Message pour Thrall", level = 14, xp = 500, Finisher = { NPC = { 20 } } }

-- Questie et Shortest Path : leurs réglages
Questie.db = { char = {}, profile = { autocomplete = false, autoAccept = { enabled = false } } }
ShortestPathForeverDB = { journey = true, arrow = true, arrowLabel = "distance", minimapLine = false, mapLine = true, laterLegs = true, useHearthstone = true }
ShortestPathForever.API.EstimateDetail = function(fm, fx, fy, tm, tx, ty)
	local s = ShortestPathForever.API.Estimate(fm, fx, fy, tm, tx, ty)
	return { seconds = s, legs = { { mode = "walk", to = "Point de vol", seconds = 30 }, { mode = "flight", to = "Orgrimmar", seconds = s - 30 } } }
end
-- Journal d'erreurs partagé des addons Forever
local registered = {}
ForeverCore = { Register = function(name, spec)
	registered[name] = spec or true
	return { CaughtErrors = function()
		if name == "ShortestPathForever" then
			return { { kind = "error", message = "Looks.lua:63 boum SP", count = 3, stack = "Looks.lua:63\nRoute.lua:12", fromSession = true } }
		end
		return {}
	end }
end }

PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.515, 0.303
local ns = LoadAddon(ADDON_DIR, { "Solver.lua", "Geo.lua", "Data.lua", "Planner.lua", "Guide.lua", "UI.lua", "Options.lua", "Group.lua", "Core.lua" })
Fire("ADDON_LOADED", "Itineraire")
assert(registered.Itineraire and registered.Itineraire.db == ItineraireDB.forever, "pas inscrit au journal Forever")
Fire("PLAYER_LOGIN")
Advance(6)
assert(ns.plan and #ns.plan.order > 0, "pas de trajet")

local function Plain(t)
	return (tostring(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
local function StopOf(pred)
	for _, s in ipairs(ns.plan.order) do
		if pred(s) then return s end
	end
end

-- 1. Assistant de départ : affiché tout seul la 1re fois, choix conseillés pré-sélectionnés.
local wizard = _G.ItineraireWizard
assert(wizard and wizard.shown, "assistant non affiché au 1er lancement")
local function ClickText(parent, text)
	for _, f in ipairs(FRAMES) do
		if f.shown ~= false and type(rawget(f, "text")) == "string" and Plain(f.text) == text and f.scripts.OnClick then
			f.scripts.OnClick(f)
			return true
		end
	end
	error("bouton introuvable : " .. text)
end
ClickText(wizard, "C'est parti !")
Advance(3)
assert(ns.db.wizardDone == true and not wizard.shown, "assistant non terminé")
assert(ns.db.ui.rows == 3 and ns.db.ui.adviceCollapsed == true and ns.db.ui.banner == true, "fenêtre légère non appliquée")
assert(Questie.db.profile.autocomplete == true, "rendu automatique de Questie non activé")
assert(ShortestPathForeverDB.arrowLabel == "both" and ShortestPathForeverDB.minimapLine == true, "réglages conseillés de Shortest Path non appliqués")
assert(ns.db.regionMode == true and ns.db.groupShare == false, "choix région / solo")
print("OK assistant")
-- pas réaffiché au lancement suivant
wizard:Hide()
Fire("PLAYER_LOGIN")
Advance(6)
assert(not wizard.shown, "assistant réaffiché alors qu'il est fait")

-- 2. Bandeau « prochaine étape »
local banner = _G.ItineraireBanner
assert(banner and banner.shown, "bandeau masqué")
assert(Plain(banner.title.text):find(ns.plan.order[1].title, 1, true), "bandeau : " .. Plain(banner.title.text))
assert(Plain(banner.line.text):find("ensuite :", 1, true), "bandeau sans l'étape suivante : " .. Plain(banner.line.text))
print("bandeau :", Plain(banner.title.text), "|", Plain(banner.line.text))
-- la flèche donne le temps et le moyen de transport
ShortestPathForever.API.Journey = function() return { owner = "Itineraire", secondsLeft = 250, legs = { { mode = "flight", text = "Voler vers Orgrimmar" } } } end
ns.session.previous = ns.plan.order[1].key
ns.UI.UpdateBannerTime()
assert(Plain(banner.line.text):find("Voler vers Orgrimmar", 1, true) and Plain(banner.line.text):find("4 min", 1, true), "temps de la flèche : " .. Plain(banner.line.text))
-- sur place
local first = ns.plan.order[1]
PLAYER.map, PLAYER.x, PLAYER.y = first.map, first.x, first.y
ns.UI.UpdateBannerTime()
assert(Plain(banner.line.text):find("Sur place", 1, true), "sur place : " .. Plain(banner.line.text))
PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.515, 0.303
ShortestPathForever.API.Journey = function() return { owner = "Itineraire" } end
-- en pause
ns.SetPaused(true, "cleared")
assert(Plain(banner.title.text):find("pause", 1, true), "bandeau en pause")
ns.SetPaused(false)
ns.RequestPlan("t", 0)
Advance(3)
-- masqué par /iti bandeau, en combat si demandé
SlashCmdList.ITINERAIRE("bandeau")
assert(not banner.shown, "/iti bandeau ne masque pas")
SlashCmdList.ITINERAIRE("bandeau")
assert(banner.shown, "/iti bandeau ne réaffiche pas")
ns.db.ui.hideCombat = true
InCombatLockdown = function() return true end
Fire("PLAYER_REGEN_DISABLED")
assert(not banner.shown, "bandeau visible en combat")
InCombatLockdown = function() return false end
Fire("PLAYER_REGEN_ENABLED")
assert(banner.shown, "bandeau pas revenu après le combat")
print("OK bandeau")

-- 3. Fenêtre légère : 3 lignes, « À savoir » replié en une ligne, clic pour déplier.
local shownRows = 0
for _, f in ipairs(FRAMES) do
	if type(rawget(f, "stop")) == "table" and rawget(f, "num") and f.shown then shownRows = shownRows + 1 end
end
assert(shownRows <= 3, "fenêtre légère : " .. shownRows .. " lignes")

-- 4. Fourchettes : résumé « x–y min » (rythme pas encore mesuré : large).
local summary
for _, f in ipairs(FONTS) do
	if tostring(f.text):find("fin vers") then summary = Plain(f.text) end
end
assert(summary and summary:find("–"), "pas de fourchette : " .. tostring(summary))
print("résumé :", summary)

-- 5. Rythme par cible et par objectif : un zhévra toutes les 40 s (le général n'a que 2 mesures).
local zhevra = LOG[1].objectives[1]
Fire("QUEST_LOG_UPDATE")
Advance(100)
local function Kill()
	zhevra.numFulfilled = zhevra.numFulfilled + 1
	zhevra.text = "Zhévra tué : " .. zhevra.numFulfilled .. "/6"
	Fire("QUEST_LOG_UPDATE")
end
Kill() -- 1er : compte le trajet
Advance(40)
Kill()
Advance(40)
Kill()
Advance(5)
local calib = ns.char.calib
assert(calib.targets["monster:106"] and calib.targets["monster:106"].n == 2, "cible non apprise")
assert(calib.slots["1001:1"] and calib.slots["1001:1"].n == 2, "objectif non appris")
assert(not ns.Rates().monster, "le rythme général ne doit pas encore compter (2 mesures)")
ns.RequestPlan("t", 0)
Advance(4)
local zstop = StopOf(function(s) return s.kind == "area" and s.questSet[1001] end)
-- 25 s par défaut -> cible (2 mesures de 40) : 32,5 -> objectif (2 mesures de 40) : 36,25 ; 3 restants
assert(math.abs(zstop.work - 3 * 36.25) < 0.6, "travail zhévras : " .. zstop.work)
local lstop = StopOf(function(s) return s.kind == "area" and s.questSet[1002] end)
assert(math.abs(lstop.work - 5 * 25) < 0.6, "les lions ne doivent pas hériter des zhévras : " .. lstop.work)
print("travail zhévras (3 restants) :", zstop.work, "· lions (5) :", lstop.work)
-- l'objectif quitte le journal : sa mesure part, la cible reste
local saved = table.remove(LOG, 1)
Fire("QUEST_LOG_UPDATE")
assert(not calib.slots["1001:1"] and calib.targets["monster:106"], "nettoyage des objectifs")
table.insert(LOG, 1, saved)
Fire("QUEST_LOG_UPDATE")
Advance(4)

-- 6. Rythme par zone : 2 fois plus lent que prévu dans Les Tarides (3 trajets).
ns.ready = false
for k = 1, 3 do
	local wx, wy, inst = ns.Geo.World(1413, 0.60, 0.30)
	ns.plan = { order = { { key = "Z" .. k, leg = 60, legWalk = true, radius = 10, map = 1413, x = 0.60, y = 0.30, wx = wx, wy = wy, inst = inst, tasks = {}, quests = {}, details = {}, pickups = {} } } }
	PLAYER.x, PLAYER.y = 0.55, 0.30
	Advance(1)
	Advance(119)
	PLAYER.x, PLAYER.y = 0.60, 0.30
	Advance(1)
end
ns.ready = true
assert(calib.zones[1413] and calib.zones[1413].n == 3, "zone non apprise")
local zp = ns.ZonePace()
assert(math.abs(zp[1413] - 2) < 0.05, "facteur de zone : " .. tostring(zp[1413]))
ns.Geo.SetPace(1.2, { [1413] = 2 })
local a = { map = 1413, x = 0.5, y = 0.3, wx = 0, wy = 0, inst = 1 }
local b = { map = 1413, x = 0.6, y = 0.3, wx = 700, wy = 0, inst = 1 }
local c = { map = 1411, x = 0.6, y = 0.3, wx = 700, wy = 0, inst = 1 }
assert(math.abs(ns.Geo.Walk(a, b, 7) - 700 * 1.25 * 2 / 7) < 0.01, "marche dans la zone mesurée")
assert(math.abs(ns.Geo.Walk(a, c, 7) - 700 * 1.25 * 1.2 / 7) < 0.01, "marche ailleurs : rythme général")
local spread = ns.Spread()
print("rythme :", ns.PaceText(), "· fourchettes :", spread.work, spread.travel, spread.system)
for _, line in ipairs(ns.PaceDetails(5)) do print("  " .. line) end
PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.515, 0.303
ns.RequestPlan("t", 0)
Advance(4)
print("OK précision")

-- 7. Chemin détaillé : un long trajet (vol) parmi les 3 prochaines étapes dit comment y aller.
local thrall = StopOf(function(s) return s.kind == "turnin" and s.questSet[1003] end)
assert(thrall, "étape Thrall absente")
ns.session.pinned = thrall.key
ns.RequestPlan("t", 0)
Advance(4)
thrall = ns.plan.order[1]
assert(thrall.questSet[1003], "Thrall pas en 1er")
assert(not thrall.legWalk and thrall.route, "pas de chemin détaillé pour un trajet en vol")
local routeText = ns.UI.RouteText(thrall.route)
assert(routeText:find("vol vers Orgrimmar", 1, true), "chemin : " .. routeText)
print("chemin :", routeText)
ns.session.pinned = nil

-- 8. Rapport à copier : texte brut, avec le trajet, le rythme et les erreurs de Shortest Path.
ns.OnError("boum test")
SlashCmdList.ITINERAIRE("rapport")
local copy = _G.ItineraireCopy
assert(copy and copy.shown, "boîte du rapport non affichée")
local text = copy.edit.text
assert(text:find("Rapport Itinéraire", 1, true) and text:find("Trajet :", 1, true) and text:find("Rythme :", 1, true), "rapport incomplet")
assert(text:find("Looks.lua:63 boum SP", 1, true), "erreurs de Shortest Path absentes")
assert(text:find("boum test", 1, true), "erreurs d'Itinéraire absentes")
assert(not text:find("|c", 1, true) and not text:find("|", 1, true), "codes du jeu dans le texte à copier")
-- lecture seule : une frappe remet le texte
copy.edit.text = "abimé"
copy.edit.scripts.OnTextChanged(copy.edit, true)
assert(copy.edit.text == text, "le rapport doit rester intact")
print(text:sub(1, 600))
print("OK rapport")

-- 9. Réglages tout-en-un : onglets, cases Questie / Shortest Path.
SlashCmdList.ITINERAIRE("reglages")
local panel = _G.ItineraireOptions
assert(panel.shown and ns.Options.page == "trajet", "réglages : onglet trajet")
ns.Options.Toggle(true, "addons")
assert(ns.Options.page == "addons", "onglet Questie & flèche")
ShortestPathForeverDB.arrow = false
local changed = ns.Options.Ext.ApplyRecommended()
assert(#changed == 1 and ShortestPathForeverDB.arrow == true, "réglages conseillés")
ns.Options.Ext.SetQuestie("autoaccept", true)
assert(Questie.db.profile.autoAccept.enabled == true, "acceptation auto")
print("OK réglages")
print("OK v1.8")
