-- Itinéraire : positions, distances et temps de trajet.
local _, ns = ...
local Geo = {}
ns.Geo = Geo

local HBD
local WALK_FACTOR = 1.25 -- les chemins ne sont jamais en ligne droite
local LONG_LEG = 120 -- au-delà (secondes à pied), on demande le vrai temps à Shortest Path
local CROSSING = 1800 -- autre continent sans estimation : très cher

-- Sans HereBeDragons (il vient avec Questie) : les mêmes deux fonctions avec l'API de cartes du jeu.
local Native = {}
function Native:GetWorldCoordinatesFromZone(x, y, map)
	if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then
		return nil
	end
	local ok, instance, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
	if not (ok and instance and pos and pos.GetXY) then
		return nil
	end
	local wy, wx = pos:GetXY() -- (axes du monde : comme HereBeDragons, x = est-ouest)
	return wx, wy, instance
end
function Native:GetPlayerWorldPosition()
	local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local pos = map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
	if not (pos and pos.GetXY) then
		return nil
	end
	local x, y = pos:GetXY()
	return Native:GetWorldCoordinatesFromZone(x, y, map)
end

function Geo.Init()
	if HBD then
		return true
	end
	if LibStub then
		HBD = LibStub("HereBeDragons-2.0", true)
	end
	if not HBD and QuestieLoader then
		local ok, mod = pcall(QuestieLoader.ImportModule, QuestieLoader, "HBD")
		if ok then
			HBD = mod
		end
	end
	if not HBD and C_Map and C_Map.GetWorldPosFromMapPos then
		HBD = Native
	end
	return HBD ~= nil
end

-- Position monde d'un point de carte (coordonnées 0-1).
function Geo.World(map, x, y)
	if not (HBD and map and x and y) then
		return nil
	end
	local ok, wx, wy, inst = pcall(HBD.GetWorldCoordinatesFromZone, HBD, x, y, map)
	if ok and wx and wy then
		return wx, wy, inst
	end
	return nil
end

-- Valeur utilisable ? (le client peut renvoyer des valeurs « secrètes » qu'on ne doit pas manipuler)
local function Plain(v)
	if v == nil then
		return nil
	end
	if issecretvalue and issecretvalue(v) then
		return nil
	end
	if canaccessvalue and not canaccessvalue(v) then
		return nil
	end
	return type(v) == "number" and v or nil
end

function Geo.Player()
	local p = {}
	if HBD then
		local ok, wx, wy, inst = pcall(HBD.GetPlayerWorldPosition, HBD)
		if ok and Plain(wx) and Plain(wy) then
			p.wx, p.wy, p.inst = wx, wy, Plain(inst)
		end
	end
	local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	if Plain(map) then
		local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
		if ok and pos then
			local x, y = pos:GetXY()
			if Plain(x) and Plain(y) then
				p.map, p.x, p.y = map, x, y
			end
		end
	end
	return p
end

function Geo.Yards(a, b)
	if not (a and b and a.wx and b.wx) or a.inst ~= b.inst then
		return nil
	end
	local dx, dy = a.wx - b.wx, a.wy - b.wy
	return math.sqrt(dx * dx + dy * dy)
end

function Geo.Speed()
	local speed = 7
	if GetUnitSpeed and IsMounted and IsMounted() then
		local _, run = GetUnitSpeed("player")
		if run and run > speed then
			speed = run
		end
	end
	return speed
end

-- Rythme de déplacement mesuré sur le joueur (1 = comme prévu, 1,3 = 30 % plus lent), en général et
-- par zone (relief, routes…).
local pace, zonePace = 1, {}
local function ValidPace(v)
	return type(v) == "number" and v >= 0.5 and v <= 3
end

function Geo.SetPace(value, zones)
	pace = ValidPace(value) and value or 1
	zonePace = {}
	if type(zones) == "table" then
		for zone, v in pairs(zones) do
			if type(zone) == "number" and ValidPace(v) then
				zonePace[zone] = v
			end
		end
	end
end

-- Le facteur qui vaut pour aller jusqu'à `point` (celui de sa zone s'il est connu).
function Geo.PaceAt(point)
	local zone = point and point.map and Geo.Zone(point.map)
	return zone and zonePace[zone] or pace
end

-- Temps de marche estimé (secondes) entre deux points du même continent, sinon nil.
function Geo.Walk(a, b, speed)
	local d = Geo.Yards(a, b)
	return d and (d * WALK_FACTOR * Geo.PaceAt(b) / (speed or Geo.Speed())) or nil
end

-- La « région » d'une carte : la zone qui la contient (une grotte, un étage de ville ou une
-- sous-carte remontent à leur zone). Gardé en cache.
local zoneOf = {}
function Geo.Zone(map)
	if type(map) ~= "number" then
		return nil
	end
	if zoneOf[map] ~= nil then
		return zoneOf[map] or nil
	end
	local found, cur = nil, map
	for _ = 1, 6 do
		local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(cur)
		if not info then
			break
		end
		local kind = info.mapType
		if kind == 3 then -- Enum.UIMapType.Zone
			found = cur
			break
		end
		if kind == nil or kind < 3 or not info.parentMapID or info.parentMapID == 0 then
			break -- continent ou monde : pas de zone au-dessus
		end
		cur = info.parentMapID
	end
	found = found or map
	zoneOf[map] = found
	return found
end

function Geo.ZoneName(map)
	local info = map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
	return info and info.name or ""
end

-- Temps réel via Shortest Path (vols, bateaux, pierre de foyer depuis le joueur), avec cache.
local cache = {}
local CACHE_TTL = 600

function Geo.SPApi()
	local api = ShortestPathForever and ShortestPathForever.API
	if type(api) == "table" and (api.version == 1 or api.version == 2) then
		return api
	end
	return nil
end

local detailCache = {}
function Geo.ClearCache()
	cache, detailCache = {}, {}
end

local function Key(a, b)
	return string.format("%d:%.3f:%.3f>%d:%.3f:%.3f", a.map, a.x, a.y, b.map, b.x, b.y)
end

function Geo.Estimate(a, b, fromPlayer)
	local api = Geo.SPApi()
	if not (api and api.Estimate and a.map and b.map) then
		return nil
	end
	local key = (fromPlayer and "P" or "") .. Key(a, b)
	local hit = cache[key]
	if hit and GetTime() - hit.t < (fromPlayer and 20 or CACHE_TTL) then
		return hit.s
	end
	local ok, seconds = pcall(api.Estimate, a.map, a.x, a.y, b.map, b.x, b.y)
	if ok and type(seconds) == "number" and seconds >= 0 then
		cache[key] = { s = seconds, t = GetTime() }
		return seconds
	end
	return nil
end

-- Comment Shortest Path ferait ce trajet (à pied, vol, bateau…), pour l'afficher : { {mode, to, seconds}, … }.
-- nil si Shortest Path ne sait pas (ou pas encore).
function Geo.RouteDetail(a, b)
	local api = Geo.SPApi()
	if not (api and api.EstimateDetail and a and b and a.map and b.map and a.x and b.x) then
		return nil
	end
	local key = Key(a, b)
	local hit = detailCache[key]
	if hit and GetTime() - hit.t < CACHE_TTL then
		return hit.legs
	end
	local ok, detail = pcall(api.EstimateDetail, a.map, a.x, a.y, b.map, b.x, b.y)
	if not (ok and type(detail) == "table" and type(detail.legs) == "table") then
		return nil -- (pas gardé : Shortest Path peut encore être en train de charger)
	end
	local legs = { seconds = tonumber(detail.seconds) }
	for k, leg in ipairs(detail.legs) do
		if k > 8 then
			break
		end
		if type(leg) == "table" then
			legs[#legs + 1] = {
				mode = type(leg.mode) == "string" and leg.mode or "?",
				to = type(leg.to) == "string" and leg.to or nil,
				seconds = tonumber(leg.seconds) or 0,
			}
		end
	end
	detailCache[key] = { t = GetTime(), legs = legs }
	return legs
end

-- Matrice des coûts. nodes[0] = joueur, nodes[1..n] = étapes. `budget` = appels Shortest Path max.
function Geo.Matrix(nodes, n, budget, tick)
	local speed = Geo.Speed()
	local C = { sp = {} } -- C.sp[i][j] = true : temps donné par Shortest Path (vol, bateau…)
	local long = {}
	local paceTo = {}
	for j = 1, n do
		paceTo[j] = Geo.PaceAt(nodes[j])
	end
	for i = 0, n do
		C[i] = {}
		for j = 1, n do
			if i ~= j then
				local d = Geo.Yards(nodes[i], nodes[j])
				local walk = d and (d * WALK_FACTOR * paceTo[j] / speed) or CROSSING
				C[i][j] = walk
				if (not d or walk > LONG_LEG) and nodes[i].map and nodes[j].map then
					long[#long + 1] = { i, j, walk }
				end
			else
				C[i][j] = 0
			end
		end
		if tick then
			tick()
		end
	end
	-- Les trajets depuis le joueur d'abord (ils comptent la pierre de foyer), puis les plus longs.
	table.sort(long, function(a, b)
		if (a[1] == 0) ~= (b[1] == 0) then
			return a[1] == 0
		end
		return a[3] > b[3]
	end)
	local used = 0
	for _, pair in ipairs(long) do
		if used >= budget then
			break
		end
		local i, j = pair[1], pair[2]
		local est = Geo.Estimate(nodes[i], nodes[j], i == 0)
		used = used + 1
		if est and est < C[i][j] then
			C[i][j] = est
			C.sp[i] = C.sp[i] or {}
			C.sp[i][j] = true
		end
		if tick then
			tick()
		end
	end
	return C, used
end
