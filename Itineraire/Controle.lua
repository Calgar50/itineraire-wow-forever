-- Itinéraire : contrôle en jeu (/iti controle). Chaque partie de l'addon est vérifiée POUR DE VRAI dans ton jeu
-- (API de Forever, addons liés, données) ; le compte rendu (avec le rapport complet) est prêt à copier.
-- Lecture seule : rien n'est changé, rien n'est cliqué.
local _, ns = ...
local Controle = {}
ns.Controle = Controle

local OK, WATCH, BROKEN = "ok", "attention", "panne"
local LABEL = { ok = "[OK]", attention = "[À SURVEILLER]", panne = "[EN PANNE]" }

local function Call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c = pcall(fn, ...)
	if ok then
		return a, b, c
	end
	return nil
end

local function Secs(s)
	s = tonumber(s) or 0
	if s >= 3600 then
		return string.format("%d h %02d", math.floor(s / 3600), math.floor(s % 3600 / 60))
	elseif s >= 60 then
		return string.format("%d min %02d", math.floor(s / 60), math.floor(s % 60))
	end
	return math.floor(s) .. " s"
end

local CHECKS = {}
local function Check(name, fn)
	CHECKS[#CHECKS + 1] = { name = name, fn = fn }
end

Check("Fichiers de l'addon", function()
	local missing = {}
	for flag, file in pairs({ groupMissing = "Group.lua", gearMissing = "Gear.lua", piloteMissing = "Pilote.lua",
		autoMissing = "Autonomie.lua", djMissing = "DungeonJournal.lua", monteeMissing = "Montee.lua",
		monteeUIMissing = "MonteeUI.lua", triMissing = "Tri.lua" }) do
		if ns[flag] then
			missing[#missing + 1] = file
		end
	end
	if #missing > 0 then
		table.sort(missing)
		return BROKEN, "pas chargés : " .. table.concat(missing, ", ") .. " -> quitte et relance complètement WoW"
	end
	return OK, "tous chargés (version " .. tostring(ns.AddonVersion and ns.AddonVersion("Itineraire") or "?") .. ")"
end)

Check("Questie", function()
	if not (ns.ready and ns.Data.Modules()) then
		return BROKEN, "pas prêt (Itinéraire attend Questie et QuestieDB)"
	end
	local log = ns.Data.ReadLog()
	return OK, string.format("prêt · Questie %s, QuestieDB %s · %d quête(s) au journal", tostring(ns.AddonVersion("Questie") or "?"),
		tostring(ns.AddonVersion("QuestieDB") or "?"), #log)
end)

Check("Base de quêtes (frise, région suivante)", function()
	local state, count, zones = ns.Montee.IndexState()
	if state == "prêt" then
		return count > 0 and OK or WATCH, string.format("%d quêtes pour ta classe et ta race, dans %d zones", count or 0, zones or 0)
	end
	pcall(ns.Montee.BuildIndex)
	return WATCH, tostring(state) .. " (relance le contrôle dans une minute)"
end)

Check("Shortest Path (flèche, temps de trajet)", function()
	local api = ns.Geo.SPApi()
	if not api then
		return BROKEN, "absent : simple repère Blizzard à la place de la flèche"
	end
	local text = "API " .. tostring(api.version) .. "." .. tostring(api.minor or 0) .. ", ShortestPathForever "
		.. tostring(ns.AddonVersion("ShortestPathForever") or "?")
	local first = ns.plan and ns.plan.order and ns.plan.order[1]
	if first then
		local est = ns.Geo.Estimate(ns.Geo.Player(), first)
		if type(est) ~= "number" then
			return WATCH, text .. " · pas d'estimation vers l'étape 1 (même carte ? hors ligne de vue ?)"
		end
		text = text .. " · étape 1 à " .. Secs(est)
	end
	local ok, journey = pcall(api.Journey)
	if ok and type(journey) == "table" then
		text = text .. " · trajet en cours : " .. tostring(journey.owner or "le tien (à la main)")
	end
	return OK, text
end)

Check("Trajet", function()
	local plan = ns.plan
	if not plan then
		return BROKEN, "pas encore calculé"
	end
	local age = ns.planAt and (GetTime() - ns.planAt) or nil
	local text = string.format("%d étape(s) · %s de trajet + %s sur place%s", #plan.order, Secs(plan.travel), Secs(plan.workTime),
		age and (" · calculé il y a " .. Secs(age)) or "")
	if plan.warnings and #plan.warnings > 0 then
		return WATCH, text .. " · avertissement : " .. tostring(plan.warnings[1])
	end
	local unknown = plan.side and plan.side.unknown or {}
	if #unknown > 0 then
		local ids = {}
		for k = 1, math.min(5, #unknown) do
			ids[#ids + 1] = tostring(unknown[k].q and unknown[k].q.id) .. " (" .. tostring(unknown[k].what) .. ")"
		end
		return WATCH, text .. " · positions inconnues : " .. table.concat(ids, ", ")
	end
	return OK, text
end)

Check("Flèche (dernier envoi)", function()
	local g = ns.guideState
	if not g then
		return WATCH, "rien envoyé pour l'instant"
	end
	return OK, tostring(g.result) .. " · " .. tostring(g.stops) .. " étape(s) à " .. tostring(g.at)
end)

Check("Niveau de ta zone", function()
	local p = ns.Geo.Player()
	if not p.map then
		return WATCH, "position inconnue (instance ?)"
	end
	local low, high = ns.Data.ZoneLevels(p.map)
	local name = ns.Geo.ZoneName(ns.Geo.Zone(p.map) or p.map)
	if not low then
		return WATCH, name .. " : niveaux inconnus (capitale ou zone nouvelle) : rien n'y est évité"
	end
	return OK, string.format("%s : niveaux %d-%d", name, low, high)
end)

Check("Pierre de foyer", function()
	local h = ns.Data.Hearth()
	if not h then
		return WATCH, "pas dans tes sacs"
	end
	local text = "liée à " .. tostring(h.name or "?") .. ((h.ready or 0) > 0 and (" · prête dans " .. Secs(h.ready)) or " · prête")
	if not h.point then
		return WATCH, text .. " · lieu exact inconnu (Shortest Path le lit à ta prochaine liaison chez un aubergiste)"
	end
	return OK, text
end)

Check("Aubergistes, marchands, maîtres", function()
	local inns = #ns.Data.TownsfolkPoints("Innkeeper")
	local repair = #ns.Data.TownsfolkPoints("Repair")
	local trainers = #ns.Data.TownsfolkPoints("Class Trainer")
	local text = string.format("%d aubergistes, %d réparateurs, %d maîtres de ta classe", inns, repair, trainers)
	return (inns > 0 and repair > 0 and trainers > 0) and OK or WATCH, text
end)

Check("Talents (API de Forever)", function()
	if ns.autoMissing then
		return BROKEN, "Autonomie.lua pas chargé"
	end
	local config = C_ClassTalents and Call(C_ClassTalents.GetActiveConfigID)
	if type(config) ~= "number" then
		return WATCH, "pas de configuration de talents lisible (avant le niveau 10 ?)"
	end
	local trees = ns.Auto.Trees()
	if type(trees) ~= "table" or #trees == 0 then
		return WATCH, "arbres illisibles"
	end
	local parts = {}
	for tab, t in ipairs(trees) do
		parts[#parts + 1] = tostring(t.name or tab) .. " " .. tostring(t.points)
	end
	return OK, table.concat(parts, " / ") .. " · libres " .. tostring(trees.free) .. " · " .. tostring(ns.Auto.TalentsText())
end)

Check("Équipement (rôle, notes)", function()
	if ns.gearMissing then
		return BROKEN, "Gear.lua pas chargé"
	end
	local role, why = ns.Gear.Role()
	local text = "rôle " .. tostring(role) .. " (" .. tostring(why) .. ")"
	local noted, failed = 0, 0
	for _, slot in ipairs({ 1, 5, 7, 16, 17 }) do
		local link = GetInventoryItemLink and Call(GetInventoryItemLink, "player", slot)
		if link then
			local ok, score = pcall(ns.Gear.Evaluate, link)
			if ok then
				noted = noted + 1
			else
				failed = failed + 1
				text = text .. " · erreur emplacement " .. slot .. " : " .. tostring(score):sub(1, 80)
			end
		end
	end
	text = text .. string.format(" · %d objet(s) portés notés sans erreur", noted)
	return failed == 0 and OK or BROKEN, text
end)

Check("Barres d'action", function()
	if ns.autoMissing then
		return BROKEN, "Autonomie.lua pas chargé"
	end
	local line = tostring(ns.Auto.ReportLine() or "")
	local bars = line:match("barres d'action ([^\n]*)") or "?"
	if bars:find("refus") or bars:find("erreur") then
		return WATCH, bars
	end
	return OK, bars
end)

Check("Pilote automatique", function()
	if ns.piloteMissing then
		return BROKEN, "Pilote.lua pas chargé"
	end
	local line = tostring(ns.Pilote.ReportLine() or ""):gsub("\n.*", "")
	if line:find("BLOQUÉ") then
		return WATCH, line .. " (le jeu a bloqué une partie : elle est coupée pour la session)"
	end
	return OK, line
end)

Check("DungeonJournal", function()
	local line = tostring(ns.DJ.ReportLine() or "?")
	return ns.DJ.NS() and OK or WATCH, line
end)

Check("Métiers (minage, forge)", function()
	local mining, forge = ns.Montee.Skill(186), ns.Montee.Skill(164)
	if not (mining or forge) then
		return WATCH, "aucun métier lu (ouvre une fois ta fenêtre des métiers si tu en as)"
	end
	local parts = {}
	if mining then
		local points = #ns.Montee.OrePoints(ns.Montee.ORES[1])
		parts[#parts + 1] = string.format("minage %d/%d (%d emplacements de cuivre connus)", mining.rank or 0, mining.max or 0, points)
	end
	if forge then
		local recipes = ns.Montee.ForgeRecipes()
		parts[#parts + 1] = string.format("forge %d/%d (%d recette(s) qui font monter)", forge.rank or 0, forge.max or 0,
			recipes and #recipes or 0)
	end
	return OK, table.concat(parts, " · ")
end)

Check("Soirée", function()
	local s = ns.SoireeActive and ns.SoireeActive()
	if not s then
		return OK, "pas de soirée en cours (/iti soiree 1h30 pour en lancer une)"
	end
	local so = ns.plan and ns.plan.soiree
	return so and OK or WATCH, string.format("en cours jusqu'à %s%s", date("%H:%M", s.fin),
		so and string.format(" · %d quête(s) ce soir · fin à l'étape %s", so.chosen or 0, tostring(so.innStep or "?")) or " · pas encore appliquée au trajet")
end)

Check("Mise à jour automatique", function()
	local info = ns.InstallerInfo()
	if not info then
		return WATCH, "installé à la main : pas de mise à jour automatique"
	end
	local text = ns.InstallerText()
	if info.version < ns.INSTALLER_WANTED or not info.auto then
		return WATCH, text
	end
	return OK, text
end)

Check("Erreurs enregistrées", function()
	local list = ns.char and ns.char.errors or {}
	if #list == 0 then
		return OK, "aucune"
	end
	local last = list[#list]
	return WATCH, string.format("%d (dernière %s : %s)", #list, tostring(last.time), tostring(last.text):sub(1, 160))
end)

-- Lance tous les contrôles : rend le texte du compte rendu, et les nombres ok / à surveiller / en panne.
function Controle.Run()
	local lines, counts = {}, { ok = 0, attention = 0, panne = 0 }
	for _, c in ipairs(CHECKS) do
		local ok, status, text = pcall(c.fn)
		if not ok then
			status, text = BROKEN, "erreur Lua : " .. tostring(status):sub(1, 200)
		end
		status = LABEL[status] and status or WATCH
		counts[status] = counts[status] + 1
		lines[#lines + 1] = string.format("%s %s : %s", LABEL[status], c.name, tostring(text or ""))
	end
	local head = string.format("=== Contrôle en jeu Itinéraire %s · %s ===", tostring(ns.AddonVersion and ns.AddonVersion("Itineraire") or "?"),
		date("%Y-%m-%d %H:%M:%S"))
	local summary = string.format("%d vérifications : %d OK · %d à surveiller · %d en panne", #CHECKS, counts.ok,
		counts.attention, counts.panne)
	table.insert(lines, 1, summary)
	table.insert(lines, 1, head)
	local okR, report = pcall(ns.ReportText)
	lines[#lines + 1] = ""
	lines[#lines + 1] = okR and report or ("(rapport impossible : " .. tostring(report) .. ")")
	return table.concat(lines, "\n"), counts, summary
end

function Controle.Show()
	local text, counts, summary = Controle.Run()
	ns.Print("contrôle en jeu : " .. summary .. (counts.panne + counts.attention > 0 and " (détail dans la fenêtre)" or "."))
	ns.UI.ShowCopyBox("Contrôle en jeu", "Tout a été vérifié dans ton jeu. Ctrl+C pour copier (déjà sélectionné), puis colle-le dans ton message.", text)
	return text, counts
end
