-- Itinéraire : faire le tri dans ton journal (/iti tri), SUR TA DEMANDE seulement. Liste des quêtes grises (trop basses
-- pour rapporter de l'XP), échouées, ou qui ne te rapportent rien, avec la raison ; tu coches, tu confirmes, elles sont
-- abandonnées. Gardées d'office : la quête suivie, les quêtes de classe ou de métier, celles dont la récompense
-- t'améliore, celles qui mènent à une suite de ton niveau. (Le trajet, lui, n'écarte jamais rien tout seul.)
local _, ns = ...
local Tri = {}
ns.Tri = Tri

local LOW_SHARE = 0.01 -- « ne rapporte rien » : moins de 1 % de ton niveau (et moins de 100 XP au minimum)
local CONFIRM_DELAY = 6 -- secondes pour confirmer l'abandon (second clic)

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

local function Num(v)
	if type(v) ~= "number" or (issecretvalue and issecretvalue(v)) then
		return nil
	end
	return v
end

local function Gray(level)
	local fn = ns.Planner and ns.Planner.GrayLevel
	return fn and fn(level) or (level - 6)
end

local function Thousands(n)
	local s = tostring(math.floor(n or 0))
	return (s:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^%s+", ""))
end

-- Le journal trié : `offer` = quêtes proposées à l'abandon (cochées d'office ou non), `kept` = quêtes grises ou sans
-- XP que l'on garde, avec la raison. Rien n'est touché ici.
function Tri.Analyse()
	local level = Num(Call(UnitLevel, "player")) or 1
	local gray = Gray(level)
	local xpMax = UnitXPMax and Num(Call(UnitXPMax, "player")) or nil
	local low = math.max(100, (xpMax or 0) * LOW_SHARE)
	local gear = {}
	local okG, opts = pcall(ns.Gear.PlanOptions)
	if okG and type(opts) == "table" and type(opts.quests) == "table" then
		gear = opts.quests
	end
	local focus = ns.session and ns.session.focus
	local offer, kept = {}, {}
	for _, q in ipairs(ns.Data.ReadLog()) do
		local quest = ns.Data.Quest(q.id)
		local xp = ns.Data.QuestXP(q.id) or 0
		local isGray = (q.level or 0) > 0 and q.level <= gray
		local nothing = (q.level or 0) > 0 and xp < low
		if q.failed or isGray or nothing then
			-- Raisons de la garder (dans l'ordre)
			local keep
			if q.id == focus then
				keep = "c'est ta quête suivie"
			elseif quest and (tonumber(quest.requiredClasses) or 0) > 0 then
				keep = "quête de classe (technique ou objet de classe)"
			elseif quest and type(quest.requiredSkill) == "table" then
				keep = "quête de métier"
			elseif gear[q.id] then
				keep = "sa récompense t'améliore : " .. tostring(gear[q.id].name or "objet") .. " " .. tostring(gear[q.id].gain or "")
			else
				local nextId = quest and tonumber(quest.nextQuestInChain)
				local nextQuest = nextId and nextId > 0 and ns.Data.Quest(nextId)
				local nextLevel = nextQuest and tonumber(nextQuest.level)
				if nextLevel and nextLevel > gray and not ns.Data.Completed(nextId) then
					keep = string.format("mène à « %s » (niv %d), encore utile", tostring(nextQuest.name or nextId), nextLevel)
				end
			end
			local e = { id = q.id, title = q.title, level = q.level, xp = xp, complete = q.complete }
			if q.failed then
				e.reason, e.checked = "échouée : elle ne sert plus à rien (reprends-la chez son donneur si tu veux la refaire)", true
				offer[#offer + 1] = e
			elseif keep then
				e.reason = keep
				kept[#kept + 1] = e
			elseif q.complete then
				e.reason = string.format("%s, mais terminée : la rendre rapporte encore ~%s XP", isGray and "grise" or "presque sans XP",
					Thousands(xp))
				e.checked = false
				offer[#offer + 1] = e
			else
				e.reason = isGray and string.format("grise (niv %d ; grise jusqu'au niv %d pour toi) : ~%s XP", q.level, gray, Thousands(xp))
					or string.format("ne te rapporte presque rien : ~%s XP", Thousands(xp))
				e.checked = true
				offer[#offer + 1] = e
			end
		end
	end
	return offer, kept, { level = level, gray = gray, low = low }
end

-------------------------------------------------------------------------------
-- Abandon (au clic du joueur, après confirmation)
-------------------------------------------------------------------------------
local function InLog(id)
	local Q = C_QuestLog
	local idx = Q and Q.GetLogIndexForQuestID and Call(Q.GetLogIndexForQuestID, id)
	if idx then
		return true
	end
	if Q and Q.IsOnQuest then
		return Call(Q.IsOnQuest, id) and true or false
	end
	return false
end

local function AbandonOne(id)
	local Q = C_QuestLog
	if Q and Q.SetSelectedQuest and Q.SetAbandonQuest and Q.AbandonQuest then
		local ok = pcall(function()
			Q.SetSelectedQuest(id)
			Q.SetAbandonQuest()
			Q.AbandonQuest()
		end)
		return ok
	end
	-- (ancienne interface : par la ligne du journal)
	local idx = Q and Q.GetLogIndexForQuestID and Call(Q.GetLogIndexForQuestID, id)
	if idx and SelectQuestLogEntry and SetAbandonQuest and AbandonQuest then
		return pcall(function()
			SelectQuestLogEntry(idx)
			SetAbandonQuest()
			AbandonQuest()
		end)
	end
	return false
end

-- Abandonne les quêtes `list` ({ id, title }…), puis vérifie dans le journal ce qui est vraiment parti.
function Tri.Abandon(list, done)
	local Q = C_QuestLog
	local previous = Q and Q.GetSelectedQuest and Call(Q.GetSelectedQuest)
	local tried = {}
	for _, e in ipairs(list) do
		if InLog(e.id) and e.id ~= (ns.session and ns.session.focus) then
			tried[#tried + 1] = e
			AbandonOne(e.id)
		end
	end
	if previous and InLog(previous) and Q.SetSelectedQuest then
		Call(Q.SetSelectedQuest, previous)
	end
	C_Timer.After(1.5, function()
		local gone, stuck = {}, {}
		for _, e in ipairs(tried) do
			if InLog(e.id) then
				stuck[#stuck + 1] = "« " .. tostring(e.title) .. " »"
			else
				gone[#gone + 1] = "« " .. tostring(e.title) .. " »"
			end
		end
		if #gone > 0 then
			ns.Print(string.format("%d quête(s) abandonnée(s) : %s.", #gone, table.concat(gone, ", ")))
		end
		if #stuck > 0 then
			ns.Print(string.format("|cffff9933le jeu a refusé d'en abandonner %d|r : %s. Abandonne-les à la main dans ton journal (L).",
				#stuck, table.concat(stuck, ", ")))
		end
		if ns.char then
			ns.char.tri = { at = date("%Y-%m-%d %H:%M"), gone = #gone, stuck = #stuck }
		end
		ns.RequestPlan("tri", 0.5)
		if done then
			pcall(done, gone, stuck)
		end
	end)
	return #tried
end

-------------------------------------------------------------------------------
-- Fenêtre « Trier mon journal »
-------------------------------------------------------------------------------
local frame, intro, keptText, child, scroll, go, all
local rows, offer, kept, info = {}, {}, {}, {}
local armed

local function Count()
	local n = 0
	for _, e in ipairs(offer) do
		if e.checked then
			n = n + 1
		end
	end
	return n
end

local function UpdateButton()
	local n = Count()
	if armed and GetTime() - armed <= CONFIRM_DELAY then
		go:SetText(string.format("|cffff5555Sûr ? Re-clique : abandonner %d quête(s)|r", n))
	else
		armed = nil
		go:SetText(n > 0 and string.format("Abandonner les %d quête(s) cochée(s)", n) or "Rien de coché")
	end
	go:SetEnabled(n > 0)
end

local function RowText(e)
	local box = e.checked and "|cff00ff00[x]|r " or "[  ] "
	return box .. "« " .. tostring(e.title) .. " »" .. (e.level and e.level > 0 and (" (niv " .. e.level .. ")") or "")
		.. "\n     |cff999999" .. tostring(e.reason) .. "|r"
end

function Tri.Refresh()
	if not (frame and frame:IsShown()) then
		return
	end
	offer, kept, info = Tri.Analyse()
	armed = nil
	intro:SetText(string.format("Niveau %d : une quête du niveau %d ou moins est grise (presque plus d'XP). Coche ce que tu veux abandonner. "
		.. "Gardées d'office : quête suivie, quêtes de classe ou de métier, récompense qui t'améliore, suite de ton niveau.",
		info.level, info.gray))
	local y = 0
	for i, e in ipairs(offer) do
		local b = rows[i]
		if not b then
			b = ns.UI.Skin.Button(child, "", 500, 34)
			b.label:SetJustifyH("LEFT")
			rows[i] = b
		end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 0, -y)
		b:SetText(RowText(e))
		b:SetScript("OnClick", function(self)
			e.checked = not e.checked
			armed = nil
			self:SetText(RowText(e))
			UpdateButton()
		end)
		b:Show()
		y = y + 37
	end
	for i = #offer + 1, #rows do
		rows[i]:Hide()
	end
	local lines = {}
	if #offer == 0 then
		lines[#lines + 1] = "|cff66ff66Rien à jeter : aucune quête grise ou sans XP à abandonner.|r"
	end
	if #kept > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "|cffffd200Grises ou presque sans XP, mais gardées :|r"
		for _, e in ipairs(kept) do
			lines[#lines + 1] = "  « " .. tostring(e.title) .. " »" .. (e.level and e.level > 0 and (" (niv " .. e.level .. ")") or "")
				.. " : " .. tostring(e.reason)
		end
	end
	keptText:ClearAllPoints()
	keptText:SetPoint("TOPLEFT", 2, -(y + 4))
	keptText:SetText(table.concat(lines, "\n"))
	child:SetHeight(math.max(20, y + 8 + (keptText:GetStringHeight() or 0)))
	UpdateButton()
	ns.UI.Skin.Panel(frame, 0.97)
	ns.UI.Skin.HeaderColors(frame)
end

local function Create()
	local Skin = ns.UI.Skin
	frame = CreateFrame("Frame", "ItineraireTri", UIParent, "BackdropTemplate")
	frame:SetSize(560, 520)
	frame:SetPoint("CENTER", 0, 30)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "ItineraireTri")
	Skin.Header(frame, "Trier mon journal", "Interface\\Icons\\INV_Misc_Book_08", 26)
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	intro = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	intro:SetPoint("TOPLEFT", 14, -34)
	intro:SetPoint("RIGHT", -14, 0)
	intro:SetJustifyH("LEFT")
	local ok, sf = pcall(CreateFrame, "ScrollFrame", "ItineraireTriScroll", frame, "UIPanelScrollFrameTemplate")
	if not ok then
		sf = CreateFrame("ScrollFrame", nil, frame)
		sf:EnableMouseWheel(true)
		sf:SetScript("OnMouseWheel", function(self, delta)
			local max = self:GetVerticalScrollRange() or 0
			self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - delta * 40)))
		end)
	end
	scroll = sf
	scroll:SetPoint("TOPLEFT", 14, -76)
	scroll:SetPoint("BOTTOMRIGHT", -32, 46)
	child = CreateFrame("Frame", nil, scroll)
	child:SetSize(505, 20)
	scroll:SetScrollChild(child)
	keptText = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	keptText:SetWidth(500)
	keptText:SetJustifyH("LEFT")
	keptText:SetSpacing(2)
	all = Skin.Button(frame, "Tout cocher", 110, 24, function()
		local any = false
		for _, e in ipairs(offer) do
			any = any or not e.checked
		end
		for _, e in ipairs(offer) do
			e.checked = any
		end
		armed = nil
		for i, e in ipairs(offer) do
			rows[i]:SetText(RowText(e))
		end
		UpdateButton()
	end)
	all:SetPoint("BOTTOMLEFT", 12, 12)
	go = Skin.Button(frame, "", 330, 24, function()
		local n = Count()
		if n == 0 then
			return
		end
		if not (armed and GetTime() - armed <= CONFIRM_DELAY) then
			armed = GetTime()
			UpdateButton()
			C_Timer.After(CONFIRM_DELAY + 0.1, function()
				if frame:IsShown() then
					UpdateButton()
				end
			end)
			return
		end
		armed = nil
		local list = {}
		for _, e in ipairs(offer) do
			if e.checked then
				list[#list + 1] = e
			end
		end
		go:SetText("Abandon en cours…")
		go:SetEnabled(false)
		Tri.Abandon(list, function()
			Tri.Refresh()
		end)
	end)
	go:SetPoint("BOTTOMRIGHT", -12, 12)
	frame:Hide()
end

function Tri.Toggle(show)
	if not frame then
		Create()
	end
	if show == nil then
		show = not frame:IsShown()
	end
	if show then
		frame:Show()
		Tri.Refresh()
	else
		frame:Hide()
	end
end

function Tri.Shown()
	return frame and frame:IsShown() or false
end

-- Pour « À savoir » : combien de quêtes grises (hors quête suivie) dans le journal du trajet.
function Tri.GrayCount(plan)
	if not (plan and plan.quests and plan.level) then
		return 0
	end
	local gray, n = Gray(plan.level), 0
	for _, q in ipairs(plan.quests) do
		if not q.external and (q.level or 0) > 0 and q.level <= gray and q.id ~= (ns.session and ns.session.focus) then
			n = n + 1
		end
	end
	return n
end
