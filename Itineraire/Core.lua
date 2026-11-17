-- Itinéraire : démarrage, événements, calcul en tâche de fond, commandes.
local ADDON, ns = ...
ns.OWNER = "Itineraire"

-- Group.lua est un nouveau fichier : après une simple mise à jour + /reload, le jeu peut ne pas
-- l'avoir chargé (il faut relancer WoW). On remplace alors le module par une coquille vide.
local function Shell()
	return setmetatable({}, { __index = function()
		return function()
			return nil
		end
	end })
end
if not ns.Group then
	ns.groupMissing = true
	ns.Group = Shell()
end
-- Idem pour l'équipement (Gear.lua, GearUI.lua : nouveaux en 1.9.0).
if not ns.Gear then
	ns.gearMissing = true
	ns.Gear = Shell()
end
if not ns.GearUI then
	ns.GearUI = Shell()
end
-- Pilote.lua : nouveau en 2.1.0.
if not ns.Pilote then
	ns.piloteMissing = true
	ns.Pilote = Shell()
end

-- Dépôt public d'Itinéraire (paquet, installateur, nouveautés).
ns.HOME = "github.com/Calgar50/itineraire-wow-forever"
-- Version de l'installateur attendue par cette version d'Itinéraire (Installateur.lua est écrit par lui).
ns.INSTALLER_WANTED = 2
-- Nouveautés affichées une fois après une mise à jour (pas de flèches Unicode : police du jeu incertaine).
ns.NEWS = {
	["2.1.0"] = {
		"PILOTE AUTOMATIQUE (comme les guides « autopilot ») : il prend et rend les quêtes, prend le vol prévu chez le maître de vol, passe les cinématiques, répare et vend les objets gris, apprend tes techniques chez le maître de classe.",
		"Bouton de l'objet de quête à utiliser maintenant (raccourci clavier dans Échap > Options > Raccourcis > Itinéraire).",
		"MAJ (Shift) en parlant à un PNJ : tu reprends la main. /iti pilote pour l'arrêter ou le relancer ; réglages : /iti reglages > Pilote.",
	},
	["2.0.0"] = {
		"Fusion des données des addons Forever : butins de TOUS les donjons et raids (boss par boss), recettes de tes métiers, vendeurs de Forever.",
		"Équipement, onglet Donjons : quel donjon faire pour ton équipement, et « Y aller » vers son entrée.",
		"Bulle des objets : « Itinéraire : +12 % pour toi » partout (sacs, butin, hôtel des ventes).",
		"Note des objets revue (poids par classe, armure en vie effective, armes) et récompense de quête marquée sans rien toucher à la fenêtre du jeu.",
		"Quêtes que Questie ne sait pas placer : Itinéraire prend le repère du jeu (et DonData s'il est installé).",
	},
	["1.9.0"] = {
		"Récompenses de quête : la meilleure pour ton rôle est mise en avant (et présélectionnée) au rendu.",
		"Équipement (/iti equipement) : tes améliorations à ton niveau, d'où elles viennent, et « Y aller » pour les ajouter au trajet.",
		"Mises à jour automatiques avec l'installateur : Itinéraire, Questie et Shortest Path restent à jour tout seuls.",
		"Les quêtes d'une autre classe ou d'une autre race ne sont plus jamais proposées.",
	},
}
ns.session = { skipped = {}, pinned = nil, previous = nil, paused = false, pauseWhy = nil, focus = nil, expanded = false }

local PREFIX = "|cff4fc3f7Itinéraire|r : "
function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
end

local DEFAULT_DB = {
	ui = { point = "LEFT", rel = "LEFT", x = 20, y = 120, shown = true },
	includeDungeons = true, -- aucune quête écartée par défaut
	includePickups = true, -- quêtes à prendre sur le trajet (et suites)
	includeServices = true, -- arrêt réparer / vendre quand il faut
	includeTrainer = true, -- visite au maître de classe aux niveaux pairs
	useHearth = true, -- conseils pierre de foyer
	groupShare = false, -- partage du trajet avec le groupe (2 à 5 joueurs)
	regionMode = true, -- finir la région où tu es (avec ses quêtes à prendre) avant d'en sortir
	maxStops = 40,
}
local DEFAULT_CHAR = {}

local function Merge(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then
				dst[k] = {}
			end
			Merge(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

-------------------------------------------------------------------------------
-- Calcul en tâche de fond (quelques millisecondes par image, jamais de saccade)
-------------------------------------------------------------------------------
local BUDGET_MS = 6
local job, dirty, timer
local deadline = 0
local runner = CreateFrame("Frame")
runner:Hide()

local function Yield()
	if coroutine.running() and debugprofilestop() > deadline then
		coroutine.yield()
	end
end

local lastError
local MAX_ERRORS = 8
local function OnError(err)
	err = tostring(err)
	if err ~= lastError then
		lastError = err
		ns.Print("|cffff5555erreur de calcul|r : " .. err:sub(1, 200))
	end
	if ns.char then
		local entry = { time = date("%Y-%m-%d %H:%M:%S"), text = err:sub(1, 600) }
		ns.char.lastError = entry
		-- Les dernières erreurs (pour /iti rapport), la plus récente à la fin, sans doublon d'affilée.
		local list = type(ns.char.errors) == "table" and ns.char.errors or {}
		ns.char.errors = list
		local last = list[#list]
		if last and last.text == entry.text then
			last.time, last.count = entry.time, (last.count or 1) + 1
		else
			list[#list + 1] = entry
		end
		while #list > MAX_ERRORS do
			table.remove(list, 1)
		end
	end
end
ns.OnError = OnError

runner:SetScript("OnUpdate", function(self)
	if not job then
		self:Hide()
		return
	end
	deadline = debugprofilestop() + BUDGET_MS
	local ok, err = coroutine.resume(job)
	if not ok then
		job = nil
		self:Hide()
		OnError(err)
		return
	end
	if coroutine.status(job) == "dead" then
		job = nil
		self:Hide()
		if dirty then
			dirty = false
			ns.RequestPlan("dirty", 0.3)
		end
	end
end)

-------------------------------------------------------------------------------
-- Rythme mesuré du joueur : les temps deviennent plus justes au fil du jeu
-------------------------------------------------------------------------------
local RATE_TYPES = { monster = true, item = true, object = true, killcredit = true }
local MIN_SAMPLES = 3
local MAX_TARGETS = 300 -- monstres / objets mémorisés au plus (les plus anciens partent)
local ZONE_SHRINK = 3 -- une zone peu mesurée reste proche du rythme général

local function Calib()
	local c = ns.char.calib
	if type(c) ~= "table" then
		c = {}
		ns.char.calib = c
	end
	for _, key in ipairs({ "work", "travel", "targets", "slots", "zones" }) do
		if type(c[key]) ~= "table" then
			c[key] = {}
		end
	end
	return c
end

-- Moyenne glissante (les dernières mesures comptent le plus), bornée contre les valeurs absurdes.
-- `d` = écart moyen aux mesures : il donne les fourchettes (« 12-15 min »).
local function Learn(entry, sample, lo, hi)
	sample = math.max(lo, math.min(hi, sample))
	if (entry.n or 0) == 0 or type(entry.v) ~= "number" then
		entry.v = sample
	else
		local dev = math.abs(sample - entry.v)
		entry.d = type(entry.d) == "number" and (entry.d * 0.8 + dev * 0.2) or dev
		entry.v = entry.v * 0.8 + sample * 0.2
	end
	entry.n = (entry.n or 0) + 1
end

-- Secondes par monstre / objet / utilisation, une fois assez de mesures.
function ns.Rates()
	local rates = {}
	for kind, e in pairs(Calib().work) do
		if type(e) == "table" and (e.n or 0) >= MIN_SAMPLES and type(e.v) == "number" then
			rates[kind] = e.v
		end
	end
	return rates
end

-- Mesures par monstre / objet précis (« monster:3245 ») et par objectif de quête (« 882:1 ») : copiées,
-- le calcul en tâche de fond ne doit pas voir la table changer sous lui.
local function Copy(list)
	local out = {}
	for key, e in pairs(list) do
		if type(e) == "table" and type(e.v) == "number" and (e.n or 0) > 0 then
			out[key] = { v = e.v, n = e.n }
		end
	end
	return out
end

function ns.TargetRates()
	return Copy(Calib().targets)
end

function ns.SlotRates()
	return Copy(Calib().slots)
end

-- Facteur sur les temps de marche (1 = comme prévu).
function ns.Pace()
	local t = Calib().travel
	return (t.n or 0) >= MIN_SAMPLES and type(t.v) == "number" and t.v or 1
end

-- Facteur de marche par zone (relief, routes…), rapproché du facteur général tant qu'il y a peu de mesures.
function ns.ZonePace()
	local general, out = ns.Pace(), {}
	for zone, e in pairs(Calib().zones) do
		if type(zone) == "number" and type(e) == "table" and type(e.v) == "number" and (e.n or 0) > 0 then
			out[zone] = (e.n * e.v + ZONE_SHRINK * general) / (e.n + ZONE_SHRINK)
		end
	end
	return out
end

-- Écart relatif typique de tes temps (0,2 = ±20 %) : sur place et en déplacement.
local function Relative(e)
	if type(e) == "table" and (e.n or 0) >= MIN_SAMPLES and type(e.d) == "number" and type(e.v) == "number" and e.v > 0 then
		return math.max(0.08, math.min(0.6, e.d / e.v))
	end
	return nil
end

function ns.Spread()
	local c = Calib()
	local sum, weight = 0, 0
	for _, e in pairs(c.work) do
		local r = Relative(e)
		if r then
			sum, weight = sum + r * e.n, weight + e.n
		end
	end
	local travel = Relative(c.travel)
	-- Erreur « d'ensemble » (tout le trajet plus lent ou plus rapide que prévu) : grande tant que ton
	-- rythme n'est pas mesuré, petite ensuite.
	local measured = (weight > 0 and 1 or 0) + (travel and 1 or 0)
	return { work = weight > 0 and sum / weight or 0.35, travel = travel or 0.25, measured = measured > 0,
		system = measured == 2 and 0.08 or measured == 1 and 0.14 or 0.2 }
end

-- Ce qu'on chasse pour un objectif du journal (« monster:3245 »), d'après Questie.
local function TargetOf(questId, index, kind)
	local ok, quest = pcall(ns.Data.Quest, questId)
	if ok and quest then
		local ok2, key = pcall(ns.Data.ObjectiveTarget, quest, index, kind)
		return ok2 and key or nil
	end
	return nil
end

local function PruneTargets(targets)
	local count, oldest, oldestKey = 0, nil, nil
	for key, e in pairs(targets) do
		count = count + 1
		local t = type(e) == "table" and e.t or 0
		if not oldest or t < oldest then
			oldest, oldestKey = t, key
		end
	end
	if count > MAX_TARGETS and oldestKey then
		targets[oldestKey] = nil
	end
end

-- Temps entre deux progrès d'un même objectif (« 3/8 » puis « 4/8 ») : le vrai rythme de chasse.
local progress = {}
function ns.TrackProgress()
	if not (ns.char and C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then
		return
	end
	local c = Calib()
	local now, seen, work = GetTime(), {}, c.work
	for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and info.questID then
			local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, info.questID)
			for idx, o in ipairs(ok and objectives or {}) do
				local key = info.questID .. ":" .. idx
				seen[key] = true
				local have = tonumber(o.numFulfilled) or 0
				local prev = progress[key]
				if prev and have > prev.have and RATE_TYPES[o.type] then
					local gap = now - prev.t
					-- Le 1er progrès après l'arrivée compte le trajet : on ne mesure qu'entre deux progrès.
					if prev.counted and gap <= 300 then
						local sample = gap / (have - prev.have)
						work[o.type] = type(work[o.type]) == "table" and work[o.type] or {}
						Learn(work[o.type], sample, 4, 180)
						-- Le même objectif (cette quête) et la même cible (ce monstre, cet objet) : plus précis.
						c.slots[key] = type(c.slots[key]) == "table" and c.slots[key] or {}
						Learn(c.slots[key], sample, 4, 180)
						local target = TargetOf(info.questID, idx, o.type)
						if target then
							c.targets[target] = type(c.targets[target]) == "table" and c.targets[target] or {}
							Learn(c.targets[target], sample, 4, 180)
							c.targets[target].t = time and time() or now
							PruneTargets(c.targets)
						end
					end
					progress[key] = { have = have, t = now, counted = true }
				elseif not prev or have ~= prev.have then
					progress[key] = { have = have, t = now, counted = false }
				end
			end
		end
	end
	for key in pairs(progress) do
		if not seen[key] then
			progress[key] = nil
		end
	end
	-- Objectifs qui ont quitté le journal : leur mesure ne sert plus (la cible, elle, reste apprise).
	-- (Journal vu vide = écran de chargement : on ne touche à rien.)
	if next(seen) then
		for key in pairs(c.slots) do
			if not seen[key] then
				c.slots[key] = nil
			end
		end
	end
end

-- Temps réel pour rejoindre l'étape en cours, comparé au temps prévu (trajets à pied seulement).
local trip
function ns.TrackTravel()
	local plan = ns.plan
	local s = plan and plan.order and plan.order[1]
	if not s or ns.session.paused or (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) then
		trip = nil
		return
	end
	local d = ns.Geo.Yards(ns.Geo.Player(), s)
	local near = d and d <= math.max(s.radius or 0, 25)
	if not trip or trip.key ~= s.key then
		-- Le facteur utilisé pour cette prévision (celui de la zone d'arrivée), pour en retrouver la mesure brute.
		trip = { key = s.key, start = GetTime(), predicted = s.legModel or s.leg, walk = s.legWalk, away = not near,
			pace = ns.Geo.PaceAt and ns.Geo.PaceAt(s) or ns.Pace(), zone = ns.Geo.Zone(s.map) }
		return
	end
	if near and trip.away and not trip.done then
		trip.done = true
		local elapsed = GetTime() - trip.start
		if trip.walk and trip.predicted and trip.predicted >= 30 and elapsed >= 10 and elapsed <= trip.predicted * 3 then
			local raw = elapsed / trip.predicted * trip.pace
			local c = Calib()
			Learn(c.travel, raw, 0.6, 2.5)
			if type(trip.zone) == "number" then
				c.zones[trip.zone] = type(c.zones[trip.zone]) == "table" and c.zones[trip.zone] or {}
				Learn(c.zones[trip.zone], raw, 0.6, 2.5)
			end
		end
	end
end

local function Factor(v)
	return (string.format("%.2f", v):gsub("%.", ","))
end

function ns.PaceText()
	local c = Calib()
	local parts = {}
	local t = c.travel
	if (t.n or 0) > 0 then
		local zones = 0
		for _ in pairs(c.zones) do
			zones = zones + 1
		end
		parts[#parts + 1] = "déplacements x" .. Factor(t.v) .. " (" .. t.n .. " mesure" .. (t.n > 1 and "s" or "")
			.. (zones > 0 and (", " .. zones .. " zone" .. (zones > 1 and "s" or "")) or "") .. ")"
	end
	local names = { monster = "par monstre", item = "par objet obtenu", object = "par objet utilisé", killcredit = "par objectif" }
	for _, kind in ipairs({ "monster", "item", "object", "killcredit" }) do
		local e = c.work[kind]
		if type(e) == "table" and (e.n or 0) > 0 then
			parts[#parts + 1] = string.format("%d s %s (%d)", math.floor(e.v + 0.5), names[kind], e.n)
		end
	end
	local targets = 0
	for _ in pairs(c.targets) do
		targets = targets + 1
	end
	if targets > 0 then
		parts[#parts + 1] = targets .. " cible" .. (targets > 1 and "s" or "") .. " apprise" .. (targets > 1 and "s" or "")
	end
	if #parts == 0 then
		return nil
	end
	return table.concat(parts, " · ")
end

-- Le détail (pour /iti rythme et le rapport) : zones et cibles les plus mesurées.
function ns.PaceDetails(limit)
	local c = Calib()
	local lines = {}
	local zones = {}
	for zone, e in pairs(c.zones) do
		if type(e) == "table" and type(e.v) == "number" then
			zones[#zones + 1] = { zone = zone, e = e }
		end
	end
	table.sort(zones, function(a, b)
		return (a.e.n or 0) > (b.e.n or 0)
	end)
	local zp = ns.ZonePace()
	for k = 1, math.min(#zones, limit or 6) do
		local z = zones[k]
		local name = ns.Geo.ZoneName(z.zone)
		lines[#lines + 1] = string.format("zone %s : x%s (%d mesure%s, utilisé x%s)", name ~= "" and name or tostring(z.zone),
			Factor(z.e.v), z.e.n or 0, (z.e.n or 0) > 1 and "s" or "", Factor(zp[z.zone] or z.e.v))
	end
	local targets = {}
	for key, e in pairs(c.targets) do
		if type(e) == "table" and type(e.v) == "number" then
			targets[#targets + 1] = { key = key, e = e }
		end
	end
	table.sort(targets, function(a, b)
		return (a.e.n or 0) > (b.e.n or 0)
	end)
	for k = 1, math.min(#targets, limit or 6) do
		local t = targets[k]
		local ok, name = pcall(ns.Data.TargetName, t.key)
		lines[#lines + 1] = string.format("%s : %d s l'unité (%d mesure%s)", ok and name or t.key, math.floor(t.e.v + 0.5),
			t.e.n or 0, (t.e.n or 0) > 1 and "s" or "")
	end
	return lines
end

function ns.ResetPace()
	ns.char.calib = nil
	progress, trip = {}, nil
end

-- Temps restant vers l'étape en cours selon Shortest Path (qui a cherché le vrai chemin).
local function FirstLeg()
	local api = ns.Geo.SPApi()
	local key = ns.session.previous
	if not (api and api.Journey and key) then
		return nil
	end
	local ok, journey = pcall(api.Journey)
	if ok and type(journey) == "table" and journey.owner == ns.OWNER and type(journey.secondsLeft) == "number"
		and journey.secondsLeft > 0 then
		return { key = key, seconds = journey.secondsLeft }
	end
	return nil
end

-- Quêtes proposées au calcul précédent (elles restent proposées tant qu'elles valent le coup).
local function PreviousCandidates()
	local ids = {}
	for _, q in ipairs(ns.plan and ns.plan.candidates or {}) do
		ids[q.id] = true
	end
	return ids
end

local function Grouped()
	return (IsInGroup and IsInGroup() and GetNumGroupMembers and (GetNumGroupMembers() or 0) >= 2) and true or false
end

local function Options()
	-- Guide d'un groupe : un trajet pour tout le monde, sans rien de personnel.
	local guide = ns.Group and ns.Group.IsGuide()
	local okGear, gear = pcall(ns.Gear.PlanOptions)
	gear = okGear and type(gear) == "table" and gear or {}
	return {
		gearGoals = gear.goals,
		wantedQuests = gear.wanted,
		gearQuests = gear.quests,
		groupMode = guide or nil,
		groupQuests = guide and ns.Group.QuestsForPlan() or nil,
		groupSize = guide and ns.Group.Size() or nil,
		me = ns.Group and ns.Group.Me() or nil,
		trainedAt = ns.char and ns.char.trainedAt or nil,
		regionMode = ns.db.regionMode ~= false,
		turninOnly = ns.session.turnins or nil,
		includeTrainer = ns.db.includeTrainer ~= false,
		useHearth = ns.db.useHearth ~= false,
		skipped = ns.session.skipped,
		pinned = ns.session.pinned,
		previous = ns.session.previous,
		includeDungeons = ns.db.includeDungeons,
		includePickups = ns.db.includePickups,
		includeServices = ns.db.includeServices,
		serviceDoneAt = ns.session.serviceDoneAt,
		focus = ns.session.focus,
		rates = ns.Rates(),
		targets = ns.TargetRates(),
		slots = ns.SlotRates(),
		pace = ns.Pace(),
		zonePace = ns.ZonePace(),
		grouped = Grouped() or guide,
		firstLeg = FirstLeg(),
		prevCandidates = PreviousCandidates(),
		prevPromoted = ns.plan and ns.plan.promotedIds or nil,
	}
end

-- Réparer / vendre : on ne recalcule que si le besoin change (sacs et usure bougent tout le temps).
local lastService
local function CheckService()
	if not ns.db then
		return
	end
	local sig = ns.Planner.ServiceSignature(Options())
	if sig ~= lastService then
		lastService = sig
		ns.RequestPlan("équipement", 1)
	end
end

local lastPos
function ns.OnPlan(plan)
	if ns.Group and ns.Group.Following() then
		return -- un calcul lancé avant de recevoir le trajet du guide : ignoré
	end
	ns.plan = plan
	local first = plan.order[1]
	ns.session.previous = first and first.key
	if ns.session.pinned then
		local still = false
		for _, s in ipairs(plan.order) do
			still = still or s.key == ns.session.pinned
		end
		if not still then
			ns.session.pinned = nil
		end
	end
	lastPos = plan.player
	if ns.session.focus and not plan.focusInLog then
		local title = ns.session.focusTitle
		ns.SetFocus(nil)
		ns.Print((title and ("« " .. title .. " »") or "La quête suivie") .. " n'est plus dans ton journal : retour au trajet complet.")
		return
	end
	ns.session.focusTitle = plan.focusTitle or ns.session.focusTitle
	plan.groupMode = ns.Group and ns.Group.IsGuide() or nil
	plan.groupSize = plan.groupMode and ns.Group.Size() or nil
	if plan.turninOnly and #plan.order == 0 then
		-- Tout est rendu : retour au trajet complet.
		ns.session.turnins = nil
		ns.Print("tout est rendu : retour au trajet complet.")
		ns.UI.SetTurnins(false)
		ns.RequestPlan("rendus", 0)
		return
	end
	ns.ShowPlan(plan)
	if ns.Group then
		local ok, err = pcall(ns.Group.OnPlan, plan)
		if not ok then
			OnError("groupe : " .. tostring(err))
		end
	end
end

-- La flèche d'abord (le plus important), puis le bandeau et la fenêtre : un souci d'affichage ne bloque
-- jamais le guidage.
function ns.ShowPlan(plan)
	ns.planAt = GetTime()
	for _, warning in ipairs(plan.warnings or {}) do
		OnError(warning)
	end
	local ok, err = pcall(ns.Guide.Apply, plan)
	if not ok then
		OnError("flèche : " .. tostring(err))
	end
	ok, err = pcall(ns.UI.RefreshBanner, plan)
	if not ok then
		OnError("bandeau : " .. tostring(err))
	end
	ok, err = pcall(ns.UI.Refresh, plan)
	if not ok then
		OnError("fenêtre : " .. tostring(err))
	end
	pcall(ns.Pilote.OnPlan) -- (bouton de l'objet de quête de l'étape)
end

-- Trajet reçu du guide du groupe.
function ns.OnGroupPlan(plan)
	ns.plan = plan
	local first = plan.order[1]
	ns.session.previous = first and first.key
	ns.ShowPlan(plan)
end

-- Empreinte rapide du journal : évite de tout recalculer quand QUEST_LOG_UPDATE ne change rien.
local lastLogSig
local function LogSignature()
	local parts = {}
	local n = C_QuestLog.GetNumQuestLogEntries() or 0
	for i = 1, n do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and info.questID then
			parts[#parts + 1] = info.questID
			for _, o in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
				parts[#parts + 1] = (o.numFulfilled or 0) .. (o.finished and "f" or "")
			end
		end
	end
	return table.concat(parts, ",")
end

local pendingReason
function ns.StartPlan()
	if not ns.ready then
		return
	end
	if ns.Group and ns.Group.Following() then
		return -- on suit le trajet du guide
	end
	if job then
		dirty = true
		return
	end
	local okSig, sig = pcall(LogSignature)
	if pendingReason == "QUEST_LOG_UPDATE" and okSig and sig == lastLogSig and ns.plan then
		return
	end
	lastLogSig = okSig and sig or nil
	local opts = Options()
	job = coroutine.create(function()
		local plan = ns.Planner.Build(opts, Yield)
		ns.OnPlan(plan)
	end)
	runner:Show()
end

function ns.RequestPlan(reason, delay)
	if not ns.ready then
		return
	end
	if job then
		dirty = true
		return
	end
	if timer then
		timer:Cancel()
		-- Une demande « forte » (rendu, déplacement…) ne doit pas être rétrogradée en simple mise à jour.
		if pendingReason ~= "QUEST_LOG_UPDATE" then
			reason = pendingReason
		end
	end
	pendingReason = reason
	timer = C_Timer.NewTimer(delay or 1, function()
		timer = nil
		ns.StartPlan()
	end)
end

-------------------------------------------------------------------------------
-- États
-------------------------------------------------------------------------------
function ns.SetPaused(paused, why)
	ns.session.paused = paused and true or false
	ns.session.pauseWhy = paused and why or nil
	ns.session.idleSince = nil
	if not paused then
		ns.Guide.Reset()
	end
	if ns.UI then
		ns.UI.SetStatus(ns.StatusText())
		pcall(ns.UI.RefreshBanner, ns.plan)
	end
end

-- Quête suivie : elle passe avant tout le reste (objectifs puis rendu), quels que soient les filtres.
local lastQuestieFocus
local function QuestieTracker()
	local ok, utils = pcall(QuestieLoader.ImportModule, QuestieLoader, "TrackerUtils")
	return ok and utils or nil
end

function ns.SetFocus(questId, source)
	if questId == ns.session.focus then
		return
	end
	ns.session.focus = questId
	ns.session.focusSource = questId and source or nil
	ns.session.focusTitle = nil
	ns.session.pinned = nil
	-- Synchronise le « focus » de Questie (il estompe alors les autres quêtes sur la carte).
	if source ~= "questie" then
		local utils = QuestieTracker()
		local current = Questie and Questie.db and Questie.db.char and Questie.db.char.TrackerFocus
		if utils then
			if questId and utils.FocusQuest then
				pcall(utils.FocusQuest, utils, questId)
			elseif not questId and current and utils.UnFocus then
				pcall(utils.UnFocus, utils)
			end
		end
		lastQuestieFocus = Questie and Questie.db and Questie.db.char and Questie.db.char.TrackerFocus
	end
	ns.SetPaused(false)
	ns.RequestPlan("focus", 0)
end

-- Le bouton « focus » à côté d'une quête dans le suivi de Questie pilote aussi Itinéraire.
function ns.WatchQuestieFocus()
	C_Timer.NewTicker(1, function()
		local db = Questie and Questie.db and Questie.db.char
		local focus = db and db.TrackerFocus
		if type(focus) ~= "number" then
			focus = nil
		end
		if focus ~= lastQuestieFocus then
			local old = lastQuestieFocus
			lastQuestieFocus = focus
			if focus then
				ns.SetFocus(focus, "questie")
			elseif old and ns.session.focus == old then
				ns.SetFocus(nil, "questie")
			end
		end
	end)
end

function ns.SkipStop(key)
	if not key then
		return
	end
	ns.session.skipped[key] = true
	if ns.session.pinned == key then
		ns.session.pinned = nil
	end
	ns.RequestPlan("skip", 0)
end

function ns.ResetChoices()
	wipe(ns.session.skipped)
	ns.session.pinned = nil
	ns.RequestPlan("reset", 0)
end

-- Addons qui guident aussi (ils se disputeraient la flèche) ou inutiles ici : désactivés automatiquement.
local CONFLICTS = {
	"RXPGuides", "AdventureGuideForever", "Polestar", "Guidelime", "ForeverWisp", "QuestTrail",
	"ForeverRoute", "ForeverRoutes", "AzerothPilotReloaded", "ZygorGuidesViewer", "ZygorGuidesViewerClassic",
	"ZygorGuidesViewerForever", "Journey", "QuestieTrace", "Leveldon",
}
local conflicts = {}
local function Loaded(name)
	local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	return fn and fn(name) and true or false
end

local function DisableConflicts()
	if ns.db.ui.autoDisable == false then
		return
	end
	local disable = (C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn
	local player = UnitName("player")
	for _, name in ipairs(CONFLICTS) do
		if Loaded(name) and disable then
			pcall(disable, name, player)
			conflicts[#conflicts + 1] = name
		end
	end
	if #conflicts > 0 then
		ns.Print("désactivé : |cffff9933" .. table.concat(conflicts, ", ") .. "|r (ils guidaient aussi). Tape |cffffff00/reload|r pour finir.")
	end
	-- Questdon garde sa liste de quêtes (utile) mais a sa propre flèche et marque aussi les récompenses : on prévient.
	if Loaded("Questdon") and not ns.db.questdonNoticed then
		ns.db.questdonNoticed = true
		ns.Print("Questdon est installé : sa flèche s'ajoute à celle de Shortest Path (|cffffff00/qd arrow|r pour la masquer),"
			.. " et il marque aussi les récompenses de quête (pièce d'or) : le cadre vert « Conseillé » est celui d'Itinéraire.")
	end
end

function ns.StatusText()
	if not ns.ready then
		return "En attente de Questie…"
	end
	local parts = {}
	if ns.session.focus then
		local title = ns.session.focusTitle or ("quête " .. ns.session.focus)
		if ns.plan and ns.plan.focus == ns.session.focus and not ns.plan.focusRouted then
			parts[#parts + 1] = "|cff66ccffSuivie :|r « " .. title .. " » — position inconnue (Questie n'a pas ses données)."
		else
			parts[#parts + 1] = "|cff66ccffSuivie :|r « " .. title .. " » passe en premier (Q pour arrêter)."
		end
	end
	if ns.session.paused then
		parts[#parts + 1] = "Guidage en pause (trajet remplacé ou effacé) : bouton R pour reprendre."
	end
	if not ns.Geo.SPApi() then
		parts[#parts + 1] = "Shortest Path absent : simple repère Blizzard."
	end
	if #conflicts > 0 then
		parts[#parts + 1] = "Désactivé : " .. table.concat(conflicts, ", ") .. ". Tape /reload pour finir."
	end
	if ns.groupMissing then
		parts[#parts + 1] = "Partage de groupe indisponible : quitte et relance WoW (nouveau fichier de l'addon)."
	end
	local group = ns.Group and ns.Group.StatusText()
	if group then
		parts[#parts + 1] = group
	end
	return table.concat(parts, "\n")
end

-------------------------------------------------------------------------------
-- Versions : ce qui a été mis à jour depuis la dernière fois, nouveautés, installateur
-------------------------------------------------------------------------------
local TRACKED = { "Itineraire", "Questie", "QuestieDB", "ShortestPathForever", "ForeverCore" }
local TRACKED_NAMES = { Itineraire = "Itinéraire", ShortestPathForever = "Shortest Path" }

local function AddonVersion(name)
	local fn = C_AddOns and C_AddOns.GetAddOnMetadata or rawget(_G, "GetAddOnMetadata")
	local ok, v = pcall(fn, name, "Version")
	return ok and type(v) == "string" and v ~= "" and v or nil
end
ns.AddonVersion = AddonVersion

-- Compare « 1.9.0 » et « 1.10.2 » : -1, 0 ou 1 (nil si illisible).
function ns.CompareVersions(a, b)
	if type(a) ~= "string" or type(b) ~= "string" then
		return nil
	end
	local pa, pb = {}, {}
	for n in a:gsub("^v", ""):gmatch("%d+") do
		pa[#pa + 1] = tonumber(n)
	end
	for n in b:gsub("^v", ""):gmatch("%d+") do
		pb[#pb + 1] = tonumber(n)
	end
	if #pa == 0 or #pb == 0 then
		return nil
	end
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x ~= y then
			return x < y and -1 or 1
		end
	end
	return 0
end

-- Ce que l'installateur a écrit (Installateur.lua) : { version, auto, verifie } ou nil (installé à la main).
function ns.InstallerInfo()
	local info = rawget(_G, "ItineraireInstallateur")
	if type(info) ~= "table" or type(info.version) ~= "number" then
		return nil
	end
	return info
end

function ns.InstallerText()
	local info = ns.InstallerInfo()
	if not info then
		return "installé à la main (pas de mise à jour automatique)"
	end
	return string.format("installateur v%d · mise à jour automatique %s · dernière vérification %s%s", info.version,
		info.auto and "ACTIVE" or "désactivée", tostring(info.verifie or "?"),
		info.version < ns.INSTALLER_WANTED and " · INSTALLATEUR À METTRE À JOUR" or "")
end

function ns.CheckVersions()
	local db = ns.db
	db.versions = type(db.versions) == "table" and db.versions or {}
	local changes = {}
	local mine = AddonVersion(ADDON)
	local previous = db.versions[ADDON]
	for _, name in ipairs(TRACKED) do
		local now = AddonVersion(name)
		local before = db.versions[name]
		if now and before and before ~= now then
			changes[#changes + 1] = (TRACKED_NAMES[name] or name) .. " " .. before .. " -> " .. now
		end
		db.versions[name] = now or before
	end
	if #changes > 0 then
		ns.Print("mis à jour depuis ta dernière session : " .. table.concat(changes, ", ") .. ".")
	end
	-- Nouveautés d'Itinéraire : une fois par version, toutes celles sautées depuis la dernière vue (pas à la toute
	-- première installation).
	local since = db.newsSeen or previous
	if mine and db.newsSeen ~= mine and (previous or db.wizardDone == true) then
		local versions = {}
		for v in pairs(ns.NEWS) do
			-- (sans repère : joueur d'une version d'avant ce suivi, on montre tout ce qui existe)
			if ns.CompareVersions(v, mine) ~= 1 and (v == mine or not since or ns.CompareVersions(v, since) == 1) then
				versions[#versions + 1] = v
			end
		end
		table.sort(versions, function(a, b)
			return ns.CompareVersions(a, b) == 1
		end)
		for _, v in ipairs(versions) do
			ns.Print("nouveautés de la version " .. v .. " :")
			for _, line in ipairs(ns.NEWS[v]) do
				ns.Print("  - " .. line)
			end
		end
	end
	db.newsSeen = mine or db.newsSeen
	local info = ns.InstallerInfo()
	if info and info.version < ns.INSTALLER_WANTED then
		ns.Print("un nouvel installateur est sorti : télécharge le paquet sur " .. ns.HOME
			.. " (onglet Releases) et relance-le. En attendant, tes mises à jour continuent.")
	end
	if ns.gearMissing then
		ns.Print("nouveaux fichiers dans cette version : |cffffff00quitte et relance complètement WoW|r pour avoir l'équipement.")
	end
end

-------------------------------------------------------------------------------
-- Démarrage
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")

local function WaitForQuestie()
	local tries = 0
	local ticker
	ticker = C_Timer.NewTicker(1, function()
		tries = tries + 1
		if ns.Data.QuestieReady() and ns.Data.Modules() and ns.Geo.Init() then
			ticker:Cancel()
			ns.ready = true
			DisableConflicts()
			ns.UI.SetStatus(ns.StatusText())
			ns.WatchQuestieFocus()
			ns.session.grouped = Grouped()
			C_Timer.NewTicker(1, function()
				pcall(ns.TrackTravel)
			end)
			ns.Group.Init()
			local okV, errV = pcall(ns.CheckVersions)
			if not okV then
				OnError("versions : " .. tostring(errV))
			end
			-- Ligne « Itinéraire : +12 % pour toi » dans la bulle des objets.
			pcall(ns.Gear.HookTooltips)
			-- Pilote automatique (prise et rendu des quêtes, vols, marchand, maître, objet de quête…).
			local okP, errP = pcall(ns.Pilote.Init)
			if not okP then
				OnError("pilote : " .. tostring(errP))
			end
			-- Recherche des améliorations d'équipement : après le 1er calcul du trajet (rien ne presse).
			C_Timer.After(25, function()
				pcall(ns.Gear.Rescan)
			end)
			C_Timer.NewTicker(5, function()
				ns.Group.Tick()
				ns.AutoResume()
				ns.Guide.Flush() -- trajet mis de côté (combat, recherche de Shortest Path en cours)
				ns.UI.SetStatus(ns.StatusText())
			end)
			ns.RequestPlan("login", 0.5)
			-- 1re fois : l'assistant de départ (solo/groupe, région, rendus auto, fenêtre).
			C_Timer.After(4, function()
				if ns.db.wizardDone ~= true and not ns.session.wizardLater then
					local ok, err = pcall(ns.Options.ShowWizard)
					if not ok then
						OnError("assistant : " .. tostring(err))
					end
				end
			end)
			-- Questie remplit les positions des objectifs peu après la connexion : un second passage.
			C_Timer.After(12, function()
				ns.RequestPlan("late", 0)
			end)
			-- Si on s'est beaucoup déplacé, on recalcule (zones de chasse les plus proches).
			C_Timer.NewTicker(15, function()
				local p = ns.Geo.Player()
				local d = lastPos and ns.Geo.Yards(lastPos, p)
				if (not d and p.wx) or (d and d > 300) then
					ns.RequestPlan("move", 0)
				end
			end)
		elseif tries >= 240 then
			ticker:Cancel()
			ns.UI.SetStatus("Questie ne répond pas : Itinéraire a besoin de Questie et QuestieDB.")
		end
	end)
end

events:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		Merge(DEFAULT_DB.ui, ns.Options.DEFAULT_UI)
		ItineraireDB = Merge(type(ItineraireDB) == "table" and ItineraireDB or {}, DEFAULT_DB)
		ItineraireCharDB = Merge(type(ItineraireCharDB) == "table" and ItineraireCharDB or {}, DEFAULT_CHAR)
		ns.db, ns.char = ItineraireDB, ItineraireCharDB
		-- Journal d'erreurs partagé des addons Forever : il attrape aussi les erreurs hors calcul (fenêtre,
		-- événements), gardées d'une session à l'autre ; /iti rapport les affiche.
		local core = rawget(_G, "ForeverCore")
		if type(core) == "table" and type(core.Register) == "function" then
			ItineraireDB.forever = type(ItineraireDB.forever) == "table" and ItineraireDB.forever or {}
			local ok, ctx = pcall(core.Register, ADDON, { title = "Itinéraire", db = ItineraireDB.forever })
			ns.forever = ok and type(ctx) == "table" and ctx or nil
		end
	elseif event == "PLAYER_LOGIN" then
		ns.Geo.Init()
		ns.UI.Create()
		ns.Options.RegisterSettings()
		WaitForQuestie()
		self:RegisterEvent("PLAYER_REGEN_DISABLED")
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
		self:RegisterEvent("QUEST_LOG_UPDATE")
		self:RegisterEvent("QUEST_ACCEPTED")
		self:RegisterEvent("QUEST_TURNED_IN")
		self:RegisterEvent("QUEST_REMOVED")
		self:RegisterEvent("PLAYER_LEVEL_UP")
		self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		self:RegisterEvent("TAXIMAP_OPENED")
		self:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
		self:RegisterEvent("BAG_UPDATE_DELAYED")
		self:RegisterEvent("MERCHANT_CLOSED")
		self:RegisterEvent("GROUP_ROSTER_UPDATE")
		self:RegisterEvent("CHAT_MSG_ADDON")
		self:RegisterEvent("TRAINER_SHOW")
		self:RegisterEvent("QUEST_COMPLETE")
		self:RegisterEvent("QUEST_FINISHED")
		self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
		for _, e in ipairs({ "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED", "TRADE_SKILL_SHOW",
			"TRADE_SKILL_LIST_UPDATE", "SKILL_LINES_CHANGED" }) do
			pcall(self.RegisterEvent, self, e) -- (un événement inconnu de cette version du jeu ne bloque rien)
		end
		-- 1re fois : on suppose tes techniques à jour (dernier niveau pair).
		if not ns.char.trainedAt then
			local level = UnitLevel("player") or 1
			ns.char.trainedAt = level - level % 2
		end
	elseif event == "GROUP_ROSTER_UPDATE" then
		local grouped = Grouped()
		if grouped ~= ns.session.grouped then
			ns.session.grouped = grouped
			ns.RequestPlan(event, 1)
		end
		ns.Group.OnRoster()
		ns.UI.SetStatus(ns.StatusText())
	elseif event == "CHAT_MSG_ADDON" then
		ns.Group.OnMessage(arg1, arg2, arg3, arg4)
	elseif event == "TRAINER_SHOW" then
		-- Maître de classe ouvert (pas un maître de métier) : techniques à jour pour ce niveau.
		if not (IsTradeskillTrainer and IsTradeskillTrainer()) then
			ns.char.trainedAt = UnitLevel("player")
			ns.RequestPlan(event, 1)
		end
	elseif event == "QUEST_COMPLETE" then
		-- Fenêtre des récompenses : la meilleure pour ton rôle (ou la plus chère à revendre).
		local ok, err = pcall(ns.Gear.OnQuestComplete)
		if not ok then
			OnError("récompense : " .. tostring(err))
		end
	elseif event == "QUEST_FINISHED" then
		pcall(ns.Gear.OnQuestFinished)
	elseif event == "ITEM_DATA_LOAD_RESULT" or event == "GET_ITEM_INFO_RECEIVED" then
		pcall(ns.Gear.OnItemData) -- (seulement si la fenêtre de récompenses attend un objet)
	elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" or event == "SKILL_LINES_CHANGED" then
		-- Ta fenêtre de métier : recettes connues (et compétences), pour les objets à fabriquer.
		if not ns.session.tradeTimer then
			ns.session.tradeTimer = true
			C_Timer.After(1, function()
				ns.session.tradeTimer = nil
				local ok, learned = pcall(ns.Gear.ReadRecipes)
				if ok and learned and ns.Gear.results then
					pcall(ns.Gear.Rescan)
				end
			end)
		end
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		-- (plusieurs objets changés d'affilée : une seule comparaison, un peu après)
		if not ns.session.gearTimer then
			ns.session.gearTimer = true
			C_Timer.After(3, function()
				ns.session.gearTimer = nil
				pcall(ns.Gear.OnEquipmentChanged)
			end)
		end
	elseif event == "UPDATE_INVENTORY_DURABILITY" or event == "BAG_UPDATE_DELAYED" then
		CheckService()
		if event == "BAG_UPDATE_DELAYED" then
			pcall(ns.Gear.CleanGoals) -- objet visé obtenu : retiré du trajet
		end
	elseif event == "MERCHANT_CLOSED" then
		-- Passage chez un marchand : l'étape réparer / vendre est faite (on n'insiste pas 15 min).
		ns.session.serviceDoneAt = GetTime()
		CheckService()
	elseif event == "QUEST_LOG_UPDATE" then
		pcall(ns.TrackProgress)
		ns.Group.ScheduleState()
		ns.RequestPlan(event, 1.5)
	elseif event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" then
		ns.RequestPlan(event, 0.5)
	elseif event == "QUEST_TURNED_IN" then
		ns.RequestPlan(event, 0.3)
	elseif event == "PLAYER_LEVEL_UP" or event == "ZONE_CHANGED_NEW_AREA" then
		ns.RequestPlan(event, 2)
		ns.UI.UpdateVisibility()
		if event == "PLAYER_LEVEL_UP" then
			C_Timer.After(8, function()
				pcall(ns.Gear.Rescan) -- nouveau niveau : nouveaux objets portables
			end)
		end
	elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_DISABLED" then
		ns.UI.UpdateVisibility()
	elseif event == "TAXIMAP_OPENED" then
		-- Nouveaux vols possibles : on oublie les temps de trajet mémorisés.
		ns.Geo.ClearCache()
	elseif event == "PLAYER_REGEN_ENABLED" then
		ns.Guide.Flush()
		ns.UI.UpdateVisibility()
	end
end)

-------------------------------------------------------------------------------
-- Commandes
-------------------------------------------------------------------------------
-- En pause parce que le trajet a été effacé ou remplacé dans Shortest Path : dès que plus rien ne
-- guide (aucun trajet en cours depuis 10 s), on reprend tout seul. (« /iti stop » reste une vraie pause.)
function ns.AutoResume()
	if not ns.session.paused or ns.session.pauseWhy == "stop" then
		return
	end
	local api = ns.Geo.SPApi()
	local ok, journey = false, nil
	if api and api.Journey then
		ok, journey = pcall(api.Journey)
	end
	if ok and type(journey) == "table" and journey.goal then
		ns.session.idleSince = nil -- un autre trajet guide encore : on le laisse faire
		return
	end
	ns.session.idleSince = ns.session.idleSince or GetTime()
	if GetTime() - ns.session.idleSince >= 10 then
		ns.SetPaused(false)
		ns.Print("plus aucun trajet dans Shortest Path : guidage repris.")
		ns.RequestPlan("reprise", 0)
	end
end

-- Route des rendus : un trajet qui ne fait que rendre les quêtes terminées (re-cliquer pour revenir).
function ns.ToggleTurnins(on)
	if on == nil then
		on = not ns.session.turnins
	end
	ns.session.turnins = on and true or nil
	ns.session.pinned = nil
	ns.SetPaused(false)
	ns.UI.SetTurnins(on)
	ns.Print(on and "route des rendus : seulement tes quêtes terminées (bouton ? pour revenir au trajet complet)."
		or "retour au trajet complet.")
	ns.RequestPlan("rendus", 0)
end

-- Diagnostic rapide dans le tchat : pourquoi la flèche ne suit pas ?
function ns.PrintState()
	local api = ns.Geo.SPApi()
	local plan = ns.plan
	ns.Print("version " .. tostring(C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?")
		.. " · Questie " .. (ns.ready and "prêt" or "PAS PRÊT")
		.. " · Shortest Path " .. (api and "présent" or "ABSENT"))
	ns.Print("trajet : " .. (plan and (#plan.order .. " étape(s)") or "pas encore calculé")
		.. (ns.session.paused and " · |cffff9933EN PAUSE|r (bouton R)" or ""))
	local g = ns.guideState
	ns.Print("dernier envoi à la flèche : " .. (g and (g.result .. (g.at and (" à " .. g.at) or "")) or "aucun"))
	if api and api.Journey then
		local ok, journey = pcall(api.Journey)
		local owner = ok and type(journey) == "table" and journey.owner
		ns.Print("flèche de Shortest Path : " .. (type(journey) == "table" and ("active, pilotée par " .. tostring(owner or "toi (à la main)")) or "aucun trajet en cours"))
	end
	local err = ns.char and ns.char.lastError
	if err then
		ns.Print("dernière erreur (" .. tostring(err.time) .. ") : " .. tostring(err.text):sub(1, 180))
	end
	ns.Print("|cff888888(tout le détail à copier-coller : /iti rapport)|r")
end

-- Rapport complet à copier-coller (/iti rapport) : tout ce qu'il faut pour comprendre un souci, sans /reload.
local function Meta(name)
	local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or rawget(_G, "GetAddOnMetadata")
	local ok, v = false, nil
	if get then
		ok, v = pcall(get, name, "Version")
	end
	local loaded = Loaded(name)
	return (ok and v and tostring(v) or "?") .. (loaded and "" or " (NON CHARGÉ)")
end

local function Secs(s)
	s = tonumber(s) or 0
	if s >= 3600 then
		return string.format("%dh%02d", math.floor(s / 3600), math.floor(s % 3600 / 60))
	elseif s >= 60 then
		return string.format("%dmin%02d", math.floor(s / 60), math.floor(s % 60))
	end
	return math.floor(s) .. "s"
end

local function OnOff(v)
	return v and "oui" or "non"
end

local function ForeverErrors(name, out, limit)
	local core = rawget(_G, "ForeverCore")
	if not (type(core) == "table" and type(core.Register) == "function") then
		return
	end
	local ctx = name == ADDON and ns.forever or select(2, pcall(core.Register, name))
	if type(ctx) ~= "table" or type(ctx.CaughtErrors) ~= "function" then
		return
	end
	local ok, list = pcall(ctx.CaughtErrors)
	if not ok or type(list) ~= "table" then
		return
	end
	for k = 1, math.min(#list, limit or 4) do
		local e = list[k]
		if type(e) == "table" then
			out[#out + 1] = string.format("  [%s%s x%s] %s", tostring(e.kind or "erreur"), e.fromSession and ", cette session" or "",
				tostring(e.count or 1), tostring(e.message or "?"):sub(1, 240))
			local stack = type(e.stack) == "string" and e.stack:gsub("\n", " / ") or nil
			if stack and stack ~= "" then
				out[#out + 1] = "    " .. stack:sub(1, 240)
			end
		end
	end
	if #list == 0 then
		out[#out + 1] = "  aucune"
	end
end

function ns.ReportText()
	local out = {}
	local function Add(line)
		out[#out + 1] = line
	end
	local plan = ns.plan
	Add("=== Rapport Itinéraire " .. Meta(ADDON) .. " · " .. date("%Y-%m-%d %H:%M:%S") .. " ===")
	local level = UnitLevel("player") or 0
	local xp, xpMax = UnitXP and UnitXP("player") or 0, UnitXPMax and UnitXPMax("player") or 0
	local rest = GetXPExhaustion and GetXPExhaustion() or nil
	local p = ns.Geo.Player()
	local region = p.map and ns.Geo.Zone(p.map)
	Add(string.format("Perso : niv %d (%d %%)%s · carte %s (%s) · région %s · %s", level,
		xpMax > 0 and math.floor(xp / xpMax * 100) or 0, rest and (" · repos " .. rest) or "", tostring(p.map),
		p.map and ns.Geo.ZoneName(p.map) or "?", region and ns.Geo.ZoneName(region) or "?",
		Grouped() and ("groupe de " .. (GetNumGroupMembers and GetNumGroupMembers() or "?")) or "solo"))
	Add("Addons : Questie " .. Meta("Questie") .. " · QuestieDB " .. Meta("QuestieDB") .. " · Shortest Path "
		.. Meta("ShortestPathForever") .. " · ForeverCore " .. Meta("ForeverCore"))
	Add("Mises à jour : " .. ns.InstallerText())
	local ext = ns.Data.Ext()
	local nRecipes = 0
	for _ in pairs(ext.RECETTES or {}) do
		nRecipes = nRecipes + 1
	end
	local okD, dungeons = pcall(ns.Data.Dungeons)
	Add(string.format("Données reprises : %d donjons/raids · %d recettes · PNJ %s · marchandises %s · DonData %s",
		okD and #dungeons or 0, nRecipes, ext.PNJ_NB and tostring(ext.PNJ_NB) or "?",
		ext.MARCHANDISES_NB and tostring(ext.MARCHANDISES_NB) or "?",
		type(rawget(_G, "DonDataAPI")) == "table" and "présent" or "absent"))
	local okPilote, piloteLine = pcall(ns.Pilote.ReportLine)
	if okPilote and piloteLine then
		Add(piloteLine)
	end
	local okGear, gearLine = pcall(ns.Gear.ReportLine)
	Add(okGear and gearLine or ("Équipement : " .. (ns.gearMissing and "fichiers absents (relancer WoW)" or tostring(gearLine))))
	local api = ns.Geo.SPApi()
	Add("État : Questie " .. (ns.ready and "prêt" or "PAS PRÊT") .. " · API Shortest Path "
		.. (api and (tostring(api.version) .. "." .. tostring(api.minor or 0)) or "ABSENTE")
		.. " · pause " .. (ns.session.paused and tostring(ns.session.pauseWhy or "oui") or "non")
		.. " · quête suivie " .. tostring(ns.session.focus or "aucune")
		.. " · étape forcée " .. tostring(ns.session.pinned or "aucune"))
	Add("Options : région " .. OnOff(ns.db.regionMode ~= false) .. " · propositions " .. OnOff(ns.db.includePickups)
		.. " · donjons " .. OnOff(ns.db.includeDungeons) .. " · réparer " .. OnOff(ns.db.includeServices ~= false)
		.. " · maître " .. OnOff(ns.db.includeTrainer ~= false) .. " · foyer " .. OnOff(ns.db.useHearth ~= false)
		.. " · groupe " .. OnOff(ns.db.groupShare) .. " · rendus seulement " .. OnOff(ns.session.turnins)
		.. " · bandeau " .. OnOff(ns.db.ui.banner ~= false) .. " · étapes " .. tostring(ns.db.ui.rows))
	local g = ns.guideState
	Add("Flèche (dernier envoi) : " .. (g and (tostring(g.result) .. " · " .. tostring(g.stops) .. " étapes à " .. tostring(g.at)) or "aucun"))
	if api and api.Journey then
		local ok, journey, why = pcall(api.Journey)
		if ok and type(journey) == "table" then
			local leg = type(journey.legs) == "table" and journey.legs[1]
			Add(string.format("Shortest Path : trajet de %s · étape %s · reste %s%s", tostring(journey.owner or "toi (à la main)"),
				tostring(journey.index or "?"), Secs(journey.secondsLeft), leg and (" · " .. tostring(leg.text or leg.mode)) or ""))
		else
			Add("Shortest Path : " .. (ok and ("aucun trajet (" .. tostring(why or "rien") .. ")") or ("erreur " .. tostring(journey))))
		end
	end
	local group = ns.Group and ns.Group.StatusText()
	if group then
		Add("Groupe : " .. group)
	end
	if plan then
		Add(string.format("Trajet : %d étapes · trajet %s + sur place %s · %s XP · %d quêtes au journal%s%s",
			#plan.order, Secs(plan.travel), Secs(plan.workTime), tostring(plan.xp or 0), plan.logCount or 0,
			plan.regionName and (" · région " .. plan.regionName) or "", plan.turninOnly and " · RENDUS SEULEMENT" or ""))
		for k = 1, math.min(#plan.order, 15) do
			local s = plan.order[k]
			local flags = {}
			for _, f in ipairs({ "legExact", "away", "promoted", "hearth", "focus" }) do
				if s[f] then
					flags[#flags + 1] = f
				end
			end
			if s.candidate then
				flags[#flags + 1] = "proposée"
			end
			if s.lateWhy then
				flags[#flags + 1] = "plus tard:" .. s.lateWhy
			end
			Add(string.format("  %d. [%s] %s · trajet %s%s · sur place %s · %s%s", k, tostring(s.kind), tostring(s.title),
				Secs(s.leg), s.legWalk and "" or " (vol/SP)", Secs(s.work), tostring(s.key),
				#flags > 0 and (" · " .. table.concat(flags, ",")) or ""))
		end
		if #plan.order > 15 then
			Add("  … " .. (#plan.order - 15) .. " étapes de plus")
		end
		local side = plan.side or {}
		local unknown = {}
		for _, u in ipairs(side.unknown or {}) do
			unknown[#unknown + 1] = (u.q and u.q.id or "?") .. " (" .. tostring(u.what) .. ")"
		end
		Add("Hors trajet : " .. #(side.pvp or {}) .. " JcJ · " .. #(side.failed or {}) .. " échouées · positions inconnues : "
			.. (#unknown > 0 and table.concat(unknown, ", ") or "aucune"))
		for _, w in ipairs(plan.warnings or {}) do
			Add("Avertissement du calcul : " .. tostring(w))
		end
	else
		Add("Trajet : pas encore calculé")
	end
	Add("Rythme : " .. (ns.PaceText() or "pas encore de mesure"))
	for _, line in ipairs(ns.PaceDetails(5)) do
		Add("  " .. line)
	end
	local spread = ns.Spread()
	Add(string.format("Fourchettes : ±%d %% sur place, ±%d %% en déplacement%s", math.floor(spread.work * 100 + 0.5),
		math.floor(spread.travel * 100 + 0.5), spread.measured and "" or " (par défaut)"))
	Add("Erreurs d'Itinéraire (calcul) :")
	local errors = ns.char and ns.char.errors or {}
	for k = math.max(1, #errors - 4), #errors do
		local e = errors[k]
		Add(string.format("  %s%s : %s", tostring(e.time), (e.count or 1) > 1 and (" (x" .. e.count .. ")") or "", tostring(e.text):sub(1, 300)))
	end
	if #errors == 0 then
		Add("  aucune")
	end
	Add("Erreurs d'Itinéraire (journal Forever) :")
	ForeverErrors(ADDON, out, 5)
	Add("Erreurs de Shortest Path :")
	ForeverErrors("ShortestPathForever", out, 5)
	return table.concat(out, "\n")
end

function ns.ShowReport()
	local ok, text = pcall(ns.ReportText)
	if not ok then
		text = "Le rapport a planté : " .. tostring(text)
		OnError("rapport : " .. tostring(text))
	end
	ns.UI.ShowCopyBox("Rapport Itinéraire", "Ctrl+C pour copier (le texte est déjà sélectionné), puis colle-le dans ton message.", text)
end

local function Dump()
	local plan = ns.plan
	if not plan then
		ns.Print("pas encore de trajet calculé.")
		return
	end
	local out = { time = date("%Y-%m-%d %H:%M:%S"), level = plan.level, xp = plan.xp, travel = plan.travel,
		work = plan.workTime, estimates = plan.estimates, stops = {}, side = {} }
	for k, s in ipairs(plan.order) do
		local quests = {}
		for _, q in ipairs(s.quests) do
			quests[#quests + 1] = q.id
		end
		out.stops[k] = { key = s.key, kind = s.kind, title = s.title, sub = s.subtitle, map = s.map,
			x = s.x, y = s.y, leg = s.leg, work = s.work, quests = quests, details = s.details }
	end
	for name, list in pairs(plan.side) do
		local ids = {}
		for key, v in pairs(list) do
			local q = v.q or v
			ids[#ids + 1] = (q.id or key) .. " " .. (q.title or v.name or "") .. (v.why and (" " .. v.why) or "") .. (v.what and (" " .. v.what) or "")
		end
		out.side[name] = ids
	end
	out.calib = ns.char.calib
	out.guide = ns.guideState
	out.paused = ns.session.paused and (ns.session.pauseWhy or true) or nil
	out.warnings = plan.warnings
	out.version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or nil
	ns.char.debug = out
	ns.Print("trajet enregistré : tape /reload pour l'écrire sur le disque.")
end

SLASH_ITINERAIRE1 = "/iti"
SLASH_ITINERAIRE2 = "/itineraire"
SlashCmdList.ITINERAIRE = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "" then
		ns.UI.Toggle()
	elseif msg == "r" or msg == "calc" or msg == "recalc" then
		ns.SetPaused(false)
		ns.RequestPlan("slash", 0)
	elseif msg == "reset" then
		ns.ResetChoices()
		ns.Print("étapes passées réaffichées.")
	elseif msg == "donjons" then
		ns.db.includeDungeons = not ns.db.includeDungeons
		ns.Print("donjons " .. (ns.db.includeDungeons and "inclus" or "exclus") .. ".")
		ns.RequestPlan("slash", 0)
	elseif msg == "stop" then
		ns.Guide.Clear()
		ns.SetPaused(true, "stop")
		ns.Print("guidage arrêté (/iti r pour reprendre).")
	elseif msg == "debug" then
		Dump()
	elseif msg == "options" or msg == "o" then
		ns.Options.Toggle(true)
	elseif msg == "groupe" or msg == "groupe on" or msg == "groupe off" then
		local on = msg == "groupe on" or (msg == "groupe" and not ns.db.groupShare)
		ns.Group.SetEnabled(on)
		ns.Print("partage de groupe " .. (on and "activé" or "désactivé") .. ". "
			.. (ns.Group.StatusText() or "Tu suis ton propre trajet."))
	elseif msg == "rendus" or msg == "rendre" then
		ns.ToggleTurnins()
	elseif msg == "etat" or msg == "état" then
		ns.PrintState()
	elseif msg == "rythme" then
		ns.Print("ton rythme mesuré : " .. (ns.PaceText() or "pas encore de mesure (il apprend en jouant).")
			.. " |cff888888(/iti rythme reset pour repartir de zéro)|r")
		for _, line in ipairs(ns.PaceDetails(6)) do
			ns.Print("  " .. line)
		end
	elseif msg == "rythme reset" then
		ns.ResetPace()
		ns.Print("rythme remis à zéro : retour aux temps par défaut.")
		ns.RequestPlan("slash", 0)
	elseif msg == "rapport" or msg == "report" then
		ns.ShowReport()
	elseif msg == "assistant" or msg == "bienvenue" then
		ns.Options.ShowWizard()
	elseif msg == "reglages" or msg == "réglages" or msg == "config" then
		ns.Options.Toggle(true, "trajet")
	elseif msg == "bandeau" then
		ns.db.ui.banner = ns.db.ui.banner == false
		ns.UI.RefreshBanner(ns.plan)
		ns.Print("bandeau « prochaine étape » " .. (ns.db.ui.banner and "affiché" or "masqué") .. ".")
	elseif msg == "equipement" or msg == "équipement" or msg == "stuff" or msg == "e" then
		if ns.gearMissing then
			ns.Print("l'équipement arrive avec de nouveaux fichiers : quitte et relance complètement WoW.")
		else
			ns.GearUI.Toggle()
		end
	elseif msg == "pilote" or msg == "pilote on" or msg == "pilote off" or msg == "autopilote" then
		if ns.piloteMissing then
			ns.Print("le pilote arrive avec un nouveau fichier : quitte et relance complètement WoW.")
		else
			local on = msg == "pilote on" or ((msg == "pilote" or msg == "autopilote") and not ns.Pilote.Config().on)
			ns.Pilote.SetOn(on)
		end
	elseif msg == "version" or msg == "maj" then
		ns.Print("Itinéraire " .. tostring(AddonVersion(ADDON)) .. " · " .. ns.InstallerText() .. " · " .. ns.HOME)
	else
		ns.Print("/iti (fenêtre) · /iti pilote · /iti equipement · /iti reglages · /iti assistant · /iti rapport · /iti bandeau · /iti r (recalculer) · /iti rendus · /iti reset · /iti rythme · /iti groupe · /iti donjons · /iti etat · /iti version · /iti stop · /iti debug")
	end
end

-------------------------------------------------------------------------------
-- Raccourcis clavier (Bindings.xml) et bouton du menu des addons
-------------------------------------------------------------------------------
BINDING_HEADER_ITINERAIRE = "Itinéraire"
BINDING_NAME_ITINERAIRE_TOGGLE = "Afficher / masquer la fenêtre"
BINDING_NAME_ITINERAIRE_RECALC = "Recalculer le trajet"
BINDING_NAME_ITINERAIRE_SKIP = "Passer l'étape en cours"
BINDING_NAME_ITINERAIRE_OPTIONS = "Ouvrir la personnalisation"
BINDING_NAME_ITINERAIRE_TURNINS = "Route des rendus (quêtes terminées)"
BINDING_NAME_ITINERAIRE_PILOTE = "Pilote automatique : marche / arrêt"
_G["BINDING_NAME_CLICK ItineraireItemButton:LeftButton"] = "Utiliser l'objet de quête (pilote)"

function Itineraire_Pilote()
	if not ns.piloteMissing then
		ns.Pilote.SetOn(not ns.Pilote.Config().on)
	end
end

function Itineraire_Turnins()
	ns.ToggleTurnins()
end

function Itineraire_Toggle()
	ns.UI.Toggle()
end

function Itineraire_Recalc()
	ns.SetPaused(false)
	ns.RequestPlan("binding", 0)
end

function Itineraire_SkipCurrent()
	local first = ns.plan and ns.plan.order[1]
	if first then
		ns.SkipStop(first.key)
		ns.Print("étape passée : " .. first.title)
	end
end

function Itineraire_Options()
	ns.Options.Toggle()
end

function Itineraire_OnCompartmentClick(_, button)
	if button == "RightButton" then
		ns.Options.Toggle()
	else
		ns.UI.Toggle()
	end
end
