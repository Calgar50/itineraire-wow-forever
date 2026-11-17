-- Itinéraire : envoie le trajet à Shortest Path Forever (ou au repère Blizzard à défaut).
local _, ns = ...
local Guide = {}
ns.Guide = Guide
local Geo = ns.Geo

local lastSig, lastTitles, pending, lastFirst, lastFirstAt, lastSentAt
-- Chaque envoi d'un trajet modifié fait repartir Shortest Path de zéro : la flèche s'arrête, il recherche
-- le chemin (« Recherche du chemin le plus rapide… », pas de points), puis repart. Pendant sa recherche,
-- un nouvel envoi la relance même : avec des recalculs fréquents, elle ne finissait jamais.
-- Donc : tant que la 1re étape (là où va la flèche) ne change pas, la suite du trajet n'est renvoyée
-- qu'au plus toutes les 60 s, et jamais pendant une recherche (au plus 45 s d'attente).
local SEARCH_PATIENCE = 45
local RESEND_GAP = 60

local function SamePlace(a, b)
	return a and b and a.map == b.map and math.abs((a.x or 0) - (b.x or 0)) < 0.0005 and math.abs((a.y or 0) - (b.y or 0)) < 0.0005
end

-- Ce qui s'est passé au dernier envoi (affiché par /iti etat, gardé par /iti debug).
local function Note(result, count)
	ns.guideState = { result = result, stops = count, at = date and date("%H:%M:%S") or nil }
end

-- Icône de l'étape sur la carte de Shortest Path (« ? » pour un rendu, « ! » pour une prise…).
local KINDS = { turnin = "turnin", area = "objective", dungeon = "dungeon", pickup = "pickup" }

local function ToSP(s)
	local stop = {
		map = s.map, x = s.x, y = s.y,
		title = s.title,
		tooltip = (#s.details > 0) and table.concat(s.details, "\n") or nil,
		hold = true, -- c'est Itinéraire qui décide quand l'étape est finie
		-- (jamais « vendor » : Shortest Path 1.37 le déclare mais n'a pas d'image pour lui et plante en dessinant
		--  l'épingle, ce qui coupe aussi le tracé du trajet sur la minicarte)
		kind = s.kind == "service" and (s.service and s.service.kind == "trainer" and "trainer" or nil) or KINDS[s.kind],
	}
	if s.kind == "area" or s.kind == "dungeon" then
		stop.radius = s.radius
	end
	local ids = {}
	for _, q in ipairs(s.quests) do
		ids[#ids + 1] = q.id
	end
	if #ids > 0 then
		stop.questID = ids[1]
		stop.questIDs = ids
	end
	if s.kind == "turnin" and #ids > 0 then
		stop.handins = ids
	end
	if type(s.npc) == "number" and s.npc > 0 then
		stop.npc = s.npc
	end
	return stop
end

local function Fallback(s)
	if not (s and C_Map and C_Map.CanSetUserWaypointOnMap and UiMapPoint) then
		return
	end
	if C_Map.CanSetUserWaypointOnMap(s.map) then
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(s.map, s.x, s.y))
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		end
	end
end

function Guide.Apply(plan)
	if ns.session.paused then
		Note("en pause (trajet effacé ou remplacé dans Shortest Path)", 0)
		return
	end
	local first = plan.order[1]
	if not first then
		Note("aucune étape", 0)
		Guide.Clear()
		return
	end
	if InCombatLockdown() then
		Note("en combat : envoi à la fin du combat", 0)
		pending = plan
		return
	end
	pending = nil
	local api = Geo.SPApi()
	if not (api and api.NavigateRoute) then
		Note("Shortest Path absent : repère Blizzard", 0)
		Fallback(first)
		return
	end
	local stops, keys, titles = {}, {}, {}
	for k = 1, math.min(#plan.order, ns.db.maxStops or 25, 64) do
		local s = plan.order[k]
		stops[k] = ToSP(s)
		keys[k] = s.key
		titles[k] = s.title
	end
	local sig = table.concat(keys, "|")
	local journey, notReady
	if api.Journey then
		journey, notReady = api.Journey()
	end
	-- « loading » = Shortest Path cherche encore le chemin de NOTRE trajet (il ne dit pas encore à qui il est).
	local searching = journey == nil and notReady == "loading" and lastSig ~= nil
	local ours = (journey and journey.owner == ns.OWNER) or searching
	if lastSig and not ours then
		-- Le joueur (ou un autre addon) a remplacé ou effacé notre trajet : on se met en pause.
		local why = api.Ended and api.Ended(ns.OWNER)
		if why == "cleared" or why == "replaced" then
			ns.SetPaused(true, why)
			Note(why == "cleared" and "en pause : trajet effacé dans Shortest Path" or "en pause : un autre trajet a pris la flèche", 0)
			lastSig = nil
			return
		end
	end
	if ours and lastSig and sig ~= lastSig and keys[1] == lastFirst and SamePlace(stops[1], lastFirstAt)
		and GetTime() - (lastSentAt or 0) < (searching and SEARCH_PATIENCE or RESEND_GAP) then
		-- La flèche va toujours au même endroit : on ne la dérange pas, la suite partira plus tard.
		if api.RenameStop and lastTitles and lastTitles[1] ~= titles[1] then
			pcall(api.RenameStop, ns.OWNER, 1, titles[1])
			lastTitles[1] = titles[1]
		end
		pending = plan
		Note(searching and "en attente : Shortest Path cherche encore le chemin"
			or "flèche inchangée : la suite du trajet sera mise à jour dans moins d'une minute", #stops)
		return
	end
	if sig == lastSig and ours then
		if api.RenameStop then
			for k, title in ipairs(titles) do
				if lastTitles[k] ~= title then
					pcall(api.RenameStop, ns.OWNER, k, title)
				end
			end
		end
		lastTitles = titles
		Note("trajet à jour dans Shortest Path", #stops)
		return
	end
	local ok, accepted = pcall(api.NavigateRoute, ns.OWNER, stops)
	if ok and accepted then
		lastSig, lastTitles, lastFirst, lastFirstAt, lastSentAt = sig, titles, keys[1], stops[1], GetTime()
		Note("trajet envoyé à Shortest Path", #stops)
	else
		-- Refusé (une étape invalide ?) : on réessaie sans les extras, puis repère Blizzard.
		local plain = {}
		for k, stop in ipairs(stops) do
			plain[k] = { map = stop.map, x = stop.x, y = stop.y, title = stop.title, hold = true, radius = stop.radius }
		end
		local ok2, accepted2 = pcall(api.NavigateRoute, ns.OWNER, plain)
		if ok2 and accepted2 then
			lastSig, lastTitles, lastFirst, lastFirstAt, lastSentAt = sig, titles, keys[1], stops[1], GetTime()
			Note("trajet envoyé à Shortest Path (version simple : " .. (ok and "refusé" or tostring(accepted)) .. ")", #stops)
		else
			lastSig = nil
			Note("refusé par Shortest Path (" .. (ok and "refus" or tostring(accepted)) .. ") : repère Blizzard", 0)
			Fallback(first)
		end
	end
end

function Guide.Flush()
	if pending then
		Guide.Apply(pending)
	end
end

function Guide.Reset()
	lastSig, lastTitles, lastFirst, lastFirstAt, lastSentAt = nil, nil, nil, nil, nil
end

function Guide.Clear()
	local api = Geo.SPApi()
	if api and api.Cancel and lastSig then
		pcall(api.Cancel, ns.OWNER)
	end
	lastSig, lastTitles, lastFirst, lastFirstAt, lastSentAt = nil, nil, nil, nil, nil
end
