-- Itinéraire : transforme le journal en étapes numérotées et calcule leur ordre.
-- Règle : AUCUNE quête du journal n'est écartée. Celles qui sont trop dures pour l'instant
-- (ou de groupe) passent simplement à la fin du trajet ; la quête suivie passe en premier.
local _, ns = ...
local Planner = {}
ns.Planner = Planner
local Data, Geo, Solver = ns.Data, ns.Geo, ns.Solver

local MERGE_YARDS = 120 -- objectifs à moins de cette distance = une seule étape
local PICKUP_YARDS = 50 -- donneur de quête « au passage » à moins de cette distance d'une étape
local WORK = { monster = 25, killcredit = 25, item = 35, object = 15, event = 15, log = 10, spell = 20 }
local TURNIN_TIME = 15
local ESTIMATE_BUDGET = 80

-- Niveaux de priorité : -1 = quête suivie, 0 = maintenant, 1 = à la fin (trop dure / groupe).
local TIER_FOCUS, TIER_NOW, TIER_LATER = -1, 0, 1
-- Mode région : ce qui se fait hors de la région où tu es passe après (mais avant le « plus tard »).
local TIER_AWAY = 0.5
local REGION_MAX = 10 -- quêtes de la région proposées au plus à la fois
local REGION_MAX_TIME = 1500 -- détour + travail max pour une quête de la région (s)
-- Une quête « plus tard » avancée (on aura le niveau en route) forme son propre groupe d'étapes.
local PHASE_PROMOTED = 10
local TOUR_YARDS = 160 -- rendus enchaînés à moins de cette distance = une « tournée »
local KILL_XP_SHARE = 0.7 -- prudence : on ne compte que 70 % de l'XP des monstres à tuer

-- XP pour passer au niveau suivant (Classic) ; mise à l'échelle sur UnitXPMax du niveau actuel.
local NEXT_XP = {
	400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400, 16000,
	17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
	50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800,
	117500, 123200, 129100, 135100, 141200, 147500, 153900, 160400, 167100, 173900, 180800, 187900,
	195000, 202300, 209800,
}

local function ZeroDiff(level)
	if level < 8 then return 5 elseif level < 10 then return 6 elseif level < 12 then return 7
	elseif level < 16 then return 8 elseif level < 20 then return 9 elseif level < 30 then return 11
	elseif level < 40 then return 12 elseif level < 45 then return 13 elseif level < 50 then return 14
	elseif level < 55 then return 15 elseif level < 60 then return 16 end
	return 17
end

local function GrayLevel(level)
	if level <= 5 then
		return 0
	elseif level <= 39 then
		return level - 5 - math.floor(level / 10)
	elseif level <= 59 then
		return level - 1 - math.floor(level / 5)
	end
	return level - 9
end

-- XP d'un monstre (formule Classic, sans repos ni élite).
local function KillXP(level, mobLevel)
	if not mobLevel or mobLevel <= 0 or mobLevel <= GrayLevel(level) then
		return 0
	end
	local base = level * 5 + 45
	if mobLevel >= level then
		return base * (1 + 0.05 * math.min(mobLevel - level, 4))
	end
	return base * (1 - (level - mobLevel) / ZeroDiff(level))
end
-- (repris par Montee.lua : frise de montée)
Planner.NEXT_XP, Planner.GrayLevel, Planner.KillXP = NEXT_XP, GrayLevel, KillXP

-- Soirée planifiée (« j'ai 1 h 30 ») : l'auberge où finir, puis ce qui est gardé pour la soirée suivante.
-- Région suivante (journal presque fini) : après le journal, avant l'auberge.
local TIER_NEXT, TIER_INN, TIER_AFTER = 0.55, 0.6, 0.75
Planner.TIER_NEXT, Planner.TIER_INN, Planner.TIER_AFTER = TIER_NEXT, TIER_INN, TIER_AFTER

local function Phase(q)
	if q.candidate and q.chainOf then
		-- une suite garde ses propres étapes : mêlées au rendu de la quête d'avant, elles tourneraient en rond
		return "c" .. q.id
	end
	-- (les autres quêtes proposées se mêlent aux étapes voisines : même zone de chasse, même PNJ)
	-- (une quête de donjon à préparer rejoint l'étape du donjon : on y va de toute façon)
	return q.promoted and PHASE_PROMOTED or (q.tier or TIER_NOW)
end

-- Quêtes proposées (pas encore prises) et étape réparer / vendre.
local CANDIDATE_MAX = 4 -- au plus tant de quêtes proposées à la fois
local CANDIDATE_LOOK = 16 -- quêtes évaluées au plus (les plus proches du trajet)
local CANDIDATE_NEAR = 300 -- donneur à moins de cette distance d'une étape (yards)
local CANDIDATE_MAX_TIME = 900 -- détour + travail au-delà duquel on ne propose pas (s)
local CANDIDATE_COUNT_GUESS = 8 -- nombre d'objets/monstres supposé (la base n'a pas les quantités)
local SERVICE_DEADLINE = 1800 -- l'arrêt réparer/vendre se fait dans les ~30 premières minutes
local HEARTH_CAST = 15 -- incantation de la pierre de foyer + chargement (s)
local HEARTH_MIN_GAIN = 120 -- on ne la conseille que si elle fait gagner au moins 2 min
local BIND_MIN_GAIN = 180 -- une autre auberge n'est conseillée que si elle fait gagner 3 min de plus
local PICKUP_TIME = 10

local VERBS = {
	monster = "Tuer", killcredit = "Tuer", item = "Récupérer", object = "Utiliser",
	spell = "Utiliser", event = "", log = "", reputation = "Réputation",
}

-- Les points hors des zones trop hautes pour le niveau `level` ; vide s'ils y sont tous (pour ce qu'on PROPOSE :
-- quêtes à prendre, marchands, maîtres ; une quête du journal, elle, passe seulement à la fin du trajet).
local function SafeOnly(points, level)
	local safe, danger = Data.SafePoints(points, level)
	if danger then
		return {}
	end
	return safe
end

-- Contexte du calcul en cours : rythme mesuré du joueur (secondes par unité), en groupe ou non.
local CONTEXT = { rates = {}, targets = {}, slots = {}, grouped = false, gearQuests = {} }

-- Une mesure précise (ce monstre-là, cet objectif-là) compte d'autant plus qu'elle a d'échantillons :
-- avec 2 mesures, moitié elle / moitié la moyenne plus générale.
local SHRINK = 2
local function Blend(per, e)
	if type(e) == "table" and type(e.v) == "number" and (e.n or 0) > 0 then
		return (e.n * e.v + SHRINK * per) / (e.n + SHRINK)
	end
	return per
end

-- Secondes par unité (monstre tué, objet obtenu…) : ton rythme général, puis celui sur cette cible,
-- puis celui sur cet objectif précis.
local function PerUnit(objective)
	local per = CONTEXT.rates[objective.type or ""] or WORK[objective.type or ""] or 30
	per = Blend(per, objective.target and CONTEXT.targets[objective.target])
	per = Blend(per, objective.slot and CONTEXT.slots[objective.slot])
	return per
end

local function Work(objective)
	local per = PerUnit(objective)
	local left = 1
	if objective.numRequired and objective.numRequired > 0 then
		left = math.max(1, objective.numRequired - (objective.numFulfilled or 0))
	end
	if objective.type == "event" then
		left = 1
	end
	return per * left
end

local function Dist(a, b)
	return Geo.Yards(a, b)
end

local function Short(text, max)
	if #text <= max then
		return text
	end
	return text:sub(1, max - 1) .. "…"
end

-- « Géomancienne Tranchecrin : 0/8 » -> « Géomancienne Tranchecrin 0/8 »
local function Compact(text)
	text = Data.CleanText(text)
	return (text:gsub("[ \194\160\226\128\175]*:[ \194\160]*(%d+/%d+)%s*$", " %1"))
end

-------------------------------------------------------------------------------
-- 1. Tâches
-------------------------------------------------------------------------------
local function ChooseClusters(tasks, player)
	for _, t in ipairs(tasks) do
		if t.fixedAt then
			-- Quête proposée : la zone a déjà été choisie (la plus proche du trajet).
			t.at, t.cands = t.fixedAt, { t.fixedAt }
		else
			local best = t.clusters[1]
			local cands = {}
			for _, c in ipairs(t.clusters) do
				if #cands < 4 and (c == best or c.count >= math.max(2, best.count * 0.3)) then
					cands[#cands + 1] = c
				end
			end
			-- La zone la plus proche du joueur reste candidate, même petite.
			local nearest, nearestD
			for _, c in ipairs(t.clusters) do
				local d = Dist(player, c)
				if d and (not nearestD or d < nearestD) then
					nearest, nearestD = c, d
				end
			end
			if nearest and nearestD < 400 then
				local present = false
				for _, c in ipairs(cands) do
					present = present or c == nearest
				end
				if not present then
					cands[#cands + 1] = nearest
				end
			end
			t.cands = cands
			local pick, score
			for _, c in ipairs(cands) do
				local d = Dist(player, c) or 5000
				local s = c.count / (1 + d / 1000)
				if not pick or s > score then
					pick, score = c, s
				end
			end
			t.at = pick
		end
	end
	-- Regroupement : préférer une zone qui tombe à côté d'un autre objectif.
	for _, t in ipairs(tasks) do
		local bestC, bestN
		for _, c in ipairs(t.cands) do
			if c.count >= t.clusters[1].count * 0.35 then
				local neighbours = 0
				for _, u in ipairs(tasks) do
					if u ~= t then
						local d = Dist(c, u.at)
						if d and d <= MERGE_YARDS then
							neighbours = neighbours + 1
						end
					end
				end
				if neighbours > 0 and (not bestN or neighbours > bestN) then
					bestC, bestN = c, neighbours
				end
			end
		end
		if bestC and not t.fixedAt then
			t.at = bestC
		end
	end
end

local function NearestPoint(points, ref)
	local best, bestD
	for _, p in ipairs(points) do
		local d = Dist(ref, p) or math.huge
		if not best or d < bestD then
			best, bestD = p, d
		end
	end
	return best
end

-- Partage de groupe (guide) : ajoute les quêtes des équipiers au journal. Une quête commune garde
-- les objectifs encore à faire pour quelqu'un ; une quête qu'on n'a pas est lue dans la base Questie.
local function MergeGroup(log, opts)
	if not opts.groupQuests then
		return
	end
	local me = opts.me or "toi"
	local mine = {}
	for _, q in ipairs(log) do
		mine[q.id] = q
		q.owners = { me }
	end
	for _, entry in ipairs(opts.groupQuests) do
		local q = mine[entry.id]
		if q then
			for _, name in ipairs(entry.members) do
				q.owners[#q.owners + 1] = name
			end
			local quest = Data.Quest(q.id)
			for i, o in ipairs(entry.objectives) do
				local own = q.objectives[i]
				if o.have < o.need and own and own.finished then
					local _, label = Data.ObjectiveLabel(quest, i)
					q.objectives[i] = {
						type = own.type, text = (label or own.text or "objectif") .. " : " .. o.have .. "/" .. o.need,
						numFulfilled = o.have, numRequired = o.need, finished = false,
					}
					q.complete, q.talkOnly = false, false
				end
			end
		else
			local ext = Data.ExternalQuest(entry)
			if ext then
				log[#log + 1] = ext
			end
		end
	end
end

function Planner.Tasks(opts, plan, yield)
	local level = plan.level
	local log = Data.ReadLog()
	plan.logCount = #log
	MergeGroup(log, opts)
	plan.quests = log
	local side = plan.side
	local objTasks, turnins, dungeonTasks = {}, {}, {}
	plan.turninTask = {}
	-- Route des rendus : seulement les quêtes terminées (et les « va parler à… »).
	local work = log
	if opts.turninOnly then
		plan.turninOnly = true
		work = {}
		for _, q in ipairs(log) do
			if (q.complete or q.talkOnly) and not q.failed then
				work[#work + 1] = q
			else
				q.status = "pas encore finie (route des rendus)"
			end
		end
	end
	for _, q in ipairs(work) do
		yield()
		local quest = Data.Quest(q.id)
		q.xp = (not q.external) and Data.QuestXP(q.id) or 0 -- l'XP d'une quête d'équipier n'est pas pour toi
		local focused = opts.focus == q.id
		if focused then
			plan.focusInLog, plan.focusTitle = true, q.title
		end
		q.tier = focused and TIER_FOCUS or TIER_NOW
		-- Objet déjà dans tes sacs que le journal du jeu ne compte pas : on ne te renvoie pas le chercher (le PNJ du
		-- rendu le prend si le serveur l'a compté). Au bout de 20 min sans mise à jour, le jeu a raison (`bagGiveUp`).
		if not (q.failed or q.complete or q.talkOnly or q.external) then
			local found, all = false, true
			-- (une copie : les tables rendues par le jeu ne sont pas à nous)
			local list = {}
			for i, o in ipairs(q.objectives) do
				list[i] = o
			end
			q.objectives = list
			for i, original in ipairs(list) do
				local o = original
				if not o.finished then
					local have, item, name = Data.ItemsInBags(quest, i, o)
					local key = have and (q.id .. ":" .. item)
					if key then
						plan.bagSeen = plan.bagSeen or {}
						plan.bagSeen[key] = true
					end
					if have and not (opts.bagGiveUp or {})[key] then
						plan.inBags = plan.inBags or {}
						plan.inBags[#plan.inBags + 1] = { id = q.id, title = q.title, key = key, name = name,
							counted = o.numFulfilled or 0, need = o.numRequired, have = have }
						o = {}
						for k, v in pairs(original) do
							o[k] = v
						end
						o.finished, o.inBags, found = true, have, true
						list[i] = o
					else
						all = false
					end
				end
			end
			if found and all then
				q.complete, q.inBags = true, true
			end
		end
		if q.failed then
			q.status = "échouée"
			side.failed[#side.failed + 1] = q
		elseif q.complete or q.talkOnly then
			q.status = q.inBags and "à rendre (l'objet est dans tes sacs ; le jeu ne l'a pas encore compté)" or "à rendre"
			local points = Data.FinisherPoints(quest)
			-- Questie ne sait pas où la rendre : repère du jeu (ou de DonData).
			local hint = #points == 0 and not q.external and Data.QuestHint(q.id, true)
			if hint then
				points = { hint }
				q.hint = hint.hint
			end
			if #points > 0 then
				-- rendu dans une zone trop haute pour toi : à la fin du trajet (sauf la quête suivie)
				local safe, danger = Data.SafePoints(points, level)
				local t = { q = q, point = NearestPoint(safe, plan.player) }
				if danger and not focused then
					t.tier, t.late = TIER_LATER, Data.DangerText(danger)
					q.status = "à rendre, à la fin (" .. t.late .. ")"
				end
				turnins[#turnins + 1] = t
				plan.turninTask[q.id] = t
			else
				q.status = "position inconnue"
				side.unknown[#side.unknown + 1] = { q = q, what = "où la rendre" }
			end
		elseif Data.Flag("IsPvPQuest", q.id) then
			q.status = "JcJ"
			side.pvp[#side.pvp + 1] = q
		else
			local late
			if q.level >= level + 3 then
				late = "niveau " .. q.level
			elseif not opts.grouped and ((q.group or 0) > 1 or Data.Flag("IsGroupQuest", q.id)) then
				late = "groupe" -- en groupe, elle redevient une quête comme les autres
			end
			local group = late == "groupe"
			local gate = q.level or 0
			local mine, dungeonObjs, unknown = {}, {}, {}
			for i, o in ipairs(q.objectives) do
				if not o.finished then
					o.slot = q.id .. ":" .. i
					o.target = Data.ObjectiveTarget(quest, i, o.type)
					local points, meta = Data.ObjectivePoints(quest, i)
					-- seulement les endroits hors des zones trop hautes ; s'il n'y a que ça : à la fin du trajet
					local safe, danger = Data.SafePoints(points, level)
					points = safe
					if danger then
						gate = math.max(gate, danger.low - 1)
						late = late or Data.DangerText(danger)
					end
					if meta.level then
						gate = math.max(gate, meta.level)
					end
					if not late and meta.level and meta.level >= level + 3 then
						late = "monstres niveau " .. meta.level
					end
					-- Élites de ton niveau (ou presque) : à plusieurs, sauf si tu es déjà en groupe.
					local elite = meta.eliteLevel and meta.eliteLevel >= level - 2 and meta.eliteLevel or nil
					if elite and not opts.grouped then
						group = true -- le niveau seul ne suffit pas : pas d'avance automatique
						if not late or late:find("^monstres") then
							late = "élites niveau " .. elite
						end
					end
					if #points > 0 then
						mine[#mine + 1] = {
							kind = "obj", q = q, index = i, objective = o,
							clusters = Data.Clusters(points), names = meta.names, mobLevel = meta.level,
							elite = meta.eliteLevel,
						}
					elseif next(meta.dungeons) then
						for areaId in pairs(meta.dungeons) do
							dungeonObjs[#dungeonObjs + 1] = { areaId = areaId, index = i, objective = o }
							break
						end
					else
						-- Questie ne sait pas où : repère du jeu (ou de DonData), une zone large autour du point.
						local hint = not q.external and Data.QuestHint(q.id, false)
						if hint then
							mine[#mine + 1] = {
								kind = "obj", q = q, index = i, objective = o, names = {}, hint = hint.hint,
								clusters = { { count = 1, map = hint.map, x = hint.x, y = hint.y, wx = hint.wx, wy = hint.wy,
									inst = hint.inst, radius = 80 } },
							}
							q.hint = hint.hint
						else
							unknown[#unknown + 1] = o
						end
					end
				end
			end
			if late and not focused then
				q.tier, q.late = TIER_LATER, late
				-- Faisable dès ce niveau (même règle que « trop dure » : écart de 3 niveaux ou plus).
				q.needLevel = not group and (gate - 2) or nil
			end
			q.status = q.late and ("à la fin (" .. q.late .. ")") or "sur le trajet"
			if #dungeonObjs > 0 and not (opts.includeDungeons or focused) then
				q.status = "donjon (option désactivée)"
				for _, d in ipairs(dungeonObjs) do
					local entry = side.dungeons[d.areaId]
					if not entry then
						entry = { areaId = d.areaId, name = Data.DungeonName(d.areaId), quests = {} }
						side.dungeons[d.areaId] = entry
					end
					if entry.quests[#entry.quests] ~= q then
						entry.quests[#entry.quests + 1] = q
					end
				end
			else
				for _, t in ipairs(mine) do
					objTasks[#objTasks + 1] = t
				end
				for _, d in ipairs(dungeonObjs) do
					dungeonTasks[#dungeonTasks + 1] = { kind = "dungeon", q = q, areaId = d.areaId, index = d.index, objective = d.objective }
				end
				if #unknown > 0 then
					q.status = (#mine > 0 or #dungeonObjs > 0) and "en partie inconnue" or "position inconnue"
					side.unknown[#side.unknown + 1] = { q = q, what = Compact(unknown[1].text) }
				else
					local points = Data.FinisherPoints(quest)
					local guess = #points == 0 and not q.external and Data.TurnInGuess(q.id)
					if guess then
						points = { guess } -- (DonData : PNJ du rendu connu de ses données ou de ses joueurs)
					end
					if #points > 0 then
						local safe, danger = Data.SafePoints(points, level)
						local t = { q = q, point = NearestPoint(safe, plan.player), after = true }
						if danger and not focused and (q.tier or TIER_NOW) < TIER_LATER then
							t.tier, t.late = TIER_LATER, Data.DangerText(danger) -- le rendu à la fin, les objectifs avant
						end
						turnins[#turnins + 1] = t
						plan.turninTask[q.id] = t
					else
						side.unknown[#side.unknown + 1] = { q = q, what = "où la rendre" }
					end
				end
			end
		end
	end
	return objTasks, turnins, dungeonTasks
end

-------------------------------------------------------------------------------
-- 2. Étapes
-------------------------------------------------------------------------------
local function NewStop(kind, at, phase)
	return {
		kind = kind, map = at.map, x = at.x, y = at.y, wx = at.wx, wy = at.wy, inst = at.inst,
		tasks = {}, quests = {}, questSet = {}, pickups = {}, work = 0, tier = TIER_LATER, phase = phase,
	}
end

local function AddTask(stop, t, work)
	stop.tasks[#stop.tasks + 1] = t
	stop.work = stop.work + work
	stop.tier = math.min(stop.tier, t.tier or t.q.tier or TIER_NOW)
	if t.q.promoted then
		stop.promoted = true
		stop.gateLevel = math.max(stop.gateLevel or 0, t.q.needLevel or 0)
	end
	if t.q.candidate then
		stop.candidate = t.q
	end
	if not stop.questSet[t.q.id] then
		stop.questSet[t.q.id] = true
		stop.quests[#stop.quests + 1] = t.q
	end
end

local function Describe(stop)
	local zone = Geo.ZoneName(stop.map)
	local lines = {}
	local owners, seen = nil, {}
	for _, q in ipairs(stop.quests) do
		for _, name in ipairs(q.owners or {}) do
			if not seen[name] then
				seen[name] = true
				owners = owners or {}
				owners[#owners + 1] = name
			end
		end
	end
	stop.owners = owners
	if stop.kind == "turnin" then
		local names = {}
		for _, q in ipairs(stop.quests) do
			names[#names + 1] = "« " .. q.title .. " »"
			lines[#lines + 1] = "Rendre « " .. q.title .. " »"
			-- Récompense qui t'améliore (fenêtre Équipement) : à choisir au rendu.
			local reward = not q.external and CONTEXT.gearQuests and CONTEXT.gearQuests[q.id]
			if reward then
				lines[#lines + 1] = "   Récompense à prendre : " .. tostring(reward.name) .. " " .. tostring(reward.gain)
					.. " (" .. tostring(reward.slot) .. ")"
				stop.reward = reward
			end
		end
		stop.title = #names == 1 and ("Rendre " .. names[1]) or ("Rendre " .. #names .. " quêtes")
		stop.subtitle = (stop.npcName and (stop.npcName .. " · ") or "") .. zone
		if stop.reward then
			stop.subtitle = stop.subtitle .. " · |cff00ff00récompense pour toi|r"
		end
	elseif stop.kind == "area" then
		-- Regroupe par verbe : « Tuer : A 0/8, B 0/8 · Récupérer : C 0/1 »
		local order, groups = {}, {}
		for _, t in ipairs(stop.tasks) do
			local verb = VERBS[t.objective.type or ""] or "Faire"
			if not groups[verb] then
				groups[verb] = {}
				order[#order + 1] = verb
			end
			local text = Compact(t.objective.text)
			table.insert(groups[verb], text)
			lines[#lines + 1] = (verb ~= "" and (verb .. " : ") or "") .. text .. "  (" .. t.q.title .. ")"
		end
		local parts = {}
		for _, verb in ipairs(order) do
			parts[#parts + 1] = (verb ~= "" and (verb .. " : ") or "") .. table.concat(groups[verb], ", ")
		end
		stop.title = Short(table.concat(parts, " · "), 80)
		for _, t in ipairs(stop.tasks) do
			if t.elite then
				stop.elite = math.max(stop.elite or 0, t.elite)
			end
		end
		if stop.elite then
			lines[#lines + 1] = "Attention : élites (niveau " .. stop.elite .. ")."
		end
		local titles = {}
		for _, q in ipairs(stop.quests) do
			titles[#titles + 1] = q.candidate and (q.title .. " (nouvelle)") or q.title
		end
		stop.subtitle = Short(table.concat(titles, ", "), 60) .. " · " .. zone
	elseif stop.kind == "dungeon" then
		stop.title = "Donjon : " .. stop.dungeonName
		local titles = {}
		for _, t in ipairs(stop.tasks) do
			lines[#lines + 1] = Compact(t.objective.text) .. "  (" .. t.q.title .. ")"
		end
		for _, q in ipairs(stop.quests) do
			titles[#titles + 1] = q.title
		end
		stop.subtitle = Short(table.concat(titles, ", "), 60) .. " · entrée"
	elseif stop.kind == "pickup" and #stop.pickups > 1 then
		stop.title = "Prendre " .. #stop.pickups .. " quêtes"
		stop.subtitle = (stop.npcName and (stop.npcName .. " · ") or "") .. zone
		local xp, time = 0, 0
		for _, q in ipairs(stop.candidates or {}) do
			xp, time = xp + (q.xp or 0), time + (q.extraTime or 0)
		end
		for _, p in ipairs(stop.pickups) do
			lines[#lines + 1] = "Prendre « " .. (p.name or "?") .. " »" .. (p.level and (" (niv " .. p.level .. ")") or "")
		end
		lines[#lines + 1] = string.format("Environ %d XP pour ~%d min en tout.", xp, math.floor(time / 60 + 0.5))
		lines[#lines + 1] = "Pas envie ? Clic droit > Passer l'étape."
	elseif stop.kind == "pickup" then
		local p = stop.pickups[1]
		local q = stop.candidate
		if q and q.chainOf then
			stop.title = "Prendre la suite « " .. (p.name or "?") .. " »"
		else
			stop.title = "Prendre « " .. (p.name or "?") .. " »" .. (p.level and (" (niv " .. p.level .. ")") or "")
		end
		stop.subtitle = (stop.npcName and (stop.npcName .. " · ") or "") .. zone
		lines[#lines + 1] = stop.title
		if q then
			lines[#lines + 1] = q.chainOf and ("Suite de « " .. q.chainOf.title .. " », proposée parce qu'elle tombe sur ton trajet.")
				or q.prepFor and ("À prendre avant le donjon « " .. q.prepFor .. " » : tu y vas de toute façon.")
				or q.inRegion and "Quête de la région : on la fait pendant que tu y es."
				or "Nouvelle quête proposée : ses objectifs tombent sur ton trajet."
			lines[#lines + 1] = string.format("Environ %d XP pour ~%d min de plus.", q.xp or 0, math.floor((q.extraTime or 0) / 60 + 0.5))
			lines[#lines + 1] = "Pas envie ? Clic droit > Passer l'étape."
		end
	elseif stop.kind == "service" then
		stop.title = stop.service.title
		stop.subtitle = (stop.npcName and (stop.npcName .. " · ") or "") .. zone
		for _, line in ipairs(stop.service.why) do
			lines[#lines + 1] = line
		end
	end
	for k, p in ipairs(stop.pickups) do
		if stop.kind ~= "pickup" and k <= 3 then
			lines[#lines + 1] = "Prendre aussi « " .. (p.name or "?") .. " »"
		end
	end
	if stop.tier == TIER_LATER then
		local why = {}
		for _, t in ipairs(stop.tasks) do
			if t.late then
				why[#why + 1] = t.late -- (un rendu dans une zone trop haute)
			end
		end
		for _, q in ipairs(stop.quests) do
			if q.late then
				why[#why + 1] = q.late
			end
		end
		stop.lateWhy = why[1]
	end
	-- Lieu qui ne vient pas de Questie (repère du jeu, DonData) : on le dit.
	for _, t in ipairs(stop.tasks) do
		local source = t.hint or (t.point and t.point.hint)
		if source then
			lines[#lines + 1] = "Lieu donné par " .. (source == "DonData" and "DonData" or "le jeu")
				.. " (Questie ne le connaît pas) : approximatif."
			stop.hint = source
			break
		end
	end
	stop.details = lines
end

-- Un rendu chez un même PNJ est scindé par priorité (sinon : contraintes circulaires).
local function AddTurnin(stops, byGiver, t)
	local phase = Phase(t.q)
	if t.q.candidate and not t.q.chainOf and not t.q.prep then
		-- Rendus des quêtes proposées : regroupés entre eux chez un même PNJ, mais pas avec ceux du
		-- journal (un rendu du journal dont l'objectif est loin les retarderait tous, journal plein).
		phase = "cand" .. tostring(t.q.tier or TIER_NOW)
	end
	local base = t.point.npc and ("n" .. t.point.npc) or t.point.object and ("o" .. t.point.object) or ("q" .. t.q.id)
	local giver = base .. "#" .. phase
	local s = byGiver[giver]
	if not s then
		s = NewStop("turnin", t.point, phase)
		s.npc = t.point.npc
		s.npcName = t.point.name
		s.giver = giver
		s.radius = 8
		byGiver[giver] = s
		stops[#stops + 1] = s
	end
	AddTask(s, t, TURNIN_TIME)
end

function Planner.Stops(opts, plan, objTasks, turnins, dungeonTasks)
	local stops = {}
	ChooseClusters(objTasks, plan.player)
	table.sort(objTasks, function(a, b)
		return a.at.count > b.at.count
	end)
	for _, t in ipairs(objTasks) do
		-- On ne fusionne qu'entre étapes de même priorité : une quête « plus tard » ne se glisse pas
		-- dans une étape « maintenant » (sinon elle serait faite trop tôt, ou créerait des cycles).
		local phase = Phase(t.q)
		local home
		for _, s in ipairs(stops) do
			if s.kind == "area" and s.phase == phase then
				local d = Dist(s, t.at)
				if d and d <= MERGE_YARDS then
					home = s
					break
				end
			end
		end
		if not home then
			home = NewStop("area", t.at, phase)
			home.radius = t.at.radius
			stops[#stops + 1] = home
		else
			home.radius = math.max(home.radius, t.at.radius)
		end
		AddTask(home, t, Work(t.objective))
	end
	local byDungeon, missing = {}, {}
	for _, t in ipairs(dungeonTasks) do
		local phase = Phase(t.q)
		local dkey = t.areaId .. ":" .. phase
		local s = byDungeon[dkey]
		if not s then
			local entrance = Data.DungeonEntrance(t.areaId)
			if entrance then
				s = NewStop("dungeon", entrance, phase)
				s.areaId = t.areaId
				s.dungeonName = Data.DungeonName(t.areaId)
				s.radius = 30
				byDungeon[dkey] = s
				stops[#stops + 1] = s
			end
		end
		if s then
			AddTask(s, t, Work(t.objective))
		else
			-- Entrée inconnue : la quête ne peut pas être finie, donc pas de rendu sur le trajet.
			missing[t.q.id] = true
			plan.side.unknown[#plan.side.unknown + 1] = { q = t.q, what = "entrée du donjon" }
		end
	end
	local byGiver = {}
	for _, t in ipairs(turnins) do
		if not (t.after and missing[t.q.id]) then
			AddTurnin(stops, byGiver, t)
		end
	end
	return stops
end

local function StopKey(stop)
	local parts = {}
	for _, t in ipairs(stop.tasks) do
		parts[#parts + 1] = t.q.id .. (t.index and ("." .. t.index) or "")
	end
	table.sort(parts)
	if stop.kind == "turnin" then
		return "T:" .. stop.giver .. ":" .. table.concat(parts, ",")
	elseif stop.kind == "dungeon" then
		return "D:" .. stop.areaId .. ":" .. tostring(stop.phase)
	elseif stop.kind == "pickup" then
		local ids = {}
		for _, p in ipairs(stop.pickups) do
			ids[#ids + 1] = p.id
		end
		table.sort(ids)
		return "P:" .. (ids[1] and table.concat(ids, ",") or "0")
	elseif stop.kind == "service" then
		return "S:" .. stop.service.key
	end
	return "A:" .. table.concat(parts, ",")
end

-- Quêtes à prendre près des étapes (ou au départ quand le journal est presque vide).
function Planner.Pickups(opts, plan, stops, yield)
	local level = plan.level
	local candidates = {}
	local count = 0
	local inLog = {}
	for _, q in ipairs(plan.quests or {}) do
		inLog[q.id] = true
	end
	for id in pairs(Data.AvailableQuests()) do
		count = count + 1
		if count % 15 == 0 then
			yield()
		end
		local quest = not (plan.candidateSet and plan.candidateSet[id]) and Data.Quest(id)
		local lvl = quest and quest.level
		if quest and lvl and lvl > 0 and lvl <= level + 2 and lvl >= level - 4
			and not Data.Flag("IsRaidQuest", id) and not Data.Flag("IsPvPQuest", id) and not inLog[id] and Data.CanTake(id, quest, inLog) then
			local points = SafeOnly(Data.StarterPoints(quest), level)
			if #points > 0 then
				candidates[#candidates + 1] = { id = id, name = quest.name, level = lvl, points = points }
			end
		end
	end
	for _, c in ipairs(candidates) do
		for _, s in ipairs(stops) do
			if s.kind ~= "pickup" and #s.pickups < 3 then
				local p = NearestPoint(c.points, s)
				local d = p and Dist(p, s)
				if d and d <= PICKUP_YARDS then
					s.pickups[#s.pickups + 1] = { id = c.id, name = c.name, level = c.level }
					c.used = true
					break
				end
			end
		end
	end
	-- Journal presque vide : aller chercher les quêtes les plus proches.
	if #stops < 3 then
		table.sort(candidates, function(a, b)
			local da = Dist(plan.player, NearestPoint(a.points, plan.player)) or math.huge
			local db = Dist(plan.player, NearestPoint(b.points, plan.player)) or math.huge
			return da < db
		end)
		local added = 0
		for _, c in ipairs(candidates) do
			if added >= 4 then
				break
			end
			local p = NearestPoint(c.points, plan.player)
			local d = Dist(plan.player, p)
			if not c.used and d and d < 2500 then
				local s = NewStop("pickup", p)
				s.npc = p.npc
				s.npcName = p.name
				s.radius = 8
				s.tier = TIER_NOW
				s.pickups[1] = { id = c.id, name = c.name, level = c.level }
				s.work = 10
				stops[#stops + 1] = s
				added = added + 1
			end
		end
	end
end

-------------------------------------------------------------------------------
-- 3. Ordre
-------------------------------------------------------------------------------
local function Precedence(stops, region)
	local before = {}
	local where = {}
	for idx, s in ipairs(stops) do
		for _, t in ipairs(s.tasks) do
			where[t] = idx
		end
	end
	-- 1. Contraintes « dures » : objectifs avant le rendu ; prendre une quête avant de la faire ;
	--    une suite après le rendu de la quête d'avant.
	local workAt, handAt = {}, {}
	for idx, s in ipairs(stops) do
		for _, t in ipairs(s.tasks) do
			if s.kind == "turnin" then
				if t.after then
					handAt[t.q.id] = idx
				end
			else
				workAt[t.q.id] = workAt[t.q.id] or {}
				workAt[t.q.id][idx] = true
			end
		end
	end
	for questId, h in pairs(handAt) do
		for idx in pairs(workAt[questId] or {}) do
			before[#before + 1] = { idx, h }
		end
	end
	for idx, s in ipairs(stops) do
		if s.kind == "pickup" and s.candidate then
			for _, q in ipairs(s.candidates or { s.candidate }) do
				for j, o in ipairs(stops) do
					if j ~= idx and o.kind ~= "pickup" and o.questSet[q.id] then
						before[#before + 1] = { idx, j }
					end
				end
				local gi = q.after and where[q.after]
				if gi then
					before[#before + 1] = { gi, idx }
				end
			end
		end
	end
	-- 2. Mode région : ce qui est hors de la région passe après. Une étape qui DOIT venir après une
	--    étape hors région (un rendu ici dont l'objectif est ailleurs) passe après, elle aussi.
	if region then
		for _, s in ipairs(stops) do
			if s.tier == TIER_NOW and s.kind ~= "service" and Geo.Zone(s.map) ~= region then
				s.tier, s.away = TIER_AWAY, true
			end
		end
		local changed = true
		while changed do
			changed = false
			for _, pair in ipairs(before) do
				local a, b = stops[pair[1]], stops[pair[2]]
				if a.tier == TIER_AWAY and b.tier == TIER_NOW and b.kind ~= "service" then
					b.tier, b.away = TIER_AWAY, true
					changed = true
				end
			end
		end
	end
	-- 3. Priorités : quête suivie, puis le reste (la région d'abord), puis ce qui est trop dur pour l'instant.
	-- (3e champ = contrainte « souple » : elle cède devant une étape que le joueur force en premier.)
	-- Une étape avancée reste libre face aux étapes « plus tard » : elle peut s'y joindre si c'est plus court.
	for i, a in ipairs(stops) do
		for j, b in ipairs(stops) do
			-- (l'auberge de fin de soirée et la région suivante restent avant ce qui est trop dur pour l'instant)
			local free = a.promoted or a.candidate or (a.kind == "service" and not a.service.urgent
				and a.service.kind ~= "inn" and a.service.kind ~= "region")
			if a.tier < b.tier and not (free and b.tier == TIER_LATER) then
				before[#before + 1] = { i, j, true }
			end
		end
	end
	-- 4. Quêtes avancées : après toutes les étapes qui rapportent l'XP du niveau requis.
	for idx, s in ipairs(stops) do
		if s.promoted then
			local seen = {}
			for _, t in ipairs(s.tasks) do
				for _, g in ipairs(t.q.gateTasks or {}) do
					local gi = where[g]
					if gi and gi ~= idx and not seen[gi] then
						seen[gi] = true
						before[#before + 1] = { gi, idx, true }
					end
				end
			end
		end
	end
	-- 5. Réparer / vendre : avant les étapes qui tombaient au-delà de ~30 min de trajet.
	for idx, s in ipairs(stops) do
		if s.kind == "service" then
			for j, o in ipairs(stops) do
				if o.afterService and o.tier >= s.tier then
					before[#before + 1] = { idx, j, true }
				end
			end
		end
	end
	return before
end

local function Respects(order, before)
	local pos = {}
	for k, idx in ipairs(order) do
		pos[idx] = k
	end
	for _, pair in ipairs(before) do
		if pos[pair[1]] and pos[pair[2]] and pos[pair[1]] > pos[pair[2]] then
			return false
		end
	end
	return true
end

-------------------------------------------------------------------------------
-- 4. Prévision de niveau
-------------------------------------------------------------------------------
local function SafeNumber(value)
	if issecretvalue and issecretvalue(value) then
		return nil
	end
	return type(value) == "number" and value == value and value or nil
end

-- XP du niveau « level », mise à l'échelle sur la vraie barre d'XP du niveau actuel.
local function LevelMax(level, curLevel, curMax)
	if level == curLevel then
		return curMax
	end
	local last = #NEXT_XP
	local base = NEXT_XP[curLevel] or NEXT_XP[last]
	local want = NEXT_XP[level] or (NEXT_XP[last] * 1.05 ^ (level - last))
	return want * (curMax / base)
end

-- XP rapportée par une étape : récompenses des rendus + 70 % des monstres à tuer.
-- Renvoie l'XP totale, et la part qui vient des monstres (doublée tant qu'il reste du repos).
local function StopXP(s, level)
	local quest, kills = 0, 0
	if s.kind == "turnin" then
		for _, q in ipairs(s.quests) do
			quest = quest + (q.xp or 0)
		end
	else
		for _, t in ipairs(s.tasks) do
			local o = t.objective
			if o and o.type == "monster" and t.mobLevel then
				local left = math.max(0, (o.numRequired or 0) - (o.numFulfilled or 0))
				kills = kills + left * KillXP(level, t.mobLevel) * KILL_XP_SHARE
			end
		end
	end
	return quest + kills, kills
end

-- Niveau atteint après chaque étape du trajet (estimation prudente).
local function Simulate(plan, stops, order)
	local start = plan.level
	local level = start
	local cap = SafeNumber(GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
	local xp = SafeNumber(UnitXP and UnitXP("player")) or 0
	local curMax = SafeNumber(UnitXPMax and UnitXPMax("player"))
	if not curMax or curMax <= 0 then
		curMax = NEXT_XP[start] or NEXT_XP[#NEXT_XP]
	end
	local max = curMax
	local rested = SafeNumber(GetXPExhaustion and GetXPExhaustion()) or 0
	local after = {}
	for k, idx in ipairs(order) do
		local gain, kills = StopXP(stops[idx], level)
		-- Repos : l'XP des monstres est doublée jusqu'à épuisement de la réserve.
		local bonus = math.min(rested, kills)
		rested = rested - bonus
		xp = xp + gain + bonus
		local up
		while level < cap and xp >= max do
			xp = xp - max
			level = level + 1
			max = LevelMax(level, start, curMax)
			up = level
		end
		after[k] = { level = level, up = up, frac = level >= cap and 0 or xp / max }
	end
	return after
end

-- Quêtes « plus tard » qu'on pourra faire en route : on aura pris le niveau avant la fin
-- des étapes « maintenant ». Renvoie { [quête] = tâches qui doivent passer avant }.
local function Promotions(plan, stops, order)
	local after = Simulate(plan, stops, order)
	local boundary = 0
	for k, idx in ipairs(order) do
		if stops[idx].tier <= TIER_NOW then
			boundary = k
		end
	end
	local result, any = {}, false
	for _, q in ipairs(plan.quests or {}) do
		if q.tier == TIER_LATER and q.needLevel then
			for k = 1, boundary do
				if after[k].level >= q.needLevel then
					local gate = {}
					for j = 1, k do
						for _, t in ipairs(stops[order[j]].tasks) do
							gate[#gate + 1] = t
						end
					end
					result[q], any = gate, true
					break
				end
			end
		end
	end
	return any and result or nil
end

-- Rendus enchaînés au même endroit : une « tournée » (affichée comme telle).
local MarkTours
function Planner.MarkTours(order)
	return MarkTours(order)
end
function MarkTours(order)
	local k = 1
	while k <= #order do
		local j = k
		if order[k].kind == "turnin" then
			while j < #order do
				local a, b = order[j], order[j + 1]
				local d = b.kind == "turnin" and Dist(a, b)
				if d and d <= TOUR_YARDS then
					j = j + 1
				else
					break
				end
			end
		end
		if j > k then
			local count = 0
			for m = k, j do
				count = count + #order[m].quests
			end
			for m = k, j do
				order[m].tour = { first = k, last = j, index = m - k + 1, size = j - k + 1, quests = count }
			end
		end
		k = j + 1
	end
end

-- Retire les étapes « passées » ; un rendu dont un objectif n'est plus sur le trajet est retiré aussi.
local function DropSkipped(stops, skipped)
	local kept, missingWork = {}, {}
	for _, s in ipairs(stops) do
		s.key = StopKey(s)
		if skipped[s.key] then
			for _, t in ipairs(s.tasks) do
				if s.kind ~= "turnin" then
					missingWork[t.q.id] = true
				end
			end
		else
			kept[#kept + 1] = s
		end
	end
	local result = {}
	for _, s in ipairs(kept) do
		if s.kind == "turnin" then
			local tasks = s.tasks
			s.tasks, s.quests, s.questSet, s.work, s.tier = {}, {}, {}, 0, TIER_LATER
			for _, t in ipairs(tasks) do
				if not (t.after and missingWork[t.q.id]) then
					AddTask(s, t, TURNIN_TIME)
				end
			end
			if #s.tasks > 0 then
				s.key = StopKey(s)
				result[#result + 1] = s
			end
		else
			result[#result + 1] = s
		end
	end
	return result
end

local function Totals(plan, stops, C, order)
	local work, xp = 0, 0
	for _, s in ipairs(stops) do
		work = work + s.work
		if s.kind == "turnin" then
			for _, q in ipairs(s.quests) do
				xp = xp + (q.xp or 0)
			end
		end
	end
	plan.travel, plan.workTime, plan.xp = Solver.Cost(C, order), work, xp
end

-------------------------------------------------------------------------------
-- 5. Propositions : quêtes à prendre sur le trajet, suites de quêtes, réparer / vendre
-------------------------------------------------------------------------------
local GUESS = { monster = CANDIDATE_COUNT_GUESS, item = CANDIDATE_COUNT_GUESS, killcredit = 4, object = 1, event = 1 }

-- Le trajet actuel sous forme de liste (joueur en tête) avec le coût de chaque tronçon.
local function Line(plan, stops, order, C)
	local nodes, legs = { plan.player }, { 0 }
	local prev = 0
	for k, idx in ipairs(order) do
		nodes[k + 1] = stops[idx]
		legs[k + 1] = C[prev][idx]
		prev = idx
	end
	return nodes, legs
end

-- Coût d'insertion de `x` dans la ligne entre nodes[p-1] et nodes[p] (p de first à last).
-- Coûts des deux nouveaux tronçons quand on glisse `x` entre `a` et `b` (tronçon actuel : `leg`).
-- À pied en ligne droite, ou par le trajet déjà connu (vol, bateau…) puis à pied depuis l'autre bout :
-- un point juste à côté de l'arrivée d'un vol ne coûte donc pas tout le trajet à pied.
local function Legs(a, x, b, leg, speed)
	local ax, xb = Geo.Walk(a, x, speed), b and Geo.Walk(x, b, speed)
	if b and leg then
		local bx, xa = Geo.Walk(b, x, speed), Geo.Walk(x, a, speed)
		if bx and (not ax or leg + bx < ax) then
			ax = leg + bx
		end
		if xa and (not xb or xa + leg < xb) then
			xb = xa + leg
		end
	end
	return ax, xb
end

local function BestInsert(nodes, legs, x, first, last, speed)
	local best, bestP
	for p = math.max(2, first), math.min(#nodes + 1, last or math.huge) do
		local b = p <= #nodes and nodes[p] or nil
		local ax, xb = Legs(nodes[p - 1], x, b, b and legs[p], speed)
		if ax then
			local delta = ax
			if b then
				delta = xb and (delta + xb - legs[p]) or nil
			end
			if delta and (not best or delta < best) then
				best, bestP = delta, p
			end
		end
	end
	return best, bestP
end

local function Insert(nodes, legs, x, p, speed)
	local b = p <= #nodes and nodes[p] or nil
	local ax, xb = Legs(nodes[p - 1], x, b, b and legs[p], speed)
	table.insert(nodes, p, x)
	table.insert(legs, p, ax or 0)
	if b then
		legs[p + 1] = xb or legs[p + 1]
	end
end

local function Copy(list)
	local r = {}
	for i, v in ipairs(list) do
		r[i] = v
	end
	return r
end

-- Évalue une quête de la base : détour (en l'insérant au mieux dans le trajet), travail, XP.
-- `first` = position minimale de la prise (une suite se prend après le rendu de la quête d'avant).
-- Garde les points de la région (si `region` est donné et qu'il y en a), sinon tous.
local function InRegion(points, region)
	if not region then
		return points
	end
	local kept = {}
	for _, p in ipairs(points) do
		if Geo.Zone(p.map) == region then
			kept[#kept + 1] = p
		end
	end
	return kept
end

local function Evaluate(id, quest, level, base, first, speed, chainOf, after, region)
	local starters = SafeOnly(InRegion(Data.StarterPoints(quest), region), level)
	local finishers = SafeOnly(Data.FinisherPoints(quest), level)
	if #starters == 0 or #finishers == 0 then
		return nil
	end
	local local_ = InRegion(finishers, region)
	if #local_ > 0 then
		finishers = local_ -- rendre dans la région si possible
	end
	local nodes, legs = Copy(base.nodes), Copy(base.legs)
	local q = {
		id = id, title = quest.name or ("#" .. id), level = quest.level or level, objectives = {},
		candidate = true, tier = TIER_NOW, xp = Data.QuestXP(id) or 0, status = "proposée sur le trajet",
		chainOf = chainOf, after = after,
	}
	local extra, work, killXP = 0, PICKUP_TIME + TURNIN_TIME, 0
	-- 1. la prise
	local pick, pickD, pickP
	for _, sp in ipairs(starters) do
		local d, p = BestInsert(nodes, legs, sp, first, nil, speed)
		if d and (not pickD or d < pickD) then
			pick, pickD, pickP = sp, d, p
		end
	end
	if not pick then
		return nil
	end
	Insert(nodes, legs, pick, pickP, speed)
	extra = extra + pickD
	local pos = pickP + 1
	-- 2. les objectifs (quantités lues dans le texte de la quête quand c'est possible)
	local tasks = {}
	local counts = Data.ObjectiveCounts(quest)
	for i = 1, #(quest.ObjectiveData or {}) do
		local kind, label = Data.ObjectiveLabel(quest, i)
		local points, meta = Data.ObjectivePoints(quest, i)
		points = SafeOnly(points, level)
		if #points == 0 or (meta.level and meta.level >= level + 3) then
			return nil -- position inconnue, donjon ou monstres trop forts : on ne propose pas
		end
		if meta.eliteLevel and meta.eliteLevel >= level - 2 and not CONTEXT.grouped then
			return nil -- élites : pas de proposition en solo
		end
		local clusters = Data.Clusters(points)
		if region then
			clusters = InRegion(clusters, region)
			if #clusters == 0 then
				return nil -- objectif dans une autre région : ce sera pour quand tu y seras
			end
		end
		local zone, zoneD, zoneP
		for k = 1, math.min(4, #clusters) do
			local c = clusters[k]
			if k == 1 or c.count >= math.max(2, clusters[1].count * 0.3) then
				local d, p = BestInsert(nodes, legs, c, pos, nil, speed)
				if d and (not zoneD or d < zoneD) then
					zone, zoneD, zoneP = c, d, p
				end
			end
		end
		if not zone then
			return nil
		end
		Insert(nodes, legs, zone, zoneP, speed)
		extra = extra + zoneD
		pos = zoneP + 1
		local need = counts[i] or GUESS[kind or ""] or 1
		local objective = { type = kind, text = label, numRequired = need, numFulfilled = 0,
			target = Data.ObjectiveTarget(quest, i, kind) }
		work = work + Work(objective)
		if kind == "monster" and meta.level then
			killXP = killXP + need * KillXP(level, meta.level) * KILL_XP_SHARE
		end
		q.objectives[i] = objective
		tasks[#tasks + 1] = {
			kind = "obj", q = q, index = i, objective = objective, clusters = clusters,
			names = meta.names, mobLevel = meta.level, fixedAt = zone,
		}
	end
	-- 3. le rendu
	local fin, finD
	for _, fp in ipairs(finishers) do
		local d = BestInsert(nodes, legs, fp, pos, nil, speed)
		if d and (not finD or d < finD) then
			fin, finD = fp, d
		end
	end
	if not fin then
		return nil
	end
	extra = extra + finD
	q.extraTime = extra + work
	return {
		q = q, tasks = tasks, start = pick,
		turnin = { q = q, point = fin, after = true },
		time = extra + work, xp = q.xp + killXP,
	}
end

-- Quête de donjon à prendre avant d'y aller : tous ses objectifs sont dans un donjon déjà au trajet.
local function EvaluateDungeon(id, quest, level, base, speed, dungeons)
	local data = quest.ObjectiveData or {}
	if #data == 0 then
		return nil
	end
	local starters = SafeOnly(Data.StarterPoints(quest), level)
	local finishers = SafeOnly(Data.FinisherPoints(quest), level)
	if #starters == 0 or #finishers == 0 then
		return nil
	end
	local q = {
		id = id, title = quest.name or ("#" .. id), level = quest.level or level, objectives = {},
		candidate = true, prep = true, xp = Data.QuestXP(id) or 0, status = "à prendre pour le donjon",
	}
	local tasks, counts, areaStop = {}, Data.ObjectiveCounts(quest), nil
	for i = 1, #data do
		local points, meta = Data.ObjectivePoints(quest, i)
		local areaId = #points == 0 and next(meta.dungeons)
		local s = areaId and dungeons[areaId]
		if not s or (areaStop and areaStop ~= s) then
			return nil -- un objectif hors du donjon (ou dans un autre) : pas une simple préparation
		end
		areaStop = s
		local kind, label = Data.ObjectiveLabel(quest, i)
		local objective = { type = kind, text = label, numRequired = counts[i] or GUESS[kind or ""] or 1, numFulfilled = 0 }
		q.objectives[i] = objective
		tasks[#tasks + 1] = { kind = "dungeon", q = q, areaId = areaId, index = i, objective = objective }
	end
	-- même priorité que les quêtes déjà dans l'étape du donjon (pour s'y joindre)
	local mate = areaStop.quests[1]
	q.tier, q.prepFor = mate and mate.tier or TIER_NOW, areaStop.dungeonName
	-- position du donjon dans la ligne : la prise avant, le rendu après
	local at
	for p, node in ipairs(base.nodes) do
		if node == areaStop then
			at = p
		end
	end
	if not at then
		return nil
	end
	local nodes, legs = Copy(base.nodes), Copy(base.legs)
	local pick, pickD, pickP
	for _, sp in ipairs(starters) do
		local d, p = BestInsert(nodes, legs, sp, 2, at, speed)
		if d and (not pickD or d < pickD) then
			pick, pickD, pickP = sp, d, p
		end
	end
	if not pick then
		return nil
	end
	Insert(nodes, legs, pick, pickP, speed)
	local fin, finD
	for _, fp in ipairs(finishers) do
		local d = BestInsert(nodes, legs, fp, at + 2, nil, speed)
		if d and (not finD or d < finD) then
			fin, finD = fp, d
		end
	end
	if not fin then
		return nil
	end
	local time = pickD + finD + PICKUP_TIME + TURNIN_TIME + 30 * #tasks
	q.extraTime = time
	return {
		q = q, dungeonTasks = tasks, tasks = {}, start = pick,
		turnin = { q = q, point = fin, after = true },
		time = time, xp = q.xp,
	}
end

local function Skipped(opts, id)
	local skipped = opts.skipped or {}
	if skipped["P:" .. id] then
		return true
	end
	local prefix = "A:" .. id .. "."
	for key in pairs(skipped) do
		if key:sub(1, #prefix) == prefix then
			return true
		end
		if key:sub(1, 2) == "P:" then
			-- étape « Prendre » regroupée (« P:12,34 ») passée
			for other in key:sub(3):gmatch("%d+") do
				if tonumber(other) == id then
					return true
				end
			end
		end
	end
	return false
end

local function Excluded(id)
	return Data.Flag("IsRepeatable", id) or Data.Flag("IsDailyQuest", id) or Data.Flag("IsDungeonQuest", id)
		or Data.Flag("IsRaidQuest", id) or Data.Flag("IsPvPQuest", id) or Data.Flag("IsGroupQuest", id)
end

-- Rythme actuel (XP par seconde) du trajet : sert de seuil pour accepter une quête proposée.
local function Rate(stops, order, C, level)
	local xp, work = 0, 0
	for _, idx in ipairs(order) do
		xp = xp + StopXP(stops[idx], level)
		work = work + stops[idx].work
	end
	local time = Solver.Cost(C, order) + work
	if xp < 1 or time < 60 then
		return 1
	end
	return xp / time
end

function Planner.SelectCandidates(opts, plan, stops, order, C, yield)
	local level = plan.level
	local nodes, legs = Line(plan, stops, order, C)
	local base = { nodes = nodes, legs = legs }
	local speed = Geo.Speed()
	local threshold = Rate(stops, order, C, level) * 0.8
	local kept = opts.prevCandidates or {}
	-- Quêtes visées dans la fenêtre Équipement (« Y aller ») et quêtes dont la récompense t'améliore.
	local wanted = opts.wantedQuests or {}
	local gearQuests = opts.gearQuests or {}
	local function Worth(c)
		local ratio = c.xp / math.max(c.time, 1)
		if wanted[c.q.id] then
			return true
		end
		return c.time <= CANDIDATE_MAX_TIME and (ratio >= threshold or (kept[c.q.id] and ratio >= threshold * 0.6)
			or (gearQuests[c.q.id] and ratio >= threshold * 0.5))
	end
	local function Score(c)
		return c.xp / math.max(c.time, 1) * (kept[c.q.id] and 1.5 or 1) * (gearQuests[c.q.id] and 1.5 or 1)
			* (wanted[c.q.id] and 100 or 1)
	end
	local inLog = {}
	for _, q in ipairs(plan.quests or {}) do
		inLog[q.id] = true
	end
	local function Usable(id)
		-- (Data.CanTake : jamais une quête d'une autre classe, d'une autre race, d'un métier qu'on n'a pas…)
		return not inLog[id] and not Skipped(opts, id) and not Data.Completed(id) and not Excluded(id)
			and Data.CanTake(id, nil, inLog)
	end
	local picked = {}
	-- a) Suites des quêtes du journal (elles se prennent en général au moment du rendu).
	local after = Simulate(plan, stops, order)
	local position = {}
	for k, idx in ipairs(order) do
		position[stops[idx]] = k
	end
	local chains = {}
	for _, q in ipairs(plan.quests or {}) do
		local task = plan.turninTask and plan.turninTask[q.id]
		local quest = task and Data.Quest(q.id)
		local nextId = quest and quest.nextQuestInChain
		if type(nextId) == "number" and nextId > 0 and Usable(nextId) then
			-- position (dans le trajet) de l'étape où l'on rend la quête d'avant
			local k
			for _, s in ipairs(stops) do
				for _, t in ipairs(s.tasks) do
					if t == task then
						k = position[s]
					end
				end
			end
			local nextQuest = k and Data.Quest(nextId)
			local lvlThen = k and after[k] and after[k].level or level
			if nextQuest and (nextQuest.requiredLevel or 0) <= lvlThen and (nextQuest.level or 0) <= lvlThen + 2 then
				local others = true
				for _, pre in ipairs(nextQuest.preQuestGroup or {}) do
					if pre ~= q.id and not Data.Completed(pre) then
						others = false
					end
				end
				if others then
					yield()
					-- nodes[k + 1] = l'étape du rendu : la prise se place juste après (position k + 2)
					local c = Evaluate(nextId, nextQuest, lvlThen, base, k + 2, speed, q, task)
					if c and Worth(c) then
						chains[#chains + 1] = c
					end
				end
			end
		end
	end
	table.sort(chains, function(a, b)
		return Score(a) > Score(b)
	end)
	local taken = {}
	for k = 1, math.min(3, #chains) do
		picked[#picked + 1] = chains[k]
		taken[chains[k].q.id] = true
	end
	-- b) Quêtes disponibles dont le donneur est près du trajet (dans la limite des places du journal).
	--    Mode région : TOUTES les quêtes de la région (le journal se vide au fil des rendus).
	local free = Data.MaxQuests() - (plan.logCount or #(plan.quests or {}))
	local region = opts.region
	local room = free
	if region then
		for _, s in ipairs(stops) do
			if s.kind == "turnin" and not s.away then -- rendus faits dans la région (ils libèrent des places à temps)
				for _, q in ipairs(s.quests) do
					if not q.external then
						room = room + 1
					end
				end
			end
		end
	end
	if room > 0 then
		local near = {}
		local count = 0
		for id in pairs(Data.AvailableQuests()) do
			count = count + 1
			if count % 20 == 0 then
				yield()
			end
			if not taken[id] and Usable(id) then
				local quest = Data.Quest(id)
				local lvl = quest and quest.level
				local want = wanted[id] and quest and (quest.requiredLevel or 0) <= level
				if want or (lvl and lvl > 0 and lvl <= level + 2 and lvl >= level - 5 and (quest.requiredLevel or 0) <= level) then
					local best
					local starters = SafeOnly(Data.StarterPoints(quest), level)
					for _, sp in ipairs(starters) do
						for _, node in ipairs(nodes) do
							local d = Dist(sp, node)
							if d and (not best or d < best) then
								best = d
							end
						end
					end
					local inRegion = false
					if region then
						for _, sp in ipairs(starters) do
							inRegion = inRegion or Geo.Zone(sp.map) == region
						end
					end
					if want or inRegion or (best and best <= CANDIDATE_NEAR) then
						near[#near + 1] = { id = id, quest = quest, d = best or math.huge, region = inRegion, wanted = want }
					end
				end
			end
		end
		table.sort(near, function(a, b)
			if (a.wanted and true or false) ~= (b.wanted and true or false) then
				return a.wanted and true or false
			end
			if (kept[a.id] and true or false) ~= (kept[b.id] and true or false) then
				return kept[a.id] and true or false
			end
			if a.d ~= b.d then
				return a.d < b.d
			end
			return a.id < b.id
		end)
		local found = {}
		for k = 1, math.min(region and (CANDIDATE_LOOK + REGION_MAX) or CANDIDATE_LOOK, #near) do
			yield()
			local c = Evaluate(near[k].id, near[k].quest, level, base, 2, speed, nil, nil, near[k].region and region or nil)
			-- Dans la région : on prend tout ce qui reste raisonnable (le but est de la finir).
			if c and (near[k].wanted or (near[k].region and c.time <= REGION_MAX_TIME) or Worth(c)) then
				c.q.inRegion = near[k].region or nil
				found[#found + 1] = c
			end
		end
		table.sort(found, function(a, b)
			return Score(a) > Score(b)
		end)
		local limit = region and math.min(room, REGION_MAX) or math.min(free, CANDIDATE_MAX)
		for k = 1, math.min(limit, #found) do
			picked[#picked + 1] = found[k]
			taken[found[k].q.id] = true
			free = free - 1
		end
	end
	-- c) Préparer les donjons du trajet : leurs quêtes encore à prendre (on y va de toute façon).
	local dungeons = {}
	for _, s in ipairs(stops) do
		if s.kind == "dungeon" and s.areaId then
			dungeons[s.areaId] = s
		end
	end
	if free > 0 and next(dungeons) then
		local found, count = {}, 0
		for id in pairs(Data.AvailableQuests()) do
			count = count + 1
			if count % 20 == 0 then
				yield()
			end
			if not taken[id] and not inLog[id] and not Skipped(opts, id) and not Data.Completed(id)
				and not Data.Flag("IsRepeatable", id) and not Data.Flag("IsRaidQuest", id) and not Data.Flag("IsPvPQuest", id) then
				local quest = Data.Quest(id)
				local lvl = quest and quest.level
				if lvl and lvl > 0 and lvl <= level + 4 and (quest.requiredLevel or 0) <= level and Data.CanTake(id, quest, inLog) then
					local c = EvaluateDungeon(id, quest, level, base, speed, dungeons)
					if c and c.time <= 600 and c.xp / math.max(c.time, 1) >= threshold * 0.5 then
						found[#found + 1] = c
					end
				end
			end
		end
		table.sort(found, function(a, b)
			return Score(a) > Score(b)
		end)
		for k = 1, math.min(free, #found) do
			picked[#picked + 1] = found[k]
		end
	end
	return picked
end

-- Faut-il réparer / vendre ? (nil sinon)
function Planner.ServiceNeed(opts)
	if opts.includeServices == false then
		return nil
	end
	-- (`forceSell` : objets à vendre choisis dans « Vider mes sacs »)
	if opts.serviceDoneAt and GetTime() - opts.serviceDoneAt < 900 and (opts.forceSell or 0) == 0 then
		return nil -- on sort de chez un marchand : on n'insiste pas
	end
	local g = Data.GearState()
	local repair = g.low <= 0.25 or g.avg <= 0.5
	local sell = (g.free ~= nil and g.free <= 3) or (opts.forceSell or 0) > 0
	if not (repair or sell) then
		return nil
	end
	local urgent = (repair and g.low <= 0.08) or (sell and g.free == 0)
	local skipped = opts.skipped or {}
	if skipped[urgent and "S:urgent" or "S:besoin"] then
		return nil
	end
	local why = {}
	if repair then
		why[#why + 1] = string.format("Équipement usé : %d %% en moyenne, %d %% pour l'objet le plus abîmé.",
			math.floor(g.avg * 100 + 0.5), math.floor(g.low * 100 + 0.5))
	end
	local chosen = (opts.forceSell or 0) > 0 and not (g.free ~= nil and g.free <= 3)
	if chosen then
		why[#why + 1] = opts.forceSell .. " objet(s) à vendre, choisis dans « Vider mes sacs » (vendus tout seuls chez le marchand)."
	elseif sell then
		why[#why + 1] = g.free == 0 and "Sacs pleins : tu ne ramasses plus rien."
			or ("Plus que " .. tostring(g.free) .. " place(s) dans les sacs.")
	end
	why[#why + 1] = "Pas maintenant ? Clic droit > Passer l'étape."
	return {
		kind = "repair", key = urgent and "urgent" or "besoin", folk = "Repair", sp = "vendor",
		urgent = urgent,
		label = repair and sell and "Réparer et vendre" or repair and "Réparer"
			or chosen and "Vendre ce qui ne sert plus"
			or (g.free == 0 and "Vendre (sacs pleins)" or "Vendre (sacs presque pleins)"),
		why = why,
	}
end

-- Maître de classe : de nouvelles techniques à chaque niveau pair (depuis la dernière visite).
function Planner.TrainerNeed(opts)
	if opts.includeTrainer == false or not opts.trainedAt then
		return nil
	end
	local level = UnitLevel("player") or 1
	local due = level - level % 2
	if due < 2 or due <= opts.trainedAt then
		return nil
	end
	local key = "maitre" .. due
	if (opts.skipped or {})["S:" .. key] then
		return nil
	end
	return {
		kind = "trainer", key = key, folk = "Class Trainer", sp = "trainer", urgent = false,
		label = "Apprendre les techniques du niveau " .. due,
		why = {
			"Depuis ta dernière visite au maître de classe (niveau " .. opts.trainedAt .. "), de nouvelles techniques t'attendent.",
			"Pas maintenant ? Clic droit > Passer l'étape.",
		},
	}
end

-- Signature de l'état « réparer / vendre » (Core recalcule seulement quand elle change).
function Planner.ServiceSignature(opts)
	local need = Planner.ServiceNeed(opts)
	return need and ((need.urgent and "U" or "N") .. need.label) or ""
end

-- Le personnage (réparateur, maître de classe) qui coûte le moins de détour, dans les ~30 premières
-- minutes du trajet (tout de suite si c'est urgent).
function Planner.SelectErrand(need, plan, stops, order, C, yield)
	if not need then
		return nil
	end
	local nodes, legs = Line(plan, stops, order, C)
	local speed = Geo.Speed()
	-- dernière position autorisée : avant la première étape qui tombe après le délai
	local last, eta, deadline = #nodes + 1, 0, {}
	for k = 2, #nodes do
		eta = eta + legs[k] + (nodes[k].work or 0)
		if eta > SERVICE_DEADLINE then
			last = math.min(last, k)
			deadline[nodes[k].key] = true
		end
	end
	if need.urgent then
		last = 2
	end
	local best, bestD
	for i, point in ipairs(Data.TownsfolkPoints(need.folk, yield)) do
		if i % 200 == 0 then
			yield()
		end
		-- (jamais un marchand ou un maître dans une zone trop haute pour toi)
		if point.inst == plan.player.inst and not Data.ZoneDanger(point.map, plan.level) then
			local d = BestInsert(nodes, legs, point, 2, last, speed)
			if d and (not bestD or d < bestD) then
				best, bestD = point, d
			end
		end
	end
	if not best then
		return nil
	end
	need.point = best
	need.deadline = deadline
	need.title = need.label .. " chez " .. (best.name or (need.kind == "trainer" and "ton maître de classe" or "un marchand"))
	return need
end

-- Objectif d'équipement (fenêtre Équipement, « Y aller ») : le lieu (vendeur, PNJ, coffre, entrée du
-- donjon) qui coûte le moins de détour sur le trajet.
function Planner.SelectGoal(goal, plan, stops, order, C, yield)
	local nodes, legs = Line(plan, stops, order, C)
	local speed = Geo.Speed()
	local best, bestD
	local points = Data.SafePoints(goal.points or {}, plan.level) -- (hors des zones trop hautes, s'il y a le choix)
	for i, point in ipairs(points) do
		if i % 50 == 0 then
			yield()
		end
		if point.wx and point.inst == plan.player.inst then
			local d = BestInsert(nodes, legs, point, 2, nil, speed)
			if d and (not bestD or d < bestD) then
				best, bestD = point, d
			end
		end
	end
	best = best or (goal.points and goal.points[1]) -- autre continent : Shortest Path s'occupe du voyage
	if not (best and best.map and best.x and best.y) then
		return nil
	end
	return {
		kind = "gear", key = goal.key, point = best, title = goal.title, label = goal.label, why = goal.why,
		work = goal.work, item = goal.item, urgent = false,
	}
end

local function ServiceStop(need)
	local s = NewStop("service", need.point, "s")
	s.service = need
	s.npc = need.point.npc
	s.npcName = need.point.name
	s.radius = need.radius or (need.kind == "gear" and 30 or 8)
	s.tier = need.tier or (need.urgent and (TIER_FOCUS - 1) or TIER_NOW)
	s.work = need.work or 60
	return s
end

local function CandidatePickup(c)
	local s = NewStop("pickup", c.start, "c" .. c.q.id)
	s.npc = c.start.npc
	s.npcName = c.start.name
	s.radius = 8
	s.tier = TIER_NOW
	s.work = PICKUP_TIME
	s.candidate = c.q
	s.candidates = { c.q }
	s.pickups[1] = { id = c.q.id, name = c.q.title, level = c.q.level }
	return s
end

-- Une seule étape « Prendre » par donneur (les suites gardent la leur : elles attendent un rendu).
local function CandidatePickups(cands)
	local stops, byGiver = {}, {}
	for _, c in ipairs(cands) do
		local giver = not c.q.chainOf and (c.start.npc and ("n" .. c.start.npc)
			or string.format("%d:%.3f:%.3f", c.start.map or 0, c.start.x or 0, c.start.y or 0))
		local s = giver and byGiver[giver]
		if s then
			s.candidates[#s.candidates + 1] = c.q
			s.pickups[#s.pickups + 1] = { id = c.q.id, name = c.q.title, level = c.q.level }
			s.work = s.work + PICKUP_TIME
		else
			s = CandidatePickup(c)
			if giver then
				byGiver[giver] = s
			end
			stops[#stops + 1] = s
		end
	end
	return stops
end

-- Étapes + ordre pour l'état actuel des quêtes (priorités, quêtes avancées).
local function Route(opts, plan, objTasks, turnins, dungeonTasks, yield, extra)
	local stops = Planner.Stops(opts, plan, objTasks, turnins, dungeonTasks)
	stops = DropSkipped(stops, opts.skipped or {})
	for _, s in ipairs(extra and extra.stops or {}) do
		stops[#stops + 1] = s
	end
	if opts.includePickups and not opts.groupMode and not opts.turninOnly then
		Planner.Pickups(opts, plan, stops, yield)
	end
	local deadline = extra and extra.deadline
	for _, s in ipairs(stops) do
		s.key = StopKey(s)
		Describe(s)
		s.focus = s.tier == TIER_FOCUS
		s.afterService = deadline and deadline[s.key] or nil
	end
	yield()
	local n = #stops
	if n == 0 then
		return stops, {}, nil, 0, 0, {}
	end
	local nodes = { [0] = plan.player }
	for i, s in ipairs(stops) do
		nodes[i] = s
	end
	local C, used = Geo.Matrix(nodes, n, ESTIMATE_BUDGET, yield)
	local before = Precedence(stops, opts.region)
	local first
	for i, s in ipairs(stops) do
		if opts.pinned and s.key == opts.pinned then
			first = i
		end
	end
	if first then
		-- L'étape forcée par le joueur passe devant les priorités (pas devant ses propres objectifs).
		local kept = {}
		for _, pair in ipairs(before) do
			if not (pair[3] and pair[2] == first) then
				kept[#kept + 1] = pair
			end
		end
		before = kept
	end
	-- Place dans le journal : prendre une quête +1, la rendre -1 (seulement tes propres quêtes).
	local capacity
	if opts.capacity then
		capacity = { start = opts.capacity.start, max = opts.capacity.max, delta = {} }
		for i, s in ipairs(stops) do
			local d = 0
			if s.kind == "pickup" then
				d = s.candidates and #s.candidates or 1
			elseif s.kind == "turnin" then
				for _, q in ipairs(s.quests) do
					if not q.external then
						d = d - 1
					end
				end
			end
			capacity.delta[i] = d
		end
	end
	local order, cost = Solver.Solve(n, C, before, { first = first, tick = yield, capacity = capacity })
	-- Stabilité : on garde l'étape en cours si l'écart est faible, pour éviter que la flèche saute.
	if not first and opts.previous then
		for i, s in ipairs(stops) do
			if s.key == opts.previous and order[1] ~= i then
				local keep, keepCost = Solver.Solve(n, C, before, { first = i, tick = yield, restarts = 10, capacity = capacity })
				if keep[1] == i and keepCost <= cost + math.max(60, cost * 0.08) then
					order, cost = keep, keepCost
				end
				break
			end
		end
	end
	return stops, order, C, cost, used or 0, before
end

-- Lance une partie facultative du calcul (quêtes avancées, propositions, arrêts, pierre de foyer).
-- Si elle plante, le trajet de base reste valable : l'erreur est notée (plan.warnings), le guidage continue.
-- (Pas de pcall : il ne laisse pas « yield » passer en Lua 5.1 ; on la fait tourner dans sa propre coroutine.)
local unpackList = unpack or table.unpack
local function Optional(plan, name, fn)
	local co = coroutine.create(fn)
	local result = { coroutine.resume(co) }
	while true do
		if not result[1] then
			plan.warnings = plan.warnings or {}
			plan.warnings[#plan.warnings + 1] = name .. " : " .. tostring(result[2])
			return false
		end
		if coroutine.status(co) == "dead" then
			return true, unpackList(result, 2)
		end
		if coroutine.running() then
			coroutine.yield() -- la partie facultative a épuisé le temps de l'image : on rend la main aussi
		end
		result = { coroutine.resume(co) }
	end
end

-- Construit le plan complet. yield() est appelé souvent (le calcul s'étale sur plusieurs images).
function Planner.Build(opts, yield)
	local plan = {
		side = { dungeons = {}, pvp = {}, failed = {}, unknown = {} },
		order = {},
	}
	plan.player = Geo.Player()
	plan.level = UnitLevel("player") or 1
	plan.focus = opts.focus
	plan.at = time and time() or nil
	CONTEXT = { rates = opts.rates or {}, targets = opts.targets or {}, slots = opts.slots or {},
		gearQuests = opts.gearQuests or {},
		grouped = opts.grouped and true or false }
	Geo.SetPace(opts.pace, opts.zonePace)
	if opts.regionMode ~= false and plan.player.map then
		opts.region = Geo.Zone(plan.player.map)
		plan.region, plan.regionName = opts.region, Geo.ZoneName(opts.region)
	end
	local objTasks, turnins, dungeonTasks = Planner.Tasks(opts, plan, yield)
	if not opts.groupMode then
		opts.capacity = { start = plan.logCount or 0, max = Data.MaxQuests() }
	end
	yield()
	local stops, order, C, cost, used = Route(opts, plan, objTasks, turnins, dungeonTasks, yield)
	if #stops == 0 then
		return plan
	end
	-- 2e passe : les quêtes « plus tard » dont on aura le niveau en route sont avancées.
	local promote
	local promoted = Optional(plan, "quêtes avancées", function()
		promote = Promotions(plan, stops, order)
		if not promote then
			return
		end
		for q, gate in pairs(promote) do
			q.tier, q.promoted, q.gateTasks = TIER_NOW, true, gate
		end
		local stops2, order2, C2, cost2, used2, before2 = Route(opts, plan, objTasks, turnins, dungeonTasks, yield)
		used = used + used2
		local valid = #stops2 > 0 and #order2 == #stops2 and Respects(order2, before2)
		plan.promotion = { before = math.floor(cost), after = math.floor(cost2), valid = valid }
		local same = true
		for q in pairs(promote) do
			same = same and (opts.prevPromoted or {})[q.id] and true or false
		end
		local tolerance = same and math.max(60, cost * 0.08) or 1
		if valid and cost2 <= cost + tolerance then
			stops, order, C, cost = stops2, order2, C2, cost2
			plan.promotedIds = {}
			for q in pairs(promote) do
				q.status = "sur le trajet (dès le niveau " .. q.needLevel .. ")"
				plan.promotedIds[q.id] = true
			end
			promote = nil -- gardées
		end
	end)
	if promote or not promoted then
		-- refusées (ou erreur) : les quêtes redeviennent « plus tard »
		for _, q in ipairs(plan.quests or {}) do
			if q.promoted and not (plan.promotedIds and plan.promotedIds[q.id]) then
				q.tier, q.promoted, q.gateTasks = TIER_LATER, nil, nil
			end
		end
	end
	-- 3e passe : quêtes proposées sur le trajet (et suites), arrêts réparer / vendre et maître de classe.
	-- (Pour un trajet de groupe, rien de personnel : chacun gère son équipement et son maître.)
	local personal = not opts.groupMode
	local cands, errands = {}, {}
	local base = { stops = stops, order = order, C = C, cost = cost }
	local keptCands = false
	-- Recalcule le trajet avec les quêtes proposées (si `withCands`, sauf celles que la soirée laisse de côté), les
	-- arrêts (réparer, maître, équipement) et des étapes en plus (`list` : région suivante, filons, auberge).
	-- Gardé seulement s'il respecte toutes les contraintes ; rend alors { stops, order, C, cost }.
	local function Reroute(withCands, list)
		local o, t, d = {}, {}, {}
		for _, x in ipairs(objTasks) do
			o[#o + 1] = x
		end
		for _, x in ipairs(turnins) do
			t[#t + 1] = x
		end
		for _, x in ipairs(dungeonTasks) do
			d[#d + 1] = x
		end
		local service = errands[1]
		local extra = { stops = {}, deadline = service and service.deadline }
		local previousSet = plan.candidateSet
		plan.candidateSet = {}
		if withCands then
			local kept = {}
			for _, c in ipairs(cands) do
				if not c.dropped then
					kept[#kept + 1] = c
					for _, x in ipairs(c.tasks) do
						o[#o + 1] = x
					end
					for _, x in ipairs(c.dungeonTasks or {}) do
						d[#d + 1] = x
					end
					t[#t + 1] = c.turnin
					plan.candidateSet[c.q.id] = true
				end
			end
			for _, s in ipairs(CandidatePickups(kept)) do
				extra.stops[#extra.stops + 1] = s
			end
		end
		for _, errand in ipairs(errands) do
			extra.stops[#extra.stops + 1] = ServiceStop(errand)
		end
		for _, need in ipairs(list or {}) do
			extra.stops[#extra.stops + 1] = ServiceStop(need)
		end
		local stops3, order3, C3, cost3, used3, before3 = Route(opts, plan, o, t, d, yield, extra)
		used = used + used3
		if #stops3 > 0 and #order3 == #stops3 and Respects(order3, before3) then
			stops, order, C, cost = stops3, order3, C3, cost3
			return { stops = stops3, order = order3, C = C3, cost = cost3 }
		end
		plan.candidateSet = previousSet
		return nil
	end
	local ok = Optional(plan, "propositions et arrêts", function()
		if personal and opts.includePickups and not opts.turninOnly then
			cands = Planner.SelectCandidates(opts, plan, stops, order, C, yield)
		end
		if personal then
			for _, need in ipairs({ Planner.ServiceNeed(opts) or false, Planner.TrainerNeed(opts) or false }) do
				local errand = need and Planner.SelectErrand(need, plan, stops, order, C, yield)
				if errand then
					errands[#errands + 1] = errand
				end
			end
			-- Objectifs d'équipement choisis par le joueur (après réparer / maître : ils gardent leur délai).
			for _, goal in ipairs(opts.gearGoals or {}) do
				if not (opts.skipped or {})["S:" .. goal.key] then
					local errand = Planner.SelectGoal(goal, plan, stops, order, C, yield)
					if errand then
						errands[#errands + 1] = errand
					end
				end
			end
		end
		local service = errands[1]
		local function Third(withCands)
			if Reroute(withCands, {}) then
				keptCands = withCands
				return true
			end
			return false
		end
		if #cands > 0 or service then
			if not Third(true) and #cands > 0 and service then
				Third(false)
			end
		end
	end)
	if not ok then
		-- erreur : on revient au trajet d'avant les propositions
		stops, order, C, cost = base.stops, base.order, base.C, base.cost
		plan.candidateSet, cands, errands, keptCands = nil, {}, {}, false
	end
	-- 4e passe : la région suivante (journal presque fini) et les filons de minage à deux pas du trajet.
	local needs = {}
	if personal and not opts.turninOnly then
		local before4 = { stops = stops, order = order, C = C, cost = cost, set = plan.candidateSet }
		local ok4 = Optional(plan, "région suivante et filons", function()
			local Montee = ns.Montee
			local list = {}
			local region = Montee and opts.includePickups and opts.regionMode ~= false
				and Montee.NextRegionNeed(opts, plan, stops, order, C, yield)
			if type(region) == "table" and not (opts.skipped or {})["S:" .. region.key] then
				region.tier = TIER_NEXT
				list[#list + 1] = region
			end
			local mines = Montee and opts.includeMining ~= false and Montee.MineNeeds(opts, plan, stops, order, C, yield)
			for _, m in ipairs(type(mines) == "table" and mines or {}) do
				if not (opts.skipped or {})["S:" .. m.key] then
					list[#list + 1] = m
				end
			end
			if #list > 0 and Reroute(keptCands, list) then
				needs = list
			end
		end)
		if not ok4 then
			stops, order, C, cost, plan.candidateSet = before4.stops, before4.order, before4.C, before4.cost, before4.set
		end
	end
	-- 5e passe : la soirée (« j'ai 1 h 30 ») : ce qui rapporte le plus d'XP dans le temps, puis une auberge ;
	-- le reste du journal passe après (rien n'est écarté).
	if personal and opts.soiree and not opts.turninOnly then
		local before5 = { stops = stops, order = order, C = C, cost = cost, set = plan.candidateSet }
		local saved = {}
		for _, q in ipairs(plan.quests or {}) do
			saved[q] = q.tier
		end
		local ok5, applied = Optional(plan, "soirée", function()
			return Planner.Soiree(opts, plan, { stops = stops, order = order, C = C }, cands, keptCands, needs, Reroute, yield)
		end)
		if not (ok5 and applied) then
			for q, tier in pairs(saved) do
				q.tier = tier
			end
			for _, c in ipairs(cands) do
				c.dropped = nil
			end
			stops, order, C, cost, plan.candidateSet = before5.stops, before5.order, before5.C, before5.cost, before5.set
			plan.soiree = nil
		end
	end
	plan.candidates = {}
	for _, c in ipairs(cands) do
		if plan.candidateSet and plan.candidateSet[c.q.id] then
			plan.candidates[#plan.candidates + 1] = c.q
		end
	end
	plan.estimates = used
	Totals(plan, stops, C, order)
	local after = Simulate(plan, stops, order)
	local prev, eta = 0, 0
	plan.laterCount, plan.promotedCount = 0, 0
	for k, idx in ipairs(order) do
		local s = stops[idx]
		s.number = k
		s.leg = C[prev][idx]
		s.legWalk = not (C.sp and C.sp[prev] and C.sp[prev][idx])
		s.legModel = s.leg -- l'estimation du modèle (sert à mesurer ton rythme de déplacement)
		local firstLeg = opts.firstLeg
		if k == 1 and firstLeg and firstLeg.key == s.key and firstLeg.seconds and firstLeg.seconds > 0 then
			-- Étape en cours : Shortest Path connaît le vrai temps restant (relief compris) ; affichage
			-- seulement (pour l'ordre, il avantagerait les autres étapes, estimées en ligne droite).
			plan.travel = (plan.travel or 0) + firstLeg.seconds - s.leg
			s.leg = firstLeg.seconds
			s.legExact = true
		end
		-- Les 3 prochaines étapes : comment Shortest Path y va (vol, bateau…) et son estimation à lui
		-- (affichage seulement, comme ci-dessus).
		if k <= 3 and not opts.groupMode then
			local from = prev == 0 and plan.player or stops[prev]
			if not s.legWalk then
				s.route = Geo.RouteDetail(from, s)
			elseif k > 1 and s.leg >= 60 then
				s.legSP = Geo.Estimate(from, s)
			end
		end
		if s.kind == "service" and s.service.kind == "inn" and s.service.hearth and s.leg > HEARTH_CAST then
			-- fin de soirée par la pierre de foyer : l'incantation au lieu du trajet
			plan.travel = (plan.travel or 0) + HEARTH_CAST - s.leg
			s.leg, s.hearth = HEARTH_CAST, { gain = 0, name = s.service.innName }
		end
		eta = eta + s.leg + s.work
		s.eta = eta
		s.levelUp = after[k].up
		if s.levelUp then
			s.details[#s.details + 1] = "Niveau " .. s.levelUp .. " atteint ici (estimation)"
		end
		if s.focus then
			plan.focusRouted = true
		end
		if s.away then
			plan.awayCount = (plan.awayCount or 0) + 1
			plan.awayZones = plan.awayZones or {}
			local zone = Geo.ZoneName(Geo.Zone(s.map))
			if zone ~= "" and not plan.awayZones[zone] then
				plan.awayZones[zone] = true
				plan.awayZones[#plan.awayZones + 1] = zone
			end
		end
		if s.tier == TIER_LATER then
			plan.laterCount = plan.laterCount + 1
		elseif s.promoted then
			plan.promotedCount = plan.promotedCount + 1
		end
		if s.kind == "service" and s.service.kind ~= "mine" and s.service.kind ~= "inn" then
			plan.errands = plan.errands or {}
			plan.errands[#plan.errands + 1] = s.service
		end
		plan.order[k] = s
		prev = idx
	end
	local last = after[#order]
	plan.levelEnd = last and (last.level + last.frac) or plan.level
	-- Soirée : l'auberge (ou la dernière étape de la soirée), le niveau à ce moment-là, ce qui vient après.
	local soiree = plan.soiree
	if soiree then
		local endK = 0
		for k, s in ipairs(plan.order) do
			if s.tier < TIER_INN or (s.kind == "service" and s.service.kind == "inn") then
				endK = k
			end
		end
		for k, s in ipairs(plan.order) do
			if k > endK then
				s.afterSoiree = true
			end
			if s.kind == "service" and s.service.kind == "inn" then
				soiree.innStep = k
			end
		end
		local atEnd = after[endK]
		soiree.endEta = endK > 0 and plan.order[endK].eta or 0
		soiree.levelEnd = atEnd and (atEnd.level + atEnd.frac) or plan.level
		soiree.afterCount = #plan.order - endK
	end
	if not opts.groupMode and opts.useHearth ~= false and not soiree then
		-- (pendant une soirée, la pierre de foyer est gardée pour la fin : elle t'emmène à l'auberge)
		Optional(plan, "pierre de foyer", function()
			Planner.Hearth(plan, yield)
		end)
	end
	MarkTours(plan.order)
	return plan
end

-- Meilleur tronçon où prendre la pierre de foyer (une seule fois : elle se recharge longtemps) depuis
-- le lieu `home`. Le 1er tronçon est laissé à Shortest Path, qui la compte déjà depuis ta position.
local function HearthLeg(order, home, ready, speed)
	local best, bestK, bestCost
	for k = 2, #order do
		local s = order[k]
		local depart = (s.eta or 0) - (s.work or 0) - (s.leg or 0)
		if depart >= (ready or 0) then
			local walk = Geo.Walk(home, s, speed)
			if walk then
				local cost = HEARTH_CAST + walk
				local gain = (s.leg or 0) - cost
				if gain > HEARTH_MIN_GAIN and (not best or gain > best) then
					best, bestK, bestCost = gain, k, cost
				end
			end
		end
	end
	return best, bestK, bestCost
end

-- Pierre de foyer : l'étape où la prendre, et une auberge où la lier si une autre irait mieux.
function Planner.Hearth(plan, yield)
	local hearth = Data.Hearth()
	if not hearth then
		return
	end
	local speed = Geo.Speed()
	local order = plan.order
	local gain, k, cost = 0, nil, nil
	if hearth.point then
		gain, k, cost = HearthLeg(order, hearth.point, hearth.ready, speed)
		gain = gain or 0
	end
	if k then
		local s = order[k]
		local delta = cost - s.leg
		s.hearth = { gain = gain, name = hearth.name }
		s.details[#s.details + 1] = "Prends ta pierre de foyer pour y aller (" .. (hearth.name or "ton auberge")
			.. ") : ~" .. math.floor(gain / 60 + 0.5) .. " min gagnées."
		s.leg = cost
		for j = k, #order do
			order[j].eta = (order[j].eta or 0) + delta
		end
		plan.travel = (plan.travel or 0) + delta
		plan.hearth = { step = k, gain = gain, name = hearth.name }
	end
	-- Une autre auberge ferait-elle gagner plus sur ce trajet ? (seulement si on sait où tu es lié)
	if not hearth.point then
		return
	end
	local best, bestGain = nil, gain + BIND_MIN_GAIN
	for i, inn in ipairs(Data.TownsfolkPoints("Innkeeper", yield)) do
		if i % 50 == 0 then
			yield()
		end
		if inn.inst == plan.player.inst and not Data.ZoneDanger(inn.map, plan.level)
			and not (hearth.point and Geo.Yards(inn, hearth.point) and Geo.Yards(inn, hearth.point) < 150) then
			local g = HearthLeg(order, inn, hearth.ready, speed)
			if g and g > bestGain then
				best, bestGain = inn, g
			end
		end
	end
	if best then
		plan.bindAdvice = { name = best.name, zone = Geo.ZoneName(best.map), gain = bestGain - gain }
	end
end

-------------------------------------------------------------------------------
-- 7. Soirée planifiée (« j'ai 1 h 30 ») : les quêtes qui rapportent le plus d'XP dans ce temps, puis une auberge
--    (repos 4 fois plus rapide qu'en pleine nature). Le reste du journal passe après l'auberge : rien n'est écarté.
-------------------------------------------------------------------------------
local SOIREE_RESERVE = 120 -- temps gardé au départ pour rejoindre l'auberge (s)
local SOIREE_SLACK = 1.1 -- dépassement toléré avant de retirer une quête de la soirée
local SOIREE_REGION = 600 -- la région suivante n'entre dans la soirée que s'il reste ~10 min
local LOGOUT_WORK = 20 -- se déconnecter à l'auberge (s)
local INN_LOOK = 4 -- aubergistes les plus proches comparés avec le vrai trajet (Shortest Path)

-- Ce que rapporte chaque quête du trajet et ce qu'elle coûte : le temps gagné à la retirer (ses étapes à elle,
-- tronçons compris) plus sa part du travail des étapes partagées.
local function ZoneOf(s)
	return s.map and (Geo.Zone(s.map) or s.map) or 0
end

local function QuestValues(plan, route)
	local stops, order, C = route.stops, route.order, route.C
	local info, list = {}, {}
	local function Get(q)
		local e = info[q]
		if not e then
			e = { q = q, xp = q.external and 0 or (q.xp or 0), time = 0, first = math.huge, zones = {} }
			info[q] = e
			list[#list + 1] = e
		end
		return e
	end
	local prev = 0
	for k, idx in ipairs(order) do
		local s = stops[idx]
		local zone = ZoneOf(s)
		for _, q in ipairs(s.quests) do
			Get(q).zones[zone] = true
		end
		for _, q in ipairs(s.candidates or {}) do
			Get(q).zones[zone] = true
		end
		local nxt = order[k + 1]
		local saving = (C[prev][idx] or 0) + s.work
		if nxt then
			saving = saving + (C[idx][nxt] or 0) - (C[prev][nxt] or 0)
		end
		saving = math.max(s.work, saving)
		local own, seen = {}, {}
		for _, list2 in ipairs({ s.quests, s.candidates or {} }) do
			for _, q in ipairs(list2) do
				if not seen[q] then
					seen[q] = true
					own[#own + 1] = q
				end
			end
		end
		for _, q in ipairs(own) do
			local e = Get(q)
			e.first = math.min(e.first, k)
			if #own == 1 then
				e.time = e.time + saving
			else
				local work = s.kind == "pickup" and PICKUP_TIME or 0
				for _, t in ipairs(s.tasks) do
					if t.q == q then
						work = work + (s.kind == "turnin" and TURNIN_TIME or Work(t.objective))
					end
				end
				e.time = e.time + work + (saving - s.work) / #own
			end
		end
		for _, t in ipairs(s.tasks) do
			local o = t.objective
			if o and o.type == "monster" and t.mobLevel and not t.q.external then
				local left = math.max(0, (o.numRequired or 0) - (o.numFulfilled or 0))
				local e = Get(t.q)
				e.xp = e.xp + left * KillXP(plan.level, t.mobLevel) * KILL_XP_SHARE
			end
		end
		prev = idx
	end
	return list
end

-- Le voyage pour aller dans une zone (et en revenir) : ce que le trajet gagne à n'y faire AUCUNE étape, moins le temps
-- déjà compté quête par quête. Payé une fois, par le groupe de quêtes de la zone (sinon chaque quête d'une zone
-- lointaine paraît bon marché, et toutes ensemble coûtent le voyage).
local function ZoneEntries(route, values)
	local stops, order, C = route.stops, route.order, route.C
	local function Cost(skip)
		local prev, cost = 0, 0
		for _, idx in ipairs(order) do
			local s = stops[idx]
			if not (skip and ZoneOf(s) == skip) then
				cost = cost + (C[prev][idx] or 0) + s.work
				prev = idx
			end
		end
		return cost
	end
	local full, entry = Cost(nil), {}
	for _, idx in ipairs(order) do
		local z = ZoneOf(stops[idx])
		if not entry[z] then
			local inside = 0
			for _, e in ipairs(values) do
				local has, only = false, true
				for zz in pairs(e.zones) do
					if zz == z then
						has = true
					else
						only = false
					end
				end
				if has and only then
					inside = inside + e.time
				end
			end
			entry[z] = math.max(0, full - Cost(z) - inside)
		end
	end
	return entry
end

-- Les quêtes de la soirée : la meilleure XP par seconde, une quête seule dans une zone où l'on va déjà, ou un groupe
-- de quêtes d'une nouvelle zone avec son voyage. Rend { [quête] = true }, temps prévu.
local function SelectSoiree(values, entry, entered0, budget)
	local chosen, entered, total = {}, {}, 0
	for z in pairs(entered0) do
		entered[z] = true
	end
	local function Fits(e)
		for z in pairs(e.zones) do
			if not entered[z] then
				return false
			end
		end
		return true
	end
	local function Take(e)
		chosen[e.q] = true
		total = total + e.time
		for z in pairs(e.zones) do
			entered[z] = true
		end
	end
	local function Eligible(e)
		return not chosen[e.q] and (e.q.candidate or e.q.tier == TIER_NOW or e.q.tier == TIER_AFTER)
	end
	for _, e in ipairs(values) do
		if e.q.tier == TIER_FOCUS then
			for z in pairs(e.zones) do
				if not entered[z] then
					total = total + (entry[z] or 0)
				end
			end
			Take(e) -- la quête suivie est toujours de la soirée
		end
	end
	while true do
		local room = budget - total
		local bestRatio, bestList, bestEntry
		for _, e in ipairs(values) do
			if Eligible(e) and Fits(e) and e.time <= room then
				local r = e.value / math.max(30, e.time)
				if not bestRatio or r > bestRatio then
					bestRatio, bestList, bestEntry = r, { e }, 0
				end
			end
		end
		local seen = {}
		for _, e in ipairs(values) do
			if Eligible(e) and not Fits(e) then
				local missing, count = nil, 0
				for z in pairs(e.zones) do
					if not entered[z] then
						missing, count = z, count + 1
					end
				end
				if count == 1 and not seen[missing] then
					seen[missing] = true
					local members = {}
					for _, f in ipairs(values) do
						if Eligible(f) and f.zones[missing] then
							local ok = true
							for zz in pairs(f.zones) do
								if zz ~= missing and not entered[zz] then
									ok = false
								end
							end
							if ok then
								members[#members + 1] = f
							end
						end
					end
					table.sort(members, function(a, b)
						return a.value / math.max(30, a.time) > b.value / math.max(30, b.time)
					end)
					local cost, value, list = entry[missing] or 0, 0, {}
					for _, f in ipairs(members) do
						if cost + f.time <= room then
							cost, value = cost + f.time, value + f.value
							list[#list + 1] = f
							local r = value / math.max(30, cost)
							if not bestRatio or r > bestRatio then
								bestRatio, bestEntry = r, entry[missing] or 0
								bestList = {}
								for i, g in ipairs(list) do
									bestList[i] = g
								end
							end
						end
					end
				end
			end
		end
		if not bestList then
			break
		end
		total = total + bestEntry
		for _, f in ipairs(bestList) do
			Take(f)
		end
	end
	return chosen, total
end

-- Temps jusqu'à la dernière étape de la soirée (tout ce qui passe avant l'auberge) et cette étape (ou le joueur).
local function SessionEnd(plan, route)
	local stops, order, C = route.stops, route.order, route.C
	local lastK = 0
	for k, idx in ipairs(order) do
		if stops[idx].tier < TIER_INN then
			lastK = k
		end
	end
	local prev, eta = 0, 0
	for k = 1, lastK do
		local idx = order[k]
		eta = eta + (C[prev][idx] or 0) + stops[idx].work
		prev = idx
	end
	return prev > 0 and stops[prev] or plan.player, eta
end

-- Temps jusqu'à l'auberge dans le trajet `route` (nil s'il n'y en a pas).
local function InnEta(route)
	local stops, order, C = route.stops, route.order, route.C
	local prev, eta = 0, 0
	for _, idx in ipairs(order) do
		local s = stops[idx]
		local leg = C[prev][idx] or 0
		if s.kind == "service" and s.service.kind == "inn" then
			if s.service.hearth then
				leg = math.min(leg, HEARTH_CAST)
			end
			return eta + leg + s.work
		end
		eta = eta + leg + s.work
		prev = idx
	end
	return nil
end

-- L'auberge où finir : l'aubergiste le plus rapide à rejoindre depuis `from` (hors zones trop hautes), ou la pierre
-- de foyer si elle est prête à ce moment-là et fait gagner du temps.
local function PickInn(opts, plan, from, sessionEta, yield)
	local speed = Geo.Speed()
	local near = {}
	for i, inn in ipairs(Data.TownsfolkPoints("Innkeeper", yield)) do
		if i % 50 == 0 then
			yield()
		end
		if inn.inst == from.inst and not Data.ZoneDanger(inn.map, plan.level) then
			local walk = Geo.Walk(from, inn, speed)
			if walk then
				near[#near + 1] = { point = inn, cost = walk }
			end
		end
	end
	table.sort(near, function(a, b)
		return a.cost < b.cost
	end)
	local best
	for i = 1, math.min(INN_LOOK, #near) do
		local e = near[i]
		local cost = Geo.Estimate(from, e.point) or e.cost
		if not best or cost < best.cost then
			best = { point = e.point, cost = cost, name = e.point.name, zone = Geo.ZoneName(e.point.map) }
		end
	end
	local hearth = opts.useHearth ~= false and Data.Hearth()
	if hearth and hearth.point and (hearth.ready or 0) <= sessionEta + 60
		and not Data.ZoneDanger(hearth.point.map, plan.level) and (not best or HEARTH_CAST + 30 < best.cost) then
		return { point = hearth.point, cost = HEARTH_CAST, hearth = true, name = hearth.name,
			zone = Geo.ZoneName(hearth.point.map) }
	end
	return best
end

local function InnNeed(pick)
	local name = pick.name or (pick.hearth and "ton auberge" or "l'aubergiste")
	local where = pick.zone and pick.zone ~= "" and (" (" .. pick.zone .. ")") or ""
	return {
		kind = "inn", key = "auberge", point = pick.point, tier = TIER_INN, work = LOGOUT_WORK, radius = 15,
		hearth = pick.hearth, innName = name,
		title = pick.hearth and ("Fin de soirée : pierre de foyer vers " .. name) or ("Fin de soirée : auberge, " .. name),
		label = "Fin de soirée",
		why = {
			pick.hearth and ("Ta pierre de foyer sera prête : elle te ramène à " .. name .. where .. ". Déconnecte-toi à l'auberge.")
				or ("Déconnecte-toi à l'auberge, chez " .. name .. where .. " : ton repos y monte 4 fois plus vite qu'en pleine nature."),
			"Le reste de ton journal attend la prochaine soirée (étapes « après la soirée ») : rien n'est écarté.",
		},
	}
end

-- `route` : le trajet complet actuel. `Reroute(withCands, needs)` recalcule l'ordre (Build) avec ces étapes en plus.
-- Rend true si la soirée est appliquée (sinon Build remet le trajet d'avant).
function Planner.Soiree(opts, plan, route, cands, keptCands, needs, Reroute, yield)
	local budget = math.max(0, tonumber(opts.soiree.left) or 0)
	local prevIds = opts.prevSoiree or {}
	local values = QuestValues(plan, route)
	for _, e in ipairs(values) do
		e.value = e.xp * (prevIds[e.q.id] and 1.25 or 1) -- (stabilité d'un calcul à l'autre)
	end
	table.sort(values, function(a, b)
		return a.first < b.first
	end)
	local entry = ZoneEntries(route, values)
	-- Zones où l'on va de toute façon : la tienne, et celles des arrêts imposés (réparer, maître, équipement…).
	local entered = { [ZoneOf(plan.player)] = true }
	for _, idx in ipairs(route.order) do
		local s = route.stops[idx]
		if s.kind == "service" and s.service.kind ~= "mine" and s.service.kind ~= "region" and s.tier < TIER_INN then
			entered[ZoneOf(s)] = true
		end
	end
	local chosen, total
	local function Apply()
		for _, e in ipairs(values) do
			local q = e.q
			if not q.candidate and (q.tier == TIER_NOW or q.tier == TIER_AFTER) then
				q.tier = chosen[q] and TIER_NOW or TIER_AFTER
				if not chosen[q] then
					q.status = "après la soirée"
				elseif q.status == "après la soirée" then
					q.status = "sur le trajet"
				end
			end
		end
		for _, c in ipairs(cands) do
			c.dropped = not chosen[c.q] or nil -- quête proposée qui n'entre pas dans la soirée : plus proposée
		end
	end
	local base = {}
	for _, need in ipairs(needs) do
		if need.kind == "region" then
			base[#base + 1] = need
		end
		-- (les filons sont recherchés de nouveau, près des étapes de la soirée)
	end
	local skipInn = (opts.skipped or {})["S:auberge"]
	local result, pick, kept
	local room = budget - SOIREE_RESERVE
	for _ = 1, 3 do
		chosen, total = SelectSoiree(values, entry, entered, room)
		Apply()
		for _, need in ipairs(base) do
			need.tier = total + SOIREE_REGION <= budget and TIER_NEXT or TIER_AFTER
		end
		local r = Reroute(keptCands, base)
		if not r then
			if result then
				chosen = kept -- (le trajet gardé est celui d'avant : on remet les quêtes comme pour lui)
				Apply()
			end
			break
		end
		local from, eta = SessionEnd(plan, r)
		pick = not skipInn and PickInn(opts, plan, from, eta, yield) or nil
		local list = {}
		for _, need in ipairs(base) do
			list[#list + 1] = need
		end
		local Montee = ns.Montee
		local mines = Montee and opts.includeMining ~= false and Montee.MineNeeds(opts, plan, r.stops, r.order, r.C, yield, TIER_INN)
		for _, m in ipairs(type(mines) == "table" and mines or {}) do
			if not (opts.skipped or {})["S:" .. m.key] then
				list[#list + 1] = m
			end
		end
		if pick then
			list[#list + 1] = InnNeed(pick)
		end
		local r2 = Reroute(keptCands, list)
		if not r2 and #list > #base + (pick and 1 or 0) then
			-- sans les filons
			list = {}
			for _, need in ipairs(base) do
				list[#list + 1] = need
			end
			if pick then
				list[#list + 1] = InnNeed(pick)
			end
			r2 = Reroute(keptCands, list)
		end
		r2 = r2 or r
		result, kept = r2, chosen
		local endEta = InnEta(r2) or select(2, SessionEnd(plan, r2))
		local over = endEta - budget * SOIREE_SLACK - 60
		if over <= 0 or room <= 0 then
			break
		end
		-- Plus long que prévu (moins d'étapes partagées qu'estimé) : on recommence avec moins de temps.
		room = room - over
	end
	if not result then
		return false
	end
	local ids, count = {}, 0
	for q in pairs(chosen) do
		ids[q.id] = true
		count = count + 1
	end
	plan.soireeIds = ids
	plan.soiree = {
		budget = budget, untilAt = opts.soiree.untilAt, minutes = opts.soiree.minutes, chosen = count,
		inn = pick and { name = pick.name, zone = pick.zone, hearth = pick.hearth } or nil,
		noInn = not pick, skippedInn = skipInn and true or nil,
	}
	return true
end
