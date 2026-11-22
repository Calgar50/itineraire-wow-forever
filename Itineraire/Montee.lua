-- Itinéraire : la montée de niveau au-delà du journal.
--   Frise jusqu'au niveau 60 : zone par zone (quêtes de la base Questie faisables par ta classe et ta race), donjons
--   au bon moment. Région suivante quand ton journal se vide. Filons de minage à deux pas du trajet. Plan de forge.
-- Tout est une estimation à partir des données (Questie, recettes reprises) : jamais d'action à ta place.
local _, ns = ...
local Montee = {}
ns.Montee = Montee
local Data, Geo = ns.Data, ns.Geo

local MAX_LEVEL = 60
local FRISE_ROWS = 14
local REGION_MIN_QUESTS = 4 -- une région suivante n'est proposée qu'avec au moins tant de quêtes à prendre
local REGION_STILL_HERE = 3 -- la région actuelle en a encore autant : le mode région s'en charge
local THIN_STOPS, THIN_TIME = 4, 1200 -- journal « presque fini » : moins de 4 étapes ou moins de 20 min
local MINE_MAX = 3 -- filons au plus sur le trajet
local MINE_DETOUR = 75 -- détour maximum pour un coin à filons (s)
local MINE_HORIZON = 1800 -- seulement dans la première demi-heure du trajet
local MINE_NEAR = 250 -- un emplacement à plus de 250 m de toute étape n'est pas regardé
local MINE_CLUSTER = 70 -- emplacements regroupés en un « coin à filons »
local MINE_KEEP, MINE_KEEP_BONUS = 1.6, 40 -- un coin déjà au trajet : détour toléré ×1,6 et préféré (40 s)

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

local function Thousands(n)
	local s = tostring(math.floor(n or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (out:gsub("^%s+", ""))
end
Montee.Thousands = Thousands

local function Comma(x)
	return (string.format("%.1f", x):gsub("%.", ","))
end

-------------------------------------------------------------------------------
-- Index des quêtes de la base (construit en tâche de fond, une fois par session)
-------------------------------------------------------------------------------
local runner = CreateFrame("Frame")
runner:Hide()
local job, deadline = nil, 0
local BUDGET_MS = 4

local function Yield()
	if coroutine.running() and debugprofilestop() > deadline then
		coroutine.yield()
	end
end

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
		Montee.indexError = tostring(err)
		if ns.OnError then
			ns.OnError("frise : " .. tostring(err))
		end
		return
	end
	if coroutine.status(job) == "dead" then
		job = nil
		self:Hide()
		if ns.MonteeUI and ns.MonteeUI.Refresh then
			pcall(ns.MonteeUI.Refresh)
		end
		if ns.RequestPlan then
			ns.RequestPlan("frise", 1) -- (la région suivante peut maintenant être proposée)
		end
	end
end)

function Montee.BuildIndex()
	if job or Data.QuestIndexReady() or not Data.Modules() then
		return
	end
	job = coroutine.create(function()
		Data.QuestIndex(Yield)
	end)
	runner:Show()
end

-- L'index (nil tant qu'il n'est pas prêt : sa construction est alors lancée).
function Montee.Index()
	if Data.QuestIndexReady() then
		return Data.QuestIndex()
	end
	Montee.BuildIndex()
	return nil
end

function Montee.IndexState()
	if Data.QuestIndexReady() then
		local index = Data.QuestIndex()
		local zones = 0
		for _ in pairs(index.zones) do
			zones = zones + 1
		end
		return "prêt", index.count, zones
	end
	return job and "en cours" or (Montee.indexError and ("erreur : " .. Montee.indexError) or "pas lancé")
end

-------------------------------------------------------------------------------
-- XP (règles Classic : une quête trop basse pour toi rapporte moins)
-------------------------------------------------------------------------------
local function Adjusted(xp, questLevel, level)
	local diff = level - questLevel
	local f = diff <= 5 and 1 or diff == 6 and 0.8 or diff == 7 and 0.6 or diff == 8 and 0.4 or diff == 9 and 0.2 or 0.1
	return xp * f
end

local function LevelXP(level)
	local t = ns.Planner and ns.Planner.NEXT_XP or {}
	return t[level] or t[#t] or 200000
end

local function Gray(level)
	local fn = ns.Planner and ns.Planner.GrayLevel
	return fn and fn(level) or (level - 6)
end

-- Faisable et intéressante au niveau `level` : niveau requis atteint, pas plus de 2 niveaux au-dessus, pas grise.
local function Doable(e, level)
	return (e.req or 1) <= level and e.level <= level + 2 and e.level > Gray(level)
end

-------------------------------------------------------------------------------
-- Frise : la suite de ta montée, zone par zone, jusqu'au niveau 60
-------------------------------------------------------------------------------
local function DungeonsFor(from, to, shown)
	local out = {}
	local ok, list = pcall(Data.Dungeons)
	for _, d in ipairs(ok and type(list) == "table" and list or {}) do
		local key = d.english or d.name
		if not d.raid and not shown[key] and d.min and d.max then
			-- le bon moment : quelques niveaux après son plus bas niveau, avant son plus haut
			local good = math.max(d.min + 2, math.min(d.min + 4, d.max - 2))
			if good >= math.floor(from) and good <= math.max(math.floor(from), math.floor(to)) then
				shown[key] = true
				out[#out + 1] = d
			end
		end
	end
	return out
end

-- XP par heure à ton rythme (le trajet actuel), ou nil si on ne sait pas encore.
local function Rate()
	local plan = ns.plan
	local time = plan and ((plan.travel or 0) + (plan.workTime or 0)) or 0
	if plan and (plan.xp or 0) >= 1500 and time >= 600 then
		return plan.xp / time * 3600
	end
	return nil
end

-- Rend { rows = { { zone, name, from, to, quests, xp, hours, dungeons } }, start, stop } ou nil, raison.
function Montee.Frise()
	local index = Montee.Index()
	if not index then
		return nil, "calcul"
	end
	local plan = ns.plan
	local level = Call(UnitLevel, "player") or 1
	local start = plan and plan.levelEnd or level
	local L = math.floor(start)
	local cur = (start - L) * LevelXP(L) -- XP déjà dans le niveau L
	local inLog = {}
	for _, q in ipairs(plan and plan.quests or {}) do
		inLog[q.id] = true
	end
	local used, done, base = {}, {}, {}
	local function Done(id)
		if done[id] == nil then
			done[id] = Data.Completed(id) or inLog[id] or false
		end
		return done[id]
	end
	local function Base(e)
		if not base[e.id] then
			base[e.id] = Data.BaseQuestXP(e.id, e.level) or 0
		end
		return base[e.id]
	end
	local function Gain(xp)
		cur = cur + xp
		while L < MAX_LEVEL and cur >= LevelXP(L) do
			cur = cur - LevelXP(L)
			L = L + 1
		end
		if L >= MAX_LEVEL then
			cur = 0
		end
	end
	local function Now()
		return L + (L >= MAX_LEVEL and 0 or cur / LevelXP(L))
	end
	-- Seulement les quêtes pas encore faites et pas déjà grises : la base entière est lue une fois, pas à chaque niveau.
	local pool, gray = {}, Gray(L)
	for zone, list in pairs(index.zones) do
		local kept = {}
		for _, e in ipairs(list) do
			if e.level > gray and not Done(e.id) then
				kept[#kept + 1] = e
			end
		end
		if #kept > 0 then
			pool[zone] = kept
		end
	end
	local rows, shown, last = {}, {}, nil
	local rate = Rate()
	local gaps = 0
	while L < MAX_LEVEL and #rows < FRISE_ROWS do
		-- la zone qui rapporte le plus à ce niveau (au moins 3 quêtes ; à défaut, au moins une)
		local best, bestScore, bestRank
		for zone, list in pairs(pool) do
			if not Data.ZoneDanger(zone, L) then
				local xp, n = 0, 0
				for _, e in ipairs(list) do
					if not used[e.id] and Doable(e, L) and not Done(e.id) then
						xp, n = xp + Adjusted(Base(e), e.level, L), n + 1
					end
				end
				local score = xp * (zone == last and 1.2 or 1) -- (rester dans la même zone, plutôt que d'en changer)
				local rank = n >= 3 and 2 or (n > 0 and 1 or 0)
				if rank > 0 and (not best or rank > bestRank or (rank == bestRank and score > bestScore)) then
					best, bestScore, bestRank = zone, score, rank
				end
			end
		end
		if not best then
			-- Aucune quête connue à ce niveau : monstres, donjons, quêtes de groupe jusqu'au niveau suivant.
			gaps = gaps + 1
			if gaps > 6 then
				break
			end
			local from = Now()
			L, cur = L + 1, 0
			local prevRow = rows[#rows]
			if prevRow and prevRow.gap then
				prevRow.to = Now()
			else
				rows[#rows + 1] = { gap = true, from = from, to = Now(), quests = 0, xp = 0, name = "" }
			end
			last = nil
		else
			-- La zone choisie : ses quêtes faisables, et celles qui le deviennent en montant, tant qu'il y en a.
			gaps = 0
			local from, n, xp = Now(), 0, 0
			repeat
				local progress = false
				for _, e in ipairs(pool[best]) do
					if not used[e.id] and Doable(e, L) and not Done(e.id) and L < MAX_LEVEL then
						used[e.id] = true
						local g = Adjusted(Base(e), e.level, L)
						xp, n = xp + g, n + 1
						Gain(g)
						progress = true
					end
				end
			until not progress or L >= MAX_LEVEL
			local to = Now()
			local prevRow = rows[#rows]
			if prevRow and prevRow.zone == best then
				prevRow.to, prevRow.quests, prevRow.xp = to, prevRow.quests + n, prevRow.xp + xp
			else
				local low, high = Data.ZoneLevels(best)
				rows[#rows + 1] = { zone = best, name = Geo.ZoneName(best), from = from, to = to, quests = n, xp = xp,
					low = low, high = high }
			end
			last = best
		end
	end
	for _, row in ipairs(rows) do
		row.dungeons = DungeonsFor(row.from, row.to, shown)
		row.hours = rate and row.xp / rate or nil
	end
	return { rows = rows, start = start, stop = Now(), rate = rate }
end

function Montee.FriseLines()
	local frise, why = Montee.Frise()
	if not frise then
		return { why == "calcul" and "Calcul de la frise en cours (toute la base de quêtes est lue une fois)…"
			or "Questie n'est pas prêt : la frise attend sa base de quêtes." }
	end
	local lines = {}
	local plan = ns.plan
	if plan and plan.levelEnd and plan.levelEnd > (plan.level or 0) + 0.05 then
		lines[#lines + 1] = "|cff888888Après ton journal actuel : niveau " .. Comma(frise.start) .. ". Ensuite :|r"
	end
	for _, row in ipairs(frise.rows) do
		if row.gap then
			lines[#lines + 1] = string.format("|cffffd200%s à %s|r : |cff888888pas assez de quêtes connues : monstres, donjons, quêtes de groupe|r",
				Comma(row.from), Comma(row.to))
		else
			local range = row.low and (" |cff888888(zone " .. row.low .. "-" .. row.high .. ")|r") or ""
			local hours = row.hours and string.format(" · ~%s h à ton rythme", Comma(row.hours)) or ""
			lines[#lines + 1] = string.format("|cffffd200%s à %s|r : %s%s · %d quêtes · ~%s XP%s", Comma(row.from), Comma(row.to),
				row.name ~= "" and row.name or ("zone " .. tostring(row.zone)), range, row.quests, Thousands(row.xp), hours)
		end
		for _, d in ipairs(row.dungeons or {}) do
			lines[#lines + 1] = string.format("    |cff66ccffdonjon : %s|r (niv %d-%d)", tostring(d.name), d.min, d.max)
		end
	end
	if #frise.rows == 0 then
		lines[#lines + 1] = "Aucune zone avec assez de quêtes de ton niveau dans la base : donjons et monstres."
	elseif frise.stop < MAX_LEVEL then
		lines[#lines + 1] = string.format("|cff888888Niveau %s avec les quêtes connues ; le reste : donjons, monstres et quêtes de groupe.|r",
			Comma(frise.stop))
	else
		lines[#lines + 1] = "|cff888888Niveau 60 atteint sur la frise.|r"
	end
	lines[#lines + 1] = "|cff888888Estimation : quêtes de la base Questie (ta classe, ta race, pas encore faites), suites de quêtes "
		.. "comptées comme si tout était ouvert, sans l'XP des monstres. Recalculée à chaque ouverture.|r"
	return lines
end

-------------------------------------------------------------------------------
-- Région suivante : quand ton journal se vide, la zone de ton niveau qui a le plus de quêtes à prendre
-------------------------------------------------------------------------------
function Montee.NextRegionNeed(opts, plan, stops, order, C, yield)
	local index = Montee.Index()
	if not index then
		return nil
	end
	local count, time, prev = 0, 0, 0
	for _, idx in ipairs(order) do
		local s = stops[idx]
		if s.tier < 1 and s.kind ~= "service" then
			count = count + 1
			time = time + (C[prev][idx] or 0) + s.work
		end
		prev = idx
	end
	if count >= THIN_STOPS and time >= THIN_TIME then
		return nil -- le journal occupe encore
	end
	local level = plan.level
	local avail = Data.AvailableQuests()
	local inLog = {}
	for _, q in ipairs(plan.quests or {}) do
		inLog[q.id] = true
	end
	local here = plan.region or (plan.player.map and Geo.Zone(plan.player.map))
	local zones, n = {}, 0
	for zone, list in pairs(index.zones) do
		if not Data.ZoneDanger(zone, level) then
			local ids, xp = {}, 0
			for _, e in ipairs(list) do
				n = n + 1
				if n % 200 == 0 then
					yield()
				end
				if avail[e.id] and not inLog[e.id] and (e.req or 1) <= level and e.level <= level + 2 and e.level >= level - 4 then
					ids[#ids + 1] = e
					xp = xp + Adjusted(Data.BaseQuestXP(e.id, e.level), e.level, level)
				end
			end
			if zone == here then
				if #ids >= REGION_STILL_HERE then
					return nil -- la région a encore des quêtes : le mode région les propose
				end
			elseif #ids >= REGION_MIN_QUESTS then
				zones[#zones + 1] = { zone = zone, ids = ids, xp = xp }
			end
		end
	end
	table.sort(zones, function(a, b)
		return a.xp > b.xp
	end)
	local best
	for k = 1, math.min(3, #zones) do
		local z = zones[k]
		local points, kept, xp = {}, 0, 0
		for _, e in ipairs(z.ids) do
			local quest = Data.Quest(e.id)
			if quest and Data.CanTake(e.id, quest, inLog) then
				local any = false
				for _, p in ipairs(Data.StarterPoints(quest)) do
					if Geo.Zone(p.map) == z.zone and not Data.ZoneDanger(p.map, level) then
						points[#points + 1] = p
						any = true
					end
				end
				if any then
					kept = kept + 1
					xp = xp + Adjusted(Data.BaseQuestXP(e.id, e.level), e.level, level)
				end
			end
			yield()
		end
		local hub = kept >= REGION_MIN_QUESTS and Data.Clusters(points, 150)[1]
		if hub then
			local travel = Geo.Estimate(plan.player, hub) or Geo.Walk(plan.player, hub) or 3600
			local score = xp / (1 + travel / 1800)
			if not best or score > best.score then
				best = { zone = z.zone, hub = hub, count = kept, xp = xp, score = score, travel = travel }
			end
		end
	end
	if not best then
		return nil
	end
	local name = Geo.ZoneName(best.zone)
	local low, high = Data.ZoneLevels(best.zone)
	return {
		kind = "region", key = "region" .. best.zone, point = best.hub, work = 30, radius = 60, zone = best.zone,
		zoneName = name, count = best.count,
		title = "Nouvelle région : " .. name,
		label = "Région suivante : " .. name .. (low and (" (niv " .. low .. "-" .. high .. ")") or ""),
		why = {
			string.format("Ton journal est presque fini : %s a %d quêtes de ton niveau à prendre (~%s XP).", name,
				best.count, Thousands(best.xp)),
			"Le pilote les prend en passant ; sur place, Itinéraire finit la région comme d'habitude.",
			"Pas maintenant ? Clic droit > Passer l'étape.",
		},
	}
end

-------------------------------------------------------------------------------
-- Minage : filons qui te font monter, à deux pas du trajet
-------------------------------------------------------------------------------
-- Objets « filon » de la base Questie (emplacements possibles ; un filon n'est pas toujours là).
local ORES = {
	{ key = "cuivre", label = "Filon de cuivre", short = "cuivre", req = 1, ore = 2770, bar = 2840,
		ids = { 1731, 2055, 3763, 103713, 181248 } },
	{ key = "etain", label = "Filon d'étain", short = "étain", req = 65, ore = 2771, bar = 3576,
		ids = { 1732, 2054, 3764, 103711, 181249 } },
	{ key = "incendicite", label = "Filon d'incendicite", short = "incendicite", req = 65, ore = 3340, ids = { 1610, 1667 } },
	{ key = "argent", label = "Filon d'argent", short = "argent", req = 75, ore = 2775, bar = 2842, rare = true,
		ids = { 1733, 105569, 73940 } },
	{ key = "sanguinite", label = "Gisement de pierre de sang inférieure", short = "pierre de sang", req = 75, ore = 4278,
		ids = { 2653 } },
	{ key = "fer", label = "Gisement de fer", short = "fer", req = 125, ore = 2772, bar = 3575, ids = { 1735, 73939 } },
	{ key = "indurium", label = "Filon d'indurium", short = "indurium", req = 150, ore = 5833, ids = { 19903 } },
	{ key = "or", label = "Filon d'or", short = "or", req = 155, ore = 2776, bar = 3577, rare = true,
		ids = { 1734, 150080, 73941, 181109 } },
	{ key = "mithril", label = "Gisement de mithril", short = "mithril", req = 175, ore = 3858, bar = 3860,
		ids = { 2040, 150079, 176645, 123310 } },
	{ key = "vraiargent", label = "Gisement de vrai-argent", short = "vrai-argent", req = 230, ore = 7911, bar = 6037,
		rare = true, ids = { 2047, 150081, 181108, 123309 } },
	{ key = "sombrefer", label = "Gisement de sombrefer", short = "sombrefer", req = 230, ore = 11370, bar = 11371,
		ids = { 165658 } },
	{ key = "thorium", label = "Petit filon de thorium", short = "thorium", req = 245, ore = 10620, bar = 12359,
		ids = { 324, 150082, 176643, 123848 } },
	{ key = "thoriumriche", label = "Riche filon de thorium", short = "thorium riche", req = 275, ore = 10620, bar = 12359,
		ids = { 175404, 177388 } },
}
Montee.ORES = ORES
local MINING, BLACKSMITHING = 186, 164

-- Compétence d'un métier : { rank, max, name } ou nil (pas appris / pas lisible).
function Montee.Skill(line)
	local Gear = ns.Gear
	local ok, skills = pcall(Gear and Gear.ReadProfessions)
	if ok and type(skills) == "table" and type(skills[line]) == "table" then
		return skills[line]
	end
	return nil
end

-- Couleur d'un filon pour ta compétence (règle Classic) : orange, jaune, vert, gris ; nil = pas encore possible.
function Montee.OreColor(req, rank)
	if not (req and rank) or rank < req then
		return nil
	end
	local d = rank - req
	return d < 25 and "orange" or d < 50 and "jaune" or d < 100 and "vert" or "gris"
end

local COLOR_CODES = { orange = "ff8040", jaune = "ffff00", vert = "40c040", gris = "808080" }
local function Colored(color, text)
	return "|cff" .. (COLOR_CODES[color] or "ffffff") .. text .. "|r"
end
Montee.Colored = Colored

-- Les filons qui font monter ta compétence : orange et jaune ; à défaut, verts. `route` : seulement ceux qu'on trouve
-- vraiment en passant (pas l'argent, l'or, le vrai-argent : ils remplacent rarement un filon courant, leurs
-- emplacements sont presque toujours vides ou occupés par un autre filon).
function Montee.UsefulOres(rank, route)
	local good, green = {}, {}
	for _, ore in ipairs(ORES) do
		local color = Montee.OreColor(ore.req, rank)
		if route and ore.rare then
			color = nil
		end
		if color == "orange" or color == "jaune" then
			good[#good + 1] = ore
		elseif color == "vert" then
			green[#green + 1] = ore
		end
	end
	return #good > 0 and good or green
end

local orePoints = {}
function Montee.OrePoints(ore)
	if orePoints[ore.key] then
		return orePoints[ore.key]
	end
	local points = {}
	for _, id in ipairs(ore.ids) do
		local list = Data.ObjectPlaces(id, 4000)
		for _, p in ipairs(list or {}) do
			points[#points + 1] = p
		end
	end
	if Data.Modules() then
		orePoints[ore.key] = points -- (Questie prêt : la liste est complète, on la garde)
	end
	return points
end

-- Étapes « filon » à proposer : coins à filons (2 emplacements ou plus) qui demandent moins de 75 s de détour, dans la
-- première demi-heure du trajet. `maxTier` : seulement près des étapes d'avant ce niveau de priorité (la soirée).
function Montee.MineNeeds(opts, plan, stops, order, C, yield, maxTier)
	local skill = Montee.Skill(MINING)
	if not skill or (skill.rank or 0) <= 0 or ((skill.max or 0) > 0 and skill.rank >= skill.max) then
		return nil -- pas de minage, ou compétence bloquée au maximum de ton rang (maître des mineurs)
	end
	-- Un coin à filons vient d'être visité (ou passé) : pas d'autre détour avant un moment (`mineRest`).
	if opts.mineRest and GetTime() < opts.mineRest then
		return nil
	end
	local ores = Montee.UsefulOres(skill.rank, true)
	if #ores == 0 then
		return nil
	end
	local previous = opts.prevMines or {}
	local nodes = { plan.player }
	local prev, eta = 0, 0
	for _, idx in ipairs(order) do
		local s = stops[idx]
		eta = eta + (C[prev][idx] or 0) + s.work
		if eta > MINE_HORIZON or (maxTier and s.tier >= maxTier) then
			break
		end
		if not (s.kind == "service" and s.service and s.service.kind == "mine") then
			nodes[#nodes + 1] = s
		end
		prev = idx
	end
	if #nodes < 2 then
		return nil
	end
	local speed = Geo.Speed()
	local spots, n = {}, 0
	for _, ore in ipairs(ores) do
		local near = {}
		for _, p in ipairs(Montee.OrePoints(ore)) do
			n = n + 1
			if n % 300 == 0 then
				yield()
			end
			if p.inst == plan.player.inst and not Data.ZoneDanger(p.map, plan.level) then
				for _, node in ipairs(nodes) do
					local d = Geo.Yards(p, node)
					if d and d < MINE_NEAR then
						near[#near + 1] = p
						break
					end
				end
			end
		end
		for _, cl in ipairs(Data.Clusters(near, MINE_CLUSTER)) do
			if cl.count >= 2 then
				local best, bestK
				for k = 2, #nodes do
					local a, b = nodes[k - 1], nodes[k]
					local wa, wb, wab = Geo.Walk(a, cl, speed), Geo.Walk(cl, b, speed), Geo.Walk(a, b, speed)
					if wa and wb and wab then
						local d = wa + wb - wab
						if not best or d < best then
							best, bestK = d, k
						end
					end
				end
				-- (un coin déjà au trajet le reste avec un peu plus de détour : le trajet ne change pas à chaque calcul)
				local key = "mine:" .. ore.key .. ":" .. math.floor((cl.wx or 0) / 70) .. ":" .. math.floor((cl.wy or 0) / 70)
				local kept = previous[key] and true or false
				if best and best <= MINE_DETOUR * (kept and MINE_KEEP or 1) then
					local tier = nodes[bestK].tier or 0
					spots[#spots + 1] = { ore = ore, at = cl, detour = math.max(0, best), tier = tier, count = cl.count,
						key = key, kept = kept }
				end
			end
		end
	end
	local function Score(s)
		return s.detour - s.count * 5 - (s.kept and MINE_KEEP_BONUS or 0)
	end
	table.sort(spots, function(a, b)
		local sa, sb = Score(a), Score(b)
		if sa ~= sb then
			return sa < sb
		end
		return a.key < b.key
	end)
	local needs = {}
	for _, spot in ipairs(spots) do
		if #needs >= MINE_MAX then
			break
		end
		local close = false
		for _, need in ipairs(needs) do
			local d = Geo.Yards(need.point, spot.at)
			close = close or (d and d < 150)
		end
		if not close then
			local ore, at = spot.ore, spot.at
			local color = Montee.OreColor(ore.req, skill.rank)
			needs[#needs + 1] = {
				kind = "mine", ore = ore.key, point = at, tier = spot.tier, work = 20, radius = 45,
				key = spot.key,
				title = ore.label .. " (" .. color .. ")",
				label = "Minage",
				why = {
					string.format("%s : %d emplacements ici, ~%d s de détour. Ton minage : %d/%d (%s = te fait monter%s).",
						ore.label, spot.count, math.floor(spot.detour + 0.5), skill.rank, skill.max or 0, color,
						color == "vert" and " parfois" or ""),
					"Un filon n'est pas toujours là (déjà miné) : l'étape se valide en arrivant, continue ta route.",
					"Pas envie ? Clic droit > Passer l'étape (réglage : menu … > Filons de minage).",
				},
			}
		end
	end
	return needs
end

-------------------------------------------------------------------------------
-- Forge : recettes qui font monter ta compétence, et ce qu'elles demandent
-------------------------------------------------------------------------------
local ITEM_NAMES = {
	[2770] = "Minerai de cuivre", [2771] = "Minerai d'étain", [2775] = "Minerai d'argent", [2772] = "Minerai de fer",
	[2776] = "Minerai d'or", [3858] = "Minerai de mithril", [7911] = "Minerai de vrai-argent", [10620] = "Minerai de thorium",
	[11370] = "Minerai de sombrefer", [3340] = "Minerai d'incendicite", [4278] = "Pierre de sang inférieure",
	[5833] = "Minerai d'indurium",
	[2840] = "Barre de cuivre", [3576] = "Barre d'étain", [2841] = "Barre de bronze", [2842] = "Barre d'argent",
	[3575] = "Barre de fer", [3577] = "Barre d'or", [3859] = "Barre d'acier", [3860] = "Barre de mithril",
	[6037] = "Barre de vrai-argent", [12359] = "Barre de thorium", [11371] = "Barre de sombrefer",
	[2835] = "Pierre brute", [2836] = "Pierre grossière", [2838] = "Pierre lourde", [7912] = "Pierre solide",
	[12365] = "Pierre dense", [2880] = "Fondant faible", [3466] = "Fondant fort", [2589] = "Étoffe de lin",
	[2592] = "Étoffe de laine", [4306] = "Étoffe de soie", [2318] = "Cuir léger", [2319] = "Cuir moyen",
	[4234] = "Cuir lourd", [3470] = "Pierre à aiguiser grossière",
}

function Montee.ItemName(id)
	local name = GetItemInfo and Call(GetItemInfo, id)
	if type(name) == "string" and name ~= "" then
		return name
	end
	-- (pas encore en mémoire du jeu : demandé pour la prochaine fois)
	if C_Item and C_Item.RequestLoadItemDataByID then
		Call(C_Item.RequestLoadItemDataByID, id)
	end
	if ITEM_NAMES[id] then
		return ITEM_NAMES[id]
	end
	local fb = Data.ItemFallback and Data.ItemFallback(id)
	return fb and fb.name ~= "" and fb.name or ("objet " .. tostring(id))
end

local function Count(id)
	local n = GetItemCount and Call(GetItemCount, id, true)
	return type(n) == "number" and n or 0
end

-- Nom d'une recette : celui du sort (toujours connu du jeu), sinon celui de l'objet fabriqué.
local function RecipeName(spell, result)
	local name = C_Spell and C_Spell.GetSpellName and Call(C_Spell.GetSpellName, spell)
	if type(name) ~= "string" or name == "" then
		name = GetSpellInfo and Call(GetSpellInfo, spell)
	end
	if type(name) == "string" and name ~= "" then
		return name
	end
	return Montee.ItemName(result)
end

-- Couleur lue dans ta fenêtre de forge (Forever : 0 orange, 1 jaune, 2 vert, 3 gris ; ou le texte du jeu).
local DIFF = { [0] = "orange", [1] = "jaune", [2] = "vert", [3] = "gris", optimal = "orange", medium = "jaune",
	easy = "vert", trivial = "gris" }

-- Estimation sans la fenêtre : orange ~25 points après la compétence requise, puis jaune, vert, gris.
local function EstimateColor(min, rank)
	local d = rank - min
	return d < 25 and "orange" or d < 45 and "jaune" or d < 65 and "vert" or "gris"
end

local function Reagents(text)
	local list = {}
	for id, n in tostring(text or ""):gmatch("(%d+):(%d+)") do
		list[#list + 1] = { id = tonumber(id), n = tonumber(n) }
	end
	return list
end

-- Les recettes de forge qui font monter maintenant (les tiennes d'abord), les moins chères en premier.
function Montee.ForgeRecipes(limit)
	local skill = Montee.Skill(BLACKSMITHING)
	if not skill then
		return nil
	end
	local ext = Data.Ext()
	local cfg = ns.Gear and ns.Gear.Config and Call(ns.Gear.Config) or {}
	local known = type(cfg.recipes) == "table" and cfg.recipes or {}
	local diffs = type(cfg.recipeDiff) == "table" and cfg.recipeDiff or {}
	local list = {}
	for spell, r in pairs(ext.RECETTES or {}) do
		if type(r) == "table" and r[1] == BLACKSMITHING then
			local min = tonumber(r[2]) or 0
			local exact = DIFF[diffs[spell]]
			local color = exact or EstimateColor(min, skill.rank)
			if min <= skill.rank and (color == "orange" or color == "jaune") and (tonumber(r[5]) or 0) > 0 then
				local reagents = Reagents(r[7])
				local cost = 0
				for _, g in ipairs(reagents) do
					cost = cost + g.n
				end
				list[#list + 1] = { spell = spell, min = min, color = color, exact = exact and true or false,
					known = known[spell] and true or false, trainer = r[3] == "t", result = tonumber(r[5]),
					reagents = reagents, cost = cost }
			end
		end
	end
	table.sort(list, function(a, b)
		if a.known ~= b.known then
			return a.known
		end
		if a.color ~= b.color then
			return a.color == "orange"
		end
		if a.cost ~= b.cost then
			return a.cost < b.cost
		end
		return a.spell < b.spell
	end)
	while limit and #list > limit do
		table.remove(list)
	end
	return list, skill
end

local RANKS = { { 75, "Compagnon (jusqu'à 150)" }, { 150, "Expert (jusqu'à 225)" }, { 225, "Artisan (jusqu'à 300)" } }
local function NextRank(max)
	for _, r in ipairs(RANKS) do
		if max <= r[1] then
			return r[2]
		end
	end
	return nil
end

function Montee.CraftLines()
	local lines = {}
	local mining = Montee.Skill(MINING)
	if mining then
		lines[#lines + 1] = string.format("|cffffd200Minage : %d/%d|r", mining.rank or 0, mining.max or 0)
		if (mining.max or 0) > 0 and mining.rank >= mining.max then
			local nextRank = NextRank(mining.max)
			lines[#lines + 1] = "  Compétence au maximum de ton rang : va voir un maître des mineurs"
				.. (nextRank and (" (rang " .. nextRank .. ")") or "") .. ". Les filons ne te font plus monter d'ici là."
		end
		local parts = {}
		for _, ore in ipairs(ORES) do
			local color = Montee.OreColor(ore.req, mining.rank)
			if color and color ~= "gris" then
				parts[#parts + 1] = Colored(color, ore.short)
			end
		end
		if #parts > 0 then
			lines[#lines + 1] = "  Filons : " .. table.concat(parts, ", ") .. " |cff888888(orange et jaune font monter ; vert parfois)|r"
		end
		local onRoute = {}
		for _, s in ipairs(ns.plan and ns.plan.order or {}) do
			if s.kind == "service" and s.service and s.service.kind == "mine" then
				onRoute[#onRoute + 1] = s.number .. ". " .. s.title
			end
		end
		lines[#lines + 1] = #onRoute > 0 and ("  Sur ton trajet : " .. table.concat(onRoute, " · "))
			or "  Aucun coin à filons à moins de ~1 min de détour de ton trajet pour l'instant."
		local stock = {}
		for _, ore in ipairs(ORES) do
			local nOre, nBar = Count(ore.ore), ore.bar and Count(ore.bar) or 0
			if nOre > 0 or nBar > 0 then
				stock[#stock + 1] = ore.short .. " : " .. nOre .. " minerai(s)" .. (nBar > 0 and (", " .. nBar .. " barre(s)") or "")
			end
		end
		if #stock > 0 then
			lines[#lines + 1] = "  Dans tes sacs (et ta banque) : " .. table.concat(stock, " · ")
		end
	else
		lines[#lines + 1] = "|cff888888Minage : pas appris (ou pas encore lu : ouvre une fois ta fenêtre des métiers).|r"
	end
	lines[#lines + 1] = ""
	local recipes, forge = Montee.ForgeRecipes(8)
	if not forge then
		lines[#lines + 1] = "|cff888888Forge : pas apprise.|r"
		return lines
	end
	lines[#lines + 1] = string.format("|cffffd200Forge : %d/%d|r", forge.rank or 0, forge.max or 0)
	if (forge.max or 0) > 0 and forge.rank >= forge.max then
		local nextRank = NextRank(forge.max)
		lines[#lines + 1] = "  Compétence au maximum de ton rang : va voir un maître forgeron"
			.. (nextRank and (" (rang " .. nextRank .. ")") or "") .. "."
	end
	if #recipes == 0 then
		lines[#lines + 1] = "  Aucune recette connue qui fasse encore monter : nouvelles recettes chez ton maître forgeron."
	end
	local anyGuess = false
	for _, r in ipairs(recipes) do
		local parts = {}
		for _, g in ipairs(r.reagents) do
			local have = Count(g.id)
			parts[#parts + 1] = g.n .. " " .. Montee.ItemName(g.id) .. (have > 0 and (" |cff888888(" .. have .. ")|r") or "")
		end
		anyGuess = anyGuess or not r.exact
		lines[#lines + 1] = string.format("  %s %s%s : %s", Colored(r.color, "[" .. r.color .. (r.exact and "" or " ?") .. "]"),
			RecipeName(r.spell, r.result), r.known and "" or (r.trainer and " |cff888888(à apprendre chez le maître)|r" or " |cff888888(recette à trouver)|r"),
			table.concat(parts, ", "))
	end
	if anyGuess then
		lines[#lines + 1] = "  |cff888888« ? » : couleur estimée. Ouvre ta fenêtre de forge une fois : les vraies couleurs sont lues.|r"
	end
	return lines
end

-------------------------------------------------------------------------------
-- Démarrage : l'index se construit tranquillement après la connexion
-------------------------------------------------------------------------------
function Montee.Init()
	C_Timer.After(20, function()
		pcall(Montee.BuildIndex)
	end)
end
