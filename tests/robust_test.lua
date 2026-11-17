-- Robustesse : une partie facultative qui plante ne doit jamais empêcher la flèche de suivre le trajet.
dofile(TESTS .. "/wow_mock.lua")
dofile(TESTS .. "/scenario_setup.lua")
local ns = LoadAddon(ADDON_DIR, { "Solver.lua", "Geo.lua", "Data.lua", "Planner.lua", "Guide.lua", "UI.lua", "Options.lua", "Group.lua", "Core.lua" })
Fire("ADDON_LOADED", "Itineraire")
Fire("PLAYER_LOGIN")
Advance(5)
assert(ns.plan and #ns.plan.order > 0, "pas de trajet de base")
local baseCount = #ns.plan.order

-- 1. Les trois parties facultatives plantent : trajet de base envoyé, erreurs notées.
local realSelect, realHearth, realPromo = ns.Planner.SelectCandidates, ns.Planner.Hearth, ns.Planner.TrainerNeed
ns.Planner.SelectCandidates = function() error("boum propositions") end
ns.Planner.Hearth = function() error("boum foyer") end
local before = #SP_ROUTES
ns.RequestPlan("t", 0)
Advance(5)
-- (sans les quêtes proposées, mais avec toutes les étapes du journal)
assert(#ns.plan.order > 0 and #ns.plan.order <= baseCount, "trajet de base perdu : " .. #ns.plan.order)
for _, s in ipairs(ns.plan.order) do
	assert(not s.candidate, "une proposition a survécu à l'erreur")
end
assert(#SP_ROUTES >= before, "trajet non envoyé")
assert(ns.guideState and (ns.guideState.result:find("Shortest Path") or ns.guideState.result:find("flèche inchangée")), "état de la flèche : " .. tostring(ns.guideState and ns.guideState.result))
assert(ns.char.lastError and ns.char.lastError.text:find("boum"), "erreur non notée")
print("erreur notée :", ns.char.lastError.text)
ns.Planner.SelectCandidates, ns.Planner.Hearth = realSelect, realHearth

-- 2. La fenêtre plante : la flèche reçoit quand même le trajet.
local realRefresh = ns.UI.Refresh
ns.UI.Refresh = function() error("boum fenêtre") end
ns.Guide.Reset()
local n = #SP_ROUTES
ns.RequestPlan("t", 0)
Advance(5)
assert(#SP_ROUTES > n, "flèche bloquée par une erreur de la fenêtre")
assert(ns.char.lastError.text:find("fenêtre"), "erreur de fenêtre non notée")
ns.UI.Refresh = realRefresh

-- 3. Shortest Path refuse le trajet complet : il reçoit la version simple.
local realNav = ShortestPathForever.API.NavigateRoute
local calls = 0
ShortestPathForever.API.NavigateRoute = function(owner, stops)
	calls = calls + 1
	if stops[1].kind then return false end -- refuse la version « riche »
	return realNav(owner, stops)
end
ns.Guide.Reset()
ns.RequestPlan("t", 0)
Advance(5)
assert(calls >= 2 and ns.guideState.result:find("version simple"), "pas de 2e essai : " .. tostring(ns.guideState.result))
ShortestPathForever.API.NavigateRoute = realNav

-- 4. /iti etat
SlashCmdList.ITINERAIRE("etat")
local found
for _, m in ipairs(PRINTED) do
	if m:find("dernier envoi à la flèche") then found = m end
end
assert(found, "/iti etat muet")
print(found)
print("OK robustesse")

-- 5. Trajet effacé dans Shortest Path : pause, puis reprise automatique quand plus rien ne guide.
local realJourney, realEnded = ShortestPathForever.API.Journey, ShortestPathForever.API.Ended
ShortestPathForever.API.Journey = function() return nil end
ShortestPathForever.API.Ended = function() return "cleared" end
ns.RequestPlan("t", 0)
Advance(3)
assert(ns.session.paused, "pas de pause après effacement")
ShortestPathForever.API.Ended = realEnded
Advance(20)
assert(not ns.session.paused, "pas de reprise automatique")
ShortestPathForever.API.Journey = realJourney
local resumed
for _, m in ipairs(PRINTED) do
	if m:find("guidage repris") then resumed = true end
end
assert(resumed, "message de reprise absent")
-- « /iti stop » reste une vraie pause.
SlashCmdList.ITINERAIRE("stop")
ShortestPathForever.API.Journey = function() return nil end
Advance(20)
assert(ns.session.paused, "/iti stop ne doit pas reprendre tout seul")
ShortestPathForever.API.Journey = realJourney
print("OK reprise")

-- 6. Shortest Path cherche encore le chemin : ne pas relancer sa recherche à chaque recalcul.
SlashCmdList.ITINERAIRE("r")
Advance(3)
local sends = 0
local realNav2 = ShortestPathForever.API.NavigateRoute
ShortestPathForever.API.NavigateRoute = function(...) sends = sends + 1 return realNav2(...) end
ShortestPathForever.API.Journey = function() return nil, "loading" end
local firstKey = ns.plan.order[1].key
for k = 1, 3 do
	ns.SkipStop(ns.plan.order[#ns.plan.order].key) -- le trajet change, pas sa 1re étape
	Advance(3)
	assert(ns.plan.order[1].key == firstKey, "1re étape changée")
end
assert(sends == 0, "trajet renvoyé pendant la recherche : " .. sends .. " fois")
assert(ns.guideState.result:find("cherche encore"), "état : " .. ns.guideState.result)
-- Recherche finie : la suite part au plus tard une minute après le dernier envoi.
ShortestPathForever.API.Journey = function() return { owner = "Itineraire", goal = {} } end
Advance(6)
assert(sends == 0, "suite renvoyée trop tôt (la flèche n'a pas changé) : " .. sends)
Advance(60)
assert(sends == 1, "trajet en attente non envoyé : " .. sends)
ShortestPathForever.API.NavigateRoute, ShortestPathForever.API.Journey = realNav2, realJourney
print("OK recherche")
