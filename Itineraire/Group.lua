-- Itinéraire : partage du trajet dans un groupe de 2 à 5 joueurs (activable, désactivé par défaut).
-- Chaque membre envoie l'état de son journal. Le guide (le chef de groupe s'il partage, sinon le
-- premier nom par ordre alphabétique) calcule UN trajet pour tout le groupe et l'envoie : les autres
-- le suivent dans leur fenêtre et avec leur flèche. Tout ce qui arrive du réseau est vérifié et borné.
local _, ns = ...
local Group = {}
ns.Group = Group

local PREFIX = "ITIN1"
local VERSION = 1
local PACKET = 200 -- octets de données par message (le jeu en accepte 255)
local SEND_GAP = 0.2 -- secondes entre deux messages
local MAX_PARTS = 40
local MAX_QUESTS = 40
local MAX_OBJECTIVES = 8
local MAX_STOPS = 25
local GUIDE_TIMEOUT = 150 -- sans nouvelles du guide : retour à ton propre trajet
local HEARTBEAT = 60 -- le guide redonne signe de vie
local STATE_DELAY = 2 -- regroupe les changements du journal avant de les envoyer

local members = {} -- [nom] = { share, level, quests, at }
local following -- { guide, at, plan }
local outbox, sending = {}, false
local inbox = {}
local seq, routeSeq = 0, 0
local lastState, lastRouteBody, lastRouteAt = nil, nil, 0
local stateTimer
local lastVersionAt, versionWarned = -1000, {}

-------------------------------------------------------------------------------
-- Noms et groupe
-------------------------------------------------------------------------------
local function Short(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	if Ambiguate then
		local ok, short = pcall(Ambiguate, name, "none")
		if ok and type(short) == "string" and short ~= "" then
			return short
		end
	end
	return (name:gsub("%-.*$", ""))
end

local function Me()
	return Short(UnitName("player")) or "?"
end
Group.Me = Me

function Group.Enabled()
	return ns.db ~= nil and ns.db.groupShare == true
end

local function InRaid()
	return IsInRaid and IsInRaid() and true or false
end

local function InParty()
	return (IsInGroup and IsInGroup() and not InRaid()) and true or false
end

-- Membres présents (toi compris) et chef de groupe.
local function Roster()
	local list, leader = {}, nil
	local me = Me()
	list[me] = true
	if UnitIsGroupLeader and UnitIsGroupLeader("player") then
		leader = me
	end
	for i = 1, 4 do
		local unit = "party" .. i
		if UnitExists and UnitExists(unit) then
			local name, realm = UnitName(unit)
			local short = Short(name and ((realm and realm ~= "") and (name .. "-" .. realm) or name))
			if short then
				list[short] = true
				if UnitIsGroupLeader and UnitIsGroupLeader(unit) then
					leader = short
				end
			end
		end
	end
	return list, leader
end

-- Équipiers (sans toi) qui ont Itinéraire avec le partage activé.
local function Sharers()
	local roster, leader = Roster()
	local names = {}
	for name, m in pairs(members) do
		if roster[name] and m.share then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	return names, leader
end

function Group.Active()
	return Group.Enabled() and InParty() and #(Sharers()) > 0
end

function Group.Guide()
	if not Group.Active() then
		return nil
	end
	local names, leader = Sharers()
	local me = Me()
	local all = { [me] = true }
	for _, name in ipairs(names) do
		all[name] = true
	end
	if leader and all[leader] then
		return leader
	end
	local best = me
	for name in pairs(all) do
		if name < best then
			best = name
		end
	end
	return best
end

function Group.IsGuide()
	return Group.Active() and Group.Guide() == Me()
end

-- On suit le trajet d'un autre seulement quand on l'a vraiment reçu (sinon : son propre trajet).
function Group.Following()
	return following ~= nil and Group.Active() and Group.Guide() == following.guide
end

function Group.Size()
	return #(Sharers()) + 1
end

function Group.Mates()
	return (Sharers())
end

-------------------------------------------------------------------------------
-- Messages (découpés en morceaux de 200 octets, envoyés à 5 par seconde)
-------------------------------------------------------------------------------
local function Pump()
	if sending then
		return
	end
	sending = true
	local function Step()
		local msg = table.remove(outbox, 1)
		if msg and C_ChatInfo and C_ChatInfo.SendAddonMessage then
			pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "PARTY")
		end
		if #outbox > 0 then
			C_Timer.After(SEND_GAP, Step)
		else
			sending = false
		end
	end
	Step()
end

-- Découpe sans couper un caractère accentué (UTF-8) en deux.
local function Split(payload)
	local parts, i = {}, 1
	while i <= #payload do
		local j = math.min(#payload, i + PACKET - 1)
		while j < #payload and j > i do
			local b = payload:byte(j + 1)
			if b >= 0x80 and b < 0xC0 then
				j = j - 1
			else
				break
			end
		end
		parts[#parts + 1] = payload:sub(i, j)
		i = j + 1
	end
	if #parts == 0 then
		parts[1] = ""
	end
	return parts
end

local function Send(kind, payload)
	if not (InParty() and C_ChatInfo and C_ChatInfo.SendAddonMessage) then
		return
	end
	local parts = Split(payload)
	if #parts > MAX_PARTS then
		return
	end
	-- Un message plus récent du même genre remplace celui qui attend encore.
	for k = #outbox, 1, -1 do
		if outbox[k]:sub(1, 1) == kind then
			table.remove(outbox, k)
		end
	end
	seq = seq % 9999 + 1
	for p, chunk in ipairs(parts) do
		outbox[#outbox + 1] = kind .. seq .. ":" .. p .. "/" .. #parts .. ":" .. chunk
	end
	Pump()
end

-- Retire de quoi casser le format ou le texte affiché (« | » = codes de couleur/liens du jeu).
local function TrimUtf8(text)
	local n = #text
	local k = n
	while k > 0 do
		local b = text:byte(k)
		if b < 0x80 then
			return text
		elseif b >= 0xC0 then
			local need = b >= 0xF0 and 4 or b >= 0xE0 and 3 or 2
			return (n - k + 1 >= need) and text or text:sub(1, k - 1)
		end
		k = k - 1
	end
	return text
end

local function Clean(text, max)
	text = tostring(text or ""):gsub("[|~;#\r\n%z]", " ")
	if #text > max then
		text = TrimUtf8(text:sub(1, max))
	end
	return text
end

local function CleanKey(text)
	return (tostring(text or ""):gsub("[|~;\r\n%z]", "_")):sub(1, 120)
end

-------------------------------------------------------------------------------
-- État du journal (chaque membre -> groupe)
-------------------------------------------------------------------------------
local function StatePayload()
	local parts = {}
	if Group.Enabled() then
		for _, q in ipairs(ns.Data.ReadLog()) do
			if #parts >= MAX_QUESTS then
				break
			end
			if not q.failed then
				local objs = {}
				for i, o in ipairs(q.objectives) do
					if i > MAX_OBJECTIVES then
						break
					end
					objs[#objs + 1] = math.floor(tonumber(o.numFulfilled) or 0) .. "/" .. math.floor(tonumber(o.numRequired) or 0)
				end
				parts[#parts + 1] = q.id .. "," .. (q.complete and 1 or 0) .. (#objs > 0 and ("," .. table.concat(objs, ",")) or "")
			end
		end
	end
	return VERSION .. "#" .. (Group.Enabled() and 1 or 0) .. "#" .. (UnitLevel("player") or 0) .. "#" .. table.concat(parts, ";")
end

function Group.ParseState(payload)
	local v, share, level, list = payload:match("^(%d+)#([01])#(%d+)#(.*)$")
	if tonumber(v) ~= VERSION then
		return nil
	end
	local state = { share = share == "1", level = math.min(tonumber(level) or 0, 100), quests = {} }
	for entry in list:gmatch("[^;]+") do
		if #state.quests >= MAX_QUESTS then
			break
		end
		local fields = {}
		for field in entry:gmatch("[^,]+") do
			fields[#fields + 1] = field
		end
		local id = tonumber(fields[1])
		if id and id >= 1 and id <= 9999999 and id % 1 == 0 then
			local q = { id = id, complete = fields[2] == "1", objectives = {} }
			for k = 3, math.min(#fields, 2 + MAX_OBJECTIVES) do
				local have, need = fields[k]:match("^(%d+)/(%d+)$")
				have, need = tonumber(have), tonumber(need)
				q.objectives[#q.objectives + 1] = {
					have = math.min(have or 0, 999),
					need = math.max(1, math.min(need or 1, 999)),
				}
			end
			state.quests[#state.quests + 1] = q
		end
	end
	return state
end

function Group.SendState(force)
	if not InParty() or (not Group.Enabled() and not force) then
		return
	end
	local payload = StatePayload()
	if force or payload ~= lastState then
		lastState = payload
		Send("S", payload)
	end
end

-- Le journal a bougé : on envoie l'état un peu plus tard (plusieurs changements = un seul message).
function Group.ScheduleState()
	if not (Group.Enabled() and InParty()) or stateTimer then
		return
	end
	stateTimer = C_Timer.NewTimer(STATE_DELAY, function()
		stateTimer = nil
		Group.SendState(false)
	end)
end

-- Quêtes des équipiers pour le calcul du guide : une entrée par quête, avec qui l'a, et pour chaque
-- objectif ce qu'il reste à faire pour le plus en retard.
function Group.QuestsForPlan()
	local byId, list = {}, {}
	for _, name in ipairs((Sharers())) do
		for _, q in ipairs(members[name].quests or {}) do
			local e = byId[q.id]
			if not e then
				e = { id = q.id, complete = q.complete, objectives = {}, members = {} }
				for i, o in ipairs(q.objectives) do
					e.objectives[i] = { have = o.have, need = o.need }
				end
				byId[q.id] = e
				list[#list + 1] = e
			else
				e.complete = e.complete and q.complete
				for i, o in ipairs(q.objectives) do
					local cur = e.objectives[i]
					if not cur or (o.need - o.have) > (cur.need - cur.have) then
						e.objectives[i] = { have = o.have, need = o.need }
					end
				end
			end
			e.members[#e.members + 1] = name
		end
	end
	return list
end

-------------------------------------------------------------------------------
-- Trajet (guide -> groupe)
-------------------------------------------------------------------------------
local function RouteBody(plan)
	local stops = {}
	for k = 1, math.min(#plan.order, MAX_STOPS) do
		local s = plan.order[k]
		local kind = s.kind
		if kind == "area" then
			local t = s.tasks and s.tasks[1] and s.tasks[1].objective and s.tasks[1].objective.type
			kind = "area." .. (t or "")
		end
		local ids = {}
		for i, q in ipairs(s.quests or {}) do
			if i <= 6 then
				ids[#ids + 1] = q.id
			end
		end
		stops[#stops + 1] = table.concat({
			Clean(kind, 24), s.map or 0,
			math.floor((s.x or 0) * 10000 + 0.5), math.floor((s.y or 0) * 10000 + 0.5),
			Clean(s.title, 90), math.floor(s.leg or 0), math.floor(s.work or 0), table.concat(ids, ","),
			Clean(table.concat(s.owners or {}, ","), 90), CleanKey(s.key), tonumber(s.npc) or 0, math.floor(s.radius or 0),
		}, "~")
	end
	return #stops .. "#" .. math.floor((plan.travel or 0) + (plan.workTime or 0)) .. "#" .. table.concat(stops, ";")
end

local KINDS = { area = true, turnin = true, dungeon = true, pickup = true, service = true }

function Group.ParseRoute(payload)
	local v, id, count, total, body = payload:match("^(%d+)#(%d+)#(%d+)#(%d+)#(.*)$")
	if tonumber(v) ~= VERSION then
		return nil
	end
	local route = { id = tonumber(id), total = tonumber(total) or 0, stops = {} }
	for entry in body:gmatch("[^;]+") do
		if #route.stops >= MAX_STOPS or #route.stops >= (tonumber(count) or 0) then
			break
		end
		local f = {}
		for field in (entry .. "~"):gmatch("([^~]*)~") do
			f[#f + 1] = field
		end
		local kind, sub = (f[1] or ""):match("^(%a+)%.?(%a*)$")
		local map, x, y = tonumber(f[2]), tonumber(f[3]), tonumber(f[4])
		if kind and KINDS[kind] and map and map > 0 and map < 100000 and map % 1 == 0
			and x and y and x >= 0 and x <= 10000 and y >= 0 and y <= 10000 then
			local ids = {}
			for qid in (f[8] or ""):gmatch("%d+") do
				local n = tonumber(qid)
				if n and n >= 1 and n <= 9999999 and #ids < 6 then
					ids[#ids + 1] = n
				end
			end
			local owners = {}
			for name in (f[9] or ""):gmatch("[^,]+") do
				if #owners < 5 then
					owners[#owners + 1] = Clean(name, 40)
				end
			end
			route.stops[#route.stops + 1] = {
				kind = kind, sub = sub ~= "" and sub or nil, map = map, x = x / 10000, y = y / 10000,
				title = Clean(f[5], 90), leg = math.min(tonumber(f[6]) or 0, 36000), work = math.min(tonumber(f[7]) or 0, 36000),
				ids = ids, owners = owners[1] and owners or nil, key = CleanKey(f[10]),
				npc = tonumber(f[11]), radius = math.min(tonumber(f[12]) or 0, 300),
			}
		end
	end
	return route
end

-- Le trajet reçu, présenté comme un plan (fenêtre + flèche).
local function FollowPlan(guide, route)
	local plan = {
		order = {}, quests = {}, side = { dungeons = {}, pvp = {}, failed = {}, unknown = {} },
		group = { guide = guide, size = Group.Size() }, at = time and time() or nil,
	}
	local titles = {}
	for _, q in ipairs(ns.Data.ReadLog()) do
		titles[q.id] = q.title
	end
	local travel, work, eta = 0, 0, 0
	for k, r in ipairs(route.stops) do
		local wx, wy, inst = ns.Geo.World(r.map, r.x, r.y)
		local quests, questSet = {}, {}
		for _, id in ipairs(r.ids) do
			quests[#quests + 1] = { id = id, title = titles[id] or ("quête " .. id) }
			questSet[id] = true
		end
		travel, work = travel + r.leg, work + r.work
		eta = eta + r.leg + r.work
		plan.order[k] = {
			kind = r.kind, map = r.map, x = r.x, y = r.y, wx = wx, wy = wy, inst = inst,
			title = r.title, subtitle = ns.Geo.ZoneName(r.map), leg = r.leg, work = r.work, eta = eta,
			quests = quests, questSet = questSet, pickups = {}, tier = 0, number = k,
			tasks = r.kind == "area" and { { objective = { type = r.sub } } } or {},
			details = { "Trajet du groupe, calculé par " .. guide .. "." },
			key = r.key ~= "" and r.key or ("G" .. k), owners = r.owners,
			npc = (r.npc and r.npc > 0) and r.npc or nil, radius = (r.radius and r.radius > 0) and r.radius or nil,
		}
	end
	plan.travel, plan.workTime = travel, work
	ns.Planner.MarkTours(plan.order)
	return plan
end

function Group.OnPlan(plan)
	if not Group.IsGuide() then
		return
	end
	local body = RouteBody(plan)
	if body ~= lastRouteBody or GetTime() - lastRouteAt > HEARTBEAT * 2 then
		lastRouteBody, lastRouteAt = body, GetTime()
		routeSeq = routeSeq % 9999 + 1
		Send("R", VERSION .. "#" .. routeSeq .. "#" .. body)
	end
end

-------------------------------------------------------------------------------
-- Réception
-------------------------------------------------------------------------------
local function OnState(sender, payload)
	local state = Group.ParseState(payload)
	if not state then
		return
	end
	local before = members[sender]
	state.at = GetTime()
	members[sender] = state
	if not state.share and following and following.guide == sender then
		following = nil
	end
	local changed = not before or before.share ~= state.share or payload ~= before.payload
	state.payload = payload
	if changed then
		if Group.IsGuide() or not before then
			ns.RequestPlan("groupe", 1)
		end
		if not before then
			-- Nouveau venu : il a besoin de notre état (et du trajet si on guide).
			Group.SendState(true)
			lastRouteBody = nil
		end
	end
end

local function OnRoute(sender, payload)
	if not (Group.Enabled() and InParty()) then
		return
	end
	local m = members[sender]
	if not m then
		members[sender] = { share = true, quests = {}, at = GetTime() }
	else
		m.share, m.at = true, GetTime()
	end
	if Group.Guide() ~= sender then
		return
	end
	local route = Group.ParseRoute(payload)
	if not route or #route.stops == 0 then
		return
	end
	following = { guide = sender, at = GetTime() }
	following.plan = FollowPlan(sender, route)
	if ns.OnGroupPlan then
		ns.OnGroupPlan(following.plan)
	end
end

-------------------------------------------------------------------------------
-- Versions : prévenir quand un équipier a un Itinéraire plus récent (même sans partage de groupe)
-------------------------------------------------------------------------------
local function MyVersion()
	return ns.AddonVersion and ns.AddonVersion(ns.OWNER or "Itineraire") or nil
end

function Group.AnnounceVersion(force)
	local mine = MyVersion()
	if not (mine and InParty()) then
		return
	end
	local now = GetTime()
	if not force and now - lastVersionAt < 60 then
		return
	end
	lastVersionAt = now
	Send("V", mine)
end

local function OnVersion(sender, payload)
	if type(payload) ~= "string" or #payload > 16 or not payload:match("^%d+%.%d+%.?%d*$") then
		return
	end
	local mine = MyVersion()
	local cmp = ns.CompareVersions and ns.CompareVersions(mine, payload)
	if cmp == -1 and not versionWarned[payload] then
		versionWarned[payload] = true
		ns.Print(sender .. " a Itinéraire " .. payload .. " (toi : " .. tostring(mine) .. ") : relance l'installateur"
			.. " (ou attends la mise à jour automatique) pour avoir la même version.")
	elseif cmp == 1 then
		Group.AnnounceVersion() -- il a une version plus ancienne : on lui dit la nôtre (au plus 1 fois par minute)
	end
end

local function OnHeartbeat(sender)
	if following and following.guide == sender then
		following.at = GetTime()
	end
	if members[sender] then
		members[sender].at = GetTime()
	end
end

local function Secret(value)
	return (issecretvalue and issecretvalue(value)) or (canaccessvalue and not canaccessvalue(value)) or false
end

function Group.OnMessage(prefix, text, channel, sender)
	-- Les messages d'autres addons arrivent ici aussi ; certains peuvent être « secrets » (combat, instance).
	if Secret(prefix) or Secret(text) or Secret(sender) then
		return
	end
	if prefix ~= PREFIX or type(text) ~= "string" or #text > 255 then
		return
	end
	sender = Short(sender)
	if not sender or sender == Me() then
		return
	end
	local roster = Roster()
	if not roster[sender] then
		return -- seulement les membres du groupe
	end
	local kind, id, part, total, payload = text:match("^([SRQHV])(%d+):(%d+)/(%d+):(.*)$")
	part, total = tonumber(part), tonumber(total)
	if not kind or not part or not total or total < 1 or total > MAX_PARTS or part < 1 or part > total then
		return
	end
	local key = sender .. ":" .. kind .. id
	local box = inbox[key]
	if not box or box.total ~= total then
		box = { parts = {}, total = total, n = 0, at = GetTime() }
		inbox[key] = box
	end
	if not box.parts[part] then
		box.parts[part] = payload
		box.n = box.n + 1
	end
	if box.n < total then
		return
	end
	inbox[key] = nil
	local full = table.concat(box.parts)
	if kind == "S" then
		OnState(sender, full)
	elseif kind == "R" then
		OnRoute(sender, full)
	elseif kind == "H" then
		OnHeartbeat(sender)
	elseif kind == "V" then
		OnVersion(sender, full)
	elseif kind == "Q" then
		Group.SendState(true)
		lastRouteBody = nil
		if Group.IsGuide() then
			ns.RequestPlan("groupe", 0.5)
		end
	end
end

-------------------------------------------------------------------------------
-- Vie du groupe
-------------------------------------------------------------------------------
function Group.OnRoster()
	Group.AnnounceVersion()
	if not Group.Enabled() and not following and not next(members) then
		return -- partage coupé : rien à faire (et surtout pas de recalcul à chaque changement du groupe)
	end
	local wasActive = Group.Active()
	if not InParty() then
		members, following = {}, nil
	else
		local roster = Roster()
		for name in pairs(members) do
			if not roster[name] then
				members[name] = nil
			end
		end
		if following and not roster[following.guide] then
			following = nil
		end
		if Group.Enabled() then
			Group.SendState(true)
			Send("Q", tostring(VERSION))
		end
	end
	if wasActive ~= Group.Active() or not Group.Following() then
		ns.RequestPlan("groupe", 1)
	end
end

function Group.SetEnabled(on)
	ns.db.groupShare = on and true or false
	if on then
		Group.SendState(true)
		Send("Q", tostring(VERSION))
	else
		Group.SendState(true) -- annonce « je ne partage plus »
		following = nil
	end
	lastRouteBody = nil
	ns.RequestPlan("groupe", 0)
end

function Group.Tick()
	local now = GetTime()
	for key, box in pairs(inbox) do
		if now - box.at > 30 then
			inbox[key] = nil
		end
	end
	if following and (now - following.at > GUIDE_TIMEOUT or not Group.Active() or Group.Guide() ~= following.guide) then
		following = nil
		ns.Print("plus de nouvelles du guide : retour à ton propre trajet.")
		ns.RequestPlan("groupe", 0)
	end
	if Group.IsGuide() and now - lastRouteAt > HEARTBEAT then
		lastRouteAt = now
		Send("H", tostring(VERSION))
	end
end

function Group.Init()
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
	end
	Group.AnnounceVersion(true)
	if Group.Enabled() and InParty() then
		Group.SendState(true)
		Send("Q", tostring(VERSION))
	end
end

function Group.StatusText()
	if not Group.Enabled() then
		return nil
	end
	if InRaid() then
		return "Partage de groupe : seulement en groupe de 5 (pas en raid)."
	end
	if not InParty() then
		return "Partage de groupe activé : il démarre dès que tu es en groupe."
	end
	local mates = Group.Mates()
	if #mates == 0 then
		return "Partage de groupe : personne d'autre ici n'a Itinéraire avec le partage activé."
	end
	if Group.IsGuide() then
		return "|cff66ccffGroupe :|r tu guides (" .. table.concat(mates, ", ") .. ")."
	end
	local guide = Group.Guide()
	if Group.Following() then
		return "|cff66ccffGroupe :|r tu suis le trajet de " .. guide .. "."
	end
	return "|cff66ccffGroupe :|r en attente du trajet de " .. tostring(guide) .. "…"
end

-- « pour toi, Alix » / « pour tous » (les noms viennent du guide ou de ton propre calcul).
function Group.OwnersText(owners, size)
	if not owners or #owners == 0 then
		return nil
	end
	local me = Me()
	if size and size > 1 and #owners >= size then
		return "pour tous"
	end
	local names = {}
	for _, name in ipairs(owners) do
		names[#names + 1] = name == me and "toi" or name
	end
	return "pour " .. table.concat(names, ", ")
end
