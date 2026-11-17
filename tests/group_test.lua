-- Partage de groupe : état des journaux, trajet unique calculé par le guide, suivi par les autres.
dofile(TESTS .. "/wow_mock.lua")
time = function() return 1800000000 end

-- Groupe de 2 : toi (Testeur) + Alix.
LEADER = "player"
function UnitName(unit) if unit == "party1" then return "Alix" end return "Testeur" end
function UnitExists(unit) return unit == "party1" end
function IsInGroup() return true end
function IsInRaid() return false end
function GetNumGroupMembers() return 2 end
function UnitIsGroupLeader(unit) return unit == LEADER end
SENT = {}
C_ChatInfo = {
	RegisterAddonMessagePrefix = function() return true end,
	SendAddonMessage = function(prefix, msg, channel) SENT[#SENT + 1] = { prefix = prefix, msg = msg, channel = channel } return true end,
}

local function npc(id, name, area, pts, level)
	NPCS[id] = { id = id, name = name, spawns = { [area] = pts }, friendly = true, maxLevel = level }
end
npc(9, "Sergra Darkthorn", 17, { { 52.2, 31.0 } })
npc(13, "Gazrog", 17, { { 51.7, 29.9 } })
npc(106, "Zhévra", 17, { { 55, 33 }, { 56, 34 }, { 57, 32 } }, 14)
npc(111, "Harpie Ensorçaile", 17, { { 39, 13 }, { 40, 14 } }, 14)
-- Ton journal : les zhévras (fini à moitié).
LOG[1] = { info = { questID = 1001, title = "Les zhévras", level = 15, suggestedGroup = 0 },
	objectives = { { text = "Zhévra : 6/6", type = "monster", finished = true, numFulfilled = 6, numRequired = 6 } } }
QUESTS[1001] = { Id = 1001, name = "Les zhévras", level = 15, xp = 900, Finisher = { NPC = { 9 } },
	Objectives = { { spawnList = { { Id = 106, Name = "Zhévra", Spawns = NPCS[106].spawns, Hostile = true } } } },
	ObjectiveData = { { Type = "monster", Id = 106 } } }
-- Quête que seule Alix a.
QUESTS[1004] = { Id = 1004, name = "Les harpies", level = 15, xp = 1100, Finisher = { NPC = { 13 } },
	ObjectiveData = { { Type = "monster", Id = 111 } } }

VERSIONS = { Itineraire = "1.9.0" }
C_AddOns.GetAddOnMetadata = function(name, field) return field == "Version" and VERSIONS[name] or nil end
PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.52, 0.31
ItineraireDB = { groupShare = true }
local ns = LoadAddon(ADDON_DIR, { "Solver.lua", "Geo.lua", "Data.lua", "Planner.lua", "Guide.lua", "UI.lua", "Options.lua", "Group.lua", "Core.lua" })
Fire("ADDON_LOADED", "Itineraire")
Fire("PLAYER_LOGIN")
Advance(5)

-- Envoie un message « réseau » de la part de `sender`, découpé comme le fait l'addon.
local seq = 0
local function Deliver(sender, kind, payload)
	seq = seq + 1
	local parts, i = {}, 1
	while i <= #payload do
		parts[#parts + 1] = payload:sub(i, i + 149)
		i = i + 150
	end
	if #parts == 0 then parts[1] = "" end
	for p, chunk in ipairs(parts) do
		Fire("CHAT_MSG_ADDON", "ITIN1", kind .. seq .. ":" .. p .. "/" .. #parts .. ":" .. chunk, "PARTY", sender)
	end
end
-- Réassemble le dernier message d'un genre envoyé par l'addon.
local function LastSent(kind)
	local byId, last = {}, nil
	for _, m in ipairs(SENT) do
		local k, id, p, total, chunk = m.msg:match("^(%a)(%d+):(%d+)/(%d+):(.*)$")
		assert(#m.msg <= 255, "message trop long : " .. #m.msg)
		assert(m.prefix == "ITIN1" and m.channel == "PARTY", "préfixe ou canal")
		if k == kind then
			byId[id] = byId[id] or { total = tonumber(total), parts = {} }
			byId[id].parts[tonumber(p)] = chunk
			if #byId[id].parts == byId[id].total then last = table.concat(byId[id].parts) end
		end
	end
	return last
end
local function SubTexts()
	local out = {}
	for _, f in ipairs(FONTS) do out[#out + 1] = tostring(f.text) end
	return table.concat(out, "\n")
end

-- 0. Seul (Alix n'a pas encore répondu) : trajet perso, état envoyé + demande aux autres.
assert(LastSent("S"), "état non envoyé")
assert(LastSent("Q"), "pas de demande d'état aux équipiers")
assert(not ns.Group.Active(), "pas encore d'équipier qui partage")
print("état envoyé :", LastSent("S"))

-- 1. Alix partage : elle a les zhévras (2/6) et les harpies (0/8). Tu es chef : tu guides.
Deliver("Alix-Forever", "S", "1#1#15#1001,0,2/6;1004,0,0/8")
Advance(5)
assert(ns.Group.Active() and ns.Group.IsGuide(), "tu devrais guider (chef de groupe)")
local plan = ns.plan
for k, s in ipairs(plan.order) do
	print(string.format("%2d. [%s] %s  |  %s  pour : %s", k, s.kind, s.title, s.subtitle or "", table.concat(s.owners or {}, ",")))
end
local function Find(pred) for k, s in ipairs(plan.order) do if pred(s) then return k, s end end end
local kz, zhev = Find(function(s) return s.kind == "area" and s.questSet[1001] end)
assert(zhev, "les zhévras de Alix (2/6) doivent rester au trajet même si toi tu as fini")
local kh, harp = Find(function(s) return s.kind == "area" and s.questSet[1004] end)
assert(harp and harp.owners[1] == "Alix" and #harp.owners == 1, "harpies : pour Alix seulement")
local kt = Find(function(s) return s.kind == "turnin" and s.questSet[1001] end)
assert(kt and kt > kz, "rendu des zhévras après l'objectif de Alix")
assert(plan.groupMode and not plan.candidates[1], "trajet de groupe : pas de quêtes proposées perso")
local texts = SubTexts()
assert(texts:find("Groupe %(tu guides%)"), "résumé : tu guides")
assert(texts:find("pour tous") and texts:find("pour Alix"), "pour qui : affiché")
-- Le trajet est envoyé au groupe, et relisible.
local routePayload = LastSent("R")
assert(routePayload, "trajet non envoyé au groupe")
local route = ns.Group.ParseRoute(routePayload)
assert(route and #route.stops == #plan.order, "trajet envoyé incomplet")
assert(route.stops[1].title == plan.order[1].title, "titre de la 1re étape")
print("trajet envoyé :", #route.stops, "étapes,", #routePayload, "octets")

-- 2. Alix devient chef : c'est elle qui guide, tu suis son trajet.
LEADER = "party1"
Fire("GROUP_ROSTER_UPDATE")
Advance(2)
assert(ns.Group.Guide() == "Alix", "Alix devrait guider")
local guided = "1#7#3#900#"
	.. "area.monster~1413~3950~1350~Tuer : Harpie |cffff0000piège|r~400~200~1004~Alix~A:1004.1~0~60;"
	.. "turnin~1413~5170~2990~Rendre « Les harpies »~300~15~1004~Alix~T:n13#0:1004~13~8;"
	.. "turnin~1413~5220~3100~Rendre « Les zhévras »~20~15~1001~Testeur,Alix~T:n9#0:1001~9~8"
Deliver("Inconnu", "R", guided) -- quelqu'un hors du groupe : ignoré
Advance(1)
assert(not ns.plan.group, "message d'un inconnu accepté")
Deliver("Alix", "R", guided)
Advance(1)
plan = ns.plan
assert(plan.group and plan.group.guide == "Alix", "trajet du guide non suivi")
assert(#plan.order == 3 and plan.order[2].title == "Rendre « Les harpies »", "étapes reçues")
assert(not plan.order[1].title:find("|", 1, true), "texte non nettoyé (codes « | »)")
assert(SP_ROUTES[#SP_ROUTES][1].title == plan.order[1].title, "la flèche ne suit pas le trajet du groupe")
texts = SubTexts()
assert(texts:find("Groupe %(guide : Alix%)"), "résumé : guide Alix")
assert(texts:find("pour tous"), "pour tous (rendu commun)")
-- Pendant qu'on suit, pas de calcul perso qui écraserait le trajet du groupe.
ns.RequestPlan("t", 0)
Advance(3)
assert(ns.plan == plan, "un calcul perso a remplacé le trajet du groupe")
-- Messages abîmés : ignorés sans erreur.
Deliver("Alix", "R", "1#8#2#0#area~-5~99999~1~x;;~~~")
Deliver("Alix", "S", "9#1#15#garbage")
Fire("CHAT_MSG_ADDON", "ITIN1", "R99:5/2:abc", "PARTY", "Alix")
Fire("CHAT_MSG_ADDON", "ITIN1", string.rep("x", 300), "PARTY", "Alix")
Advance(1)
assert(ns.plan == plan, "un message abîmé a changé le trajet")

-- 3. Plus de nouvelles de la guide : retour à ton propre trajet.
Advance(200)
assert(not ns.plan.group, "toujours en train de suivre un guide muet")

-- 4. Partage coupé : annonce envoyée, trajet perso.
SENT = {}
SlashCmdList.ITINERAIRE("groupe off")
Advance(3)
local bye = LastSent("S")
assert(bye and bye:match("^1#0#"), "annonce « je ne partage plus » absente")
assert(not ns.Group.Active() and not ns.plan.groupMode, "partage encore actif")

-- 5. Versions (même sans partage) : un équipier a une version plus récente -> prévenu une fois ;
--    une plus ancienne -> on lui envoie la nôtre ; message abîmé -> ignoré.
PRINTED = {}
Deliver("Alix", "V", "9.9.9")
Advance(1)
local warned = 0
for _, m in ipairs(PRINTED) do
	if m:find("Alix a Itinéraire 9%.9%.9") then warned = warned + 1 end
end
assert(warned == 1, "pas prévenu de la version plus récente")
Deliver("Alix", "V", "9.9.9")
Advance(1)
for _, m in ipairs(PRINTED) do
	if m:find("Alix a Itinéraire 9%.9%.9") then warned = warned + 1 end
end
assert(warned == 2, "prévenu deux fois pour la même version")
Advance(61)
SENT = {}
Deliver("Alix", "V", "0.1.0")
Advance(1)
assert(LastSent("V") == VERSIONS.Itineraire, "notre version n'est pas renvoyée à un équipier en retard")
Deliver("Alix", "V", "1.2.3|cffff0000x")
Deliver("Alix", "V", string.rep("9", 40))
Advance(1)
print("OK groupe")
