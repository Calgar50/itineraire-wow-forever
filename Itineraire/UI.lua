-- Itinéraire : fenêtre du trajet, étapes numérotées 1, 2, 3… (entièrement réglable : voir Options.lua)
local _, ns = ...
local UI = {}
ns.UI = UI

local ICONS = {
	turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
	pickup = "Interface\\GossipFrame\\AvailableQuestIcon",
	monster = "Interface\\Icons\\Ability_DualWield",
	killcredit = "Interface\\Icons\\Ability_DualWield",
	item = "Interface\\Icons\\INV_Misc_Bag_10",
	object = "Interface\\Icons\\INV_Misc_Gear_01",
	event = "Interface\\Icons\\INV_Misc_Map_01",
	dungeon = "Interface\\Icons\\INV_Misc_Key_03",
	area = "Interface\\Icons\\INV_Misc_Map_01",
	service = "Interface\\GossipFrame\\VendorGossipIcon",
	trainer = "Interface\\GossipFrame\\TrainerGossipIcon",
}

local BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 14,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- Thèmes : bordure, fond, surbrillance de l'étape en cours.
UI.THEMES = {
	{ key = "bleu", label = "Bleu", border = { 0.4, 0.6, 0.9 }, bg = { 0.02, 0.02, 0.05 }, hl = { 1, 0.82, 0 } },
	{ key = "or", label = "Or", border = { 1, 0.82, 0 }, bg = { 0.06, 0.04, 0 }, hl = { 1, 0.82, 0 } },
	{ key = "horde", label = "Horde", border = { 0.8, 0.15, 0.1 }, bg = { 0.08, 0.01, 0.01 }, hl = { 1, 0.45, 0.2 } },
	{ key = "nature", label = "Nature", border = { 0.3, 0.8, 0.4 }, bg = { 0.01, 0.05, 0.02 }, hl = { 0.5, 1, 0.5 } },
	{ key = "sombre", label = "Sombre", border = { 0.25, 0.25, 0.25 }, bg = { 0, 0, 0 }, hl = { 0.8, 0.8, 0.8 } },
}

-- Tailles de texte : polices et hauteur de ligne (normale / compacte).
UI.FONTS = {
	{ key = "petit", label = "Petit", num = "GameFontNormalSmall", title = "GameFontHighlightSmall", sub = "GameFontDisableSmall", h = 26, hc = 16 },
	{ key = "normal", label = "Normal", num = "GameFontNormal", title = "GameFontHighlight", sub = "GameFontDisableSmall", h = 32, hc = 20 },
	{ key = "grand", label = "Grand", num = "GameFontNormalLarge", title = "GameFontHighlightLarge", sub = "GameFontDisable", h = 40, hc = 26 },
}

local function Find(list, key)
	for _, item in ipairs(list) do
		if item.key == key then
			return item
		end
	end
	return list[1]
end

local frame, rows, advice, adviceBtn, status, summary, more, grip, menu, catcher, titleText
local banner -- (bandeau « prochaine étape », créé plus bas)
local adviceLine
local buttons = {}

local function S()
	return ns.db.ui
end

-------------------------------------------------------------------------------
-- Habillage commun (fenêtre, bandeau, Équipement, réglages, assistant, rapport, menus) : cadres plats à fine bordure
-- aux couleurs du thème, liseré d'accent, barre de titre avec icône, boutons à icône, boutons et onglets plats, barres
-- de progression. Style « Blizzard » (cadres d'infobulle du jeu) au choix dans les réglages.
-- Seulement des textures présentes dans tous les clients (WHITE8X8, icônes de base du jeu).
-------------------------------------------------------------------------------
local Skin = {}
UI.Skin = Skin
local WHITE = "Interface\\Buttons\\WHITE8X8"
local FLAT = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } }
Skin.WHITE = WHITE
Skin.COLORS = {
	gold = { 1, 0.82, 0 }, green = { 0.35, 0.95, 0.45 }, grey = { 0.62, 0.62, 0.62 }, white = { 0.95, 0.95, 0.95 },
	red = { 1, 0.42, 0.36 }, blue = { 0.45, 0.75, 1 }, orange = { 1, 0.6, 0.2 },
}

function Skin.Theme()
	return Find(UI.THEMES, ns.db and ns.db.ui and ns.db.ui.theme)
end

function Skin.Classic()
	return ns.db and ns.db.ui and ns.db.ui.style == "blizzard" or false
end

-- Bordure de 1 px autour d'un cadre (icône d'objet, bouton…).
function Skin.Border(frame, r, g, b, a)
	if not rawget(frame, "skinBorder") then
		local t = {}
		for i = 1, 4 do
			local tex = frame:CreateTexture(nil, "OVERLAY")
			tex:SetTexture(WHITE)
			t[i] = tex
		end
		t[1]:SetPoint("TOPLEFT", -1, 1)
		t[1]:SetPoint("TOPRIGHT", 1, 1)
		t[1]:SetHeight(1)
		t[2]:SetPoint("BOTTOMLEFT", -1, -1)
		t[2]:SetPoint("BOTTOMRIGHT", 1, -1)
		t[2]:SetHeight(1)
		t[3]:SetPoint("TOPLEFT", -1, 1)
		t[3]:SetPoint("BOTTOMLEFT", -1, -1)
		t[3]:SetWidth(1)
		t[4]:SetPoint("TOPRIGHT", 1, 1)
		t[4]:SetPoint("BOTTOMRIGHT", 1, -1)
		t[4]:SetWidth(1)
		frame.skinBorder = t
	end
	for _, tex in ipairs(rawget(frame, "skinBorder")) do
		tex:SetVertexColor(r or 0, g or 0, b or 0, a or 1)
	end
end

-- Fond + bordure du thème (+ liseré d'accent en haut). `border` : couleur de bordure à la place du thème.
function Skin.Panel(frame, alpha, border)
	local theme = Skin.Theme()
	local classic = Skin.Classic()
	if frame.SetBackdrop then
		frame:SetBackdrop(classic and BACKDROP or FLAT)
		frame:SetBackdropColor(theme.bg[1], theme.bg[2], theme.bg[3], alpha or 0.92)
		local c = border or theme.border
		frame:SetBackdropBorderColor(c[1], c[2], c[3], classic and 1 or 0.9)
	end
	if not rawget(frame, "skinAccent") then
		frame.skinAccent = frame:CreateTexture(nil, "BORDER")
		frame.skinAccent:SetTexture(WHITE)
		frame.skinAccent:SetPoint("TOPLEFT", 1, -1)
		frame.skinAccent:SetPoint("TOPRIGHT", -1, -1)
		frame.skinAccent:SetHeight(2)
	end
	local a = border or theme.hl
	frame.skinAccent:SetVertexColor(a[1], a[2], a[3], 0.9)
	frame.skinAccent:SetShown(not classic)
end

-- Barre de titre : icône + titre, et un trait discret dessous. Rend la ligne de texte du titre.
function Skin.Header(frame, title, icon, height)
	height = height or 24
	local h = rawget(frame, "skinHeader")
	if not h then
		h = {}
		frame.skinHeader = h
		h.icon = frame:CreateTexture(nil, "ARTWORK")
		h.icon:SetSize(16, 16)
		h.icon:SetPoint("TOPLEFT", 8, -5)
		h.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		h.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		h.text:SetPoint("LEFT", h.icon, "RIGHT", 6, 0)
		h.text:SetJustifyH("LEFT")
		h.line = frame:CreateTexture(nil, "BORDER")
		h.line:SetTexture(WHITE)
		h.line:SetHeight(1)
		h.line:SetPoint("TOPLEFT", 6, -height)
		h.line:SetPoint("TOPRIGHT", -6, -height)
	end
	h.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_Map_01")
	h.text:SetText(title or "")
	Skin.HeaderColors(frame)
	return h.text
end

function Skin.HeaderColors(frame)
	local h = rawget(frame, "skinHeader")
	if h then
		local theme = Skin.Theme()
		h.text:SetTextColor(theme.hl[1], theme.hl[2], theme.hl[3])
		h.line:SetVertexColor(theme.border[1], theme.border[2], theme.border[3], 0.35)
	end
end

-- Trait de séparation horizontal (sous un intitulé de section…).
function Skin.Line(parent, alpha)
	local line = parent:CreateTexture(nil, "BORDER")
	line:SetTexture(WHITE)
	line:SetHeight(1)
	local theme = Skin.Theme()
	line:SetVertexColor(theme.border[1], theme.border[2], theme.border[3], alpha or 0.3)
	return line
end

local function TipScript(b, title, text)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		if title then
			GameTooltip:AddLine(title, 1, 0.82, 0)
		end
		if text then
			GameTooltip:AddLine(text, 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end
Skin.Tip = TipScript

-- Petit bouton à icône (barre de titre). `key` : son nom (tests, réglages). SetActive(true) : bordure verte (allumé).
function Skin.IconButton(parent, key, icon, title, tip, onClick, size, crop)
	local b = CreateFrame("Button", nil, parent)
	size = size or 18
	b:SetSize(size, size)
	b.skinKey = key
	b.tipText = tip
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexture(icon)
	if crop ~= false then
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetTexture(WHITE)
	hl:SetBlendMode("ADD")
	hl:SetVertexColor(1, 1, 1, 0.25)
	Skin.Border(b, 0, 0, 0, 0.9)
	b:SetScript("OnClick", onClick)
	TipScript(b, title, tip)
	function b:SetActive(on)
		self.active = on and true or false
		local c = on and Skin.COLORS.green
		if c then
			Skin.Border(self, c[1], c[2], c[3], 1)
		else
			Skin.Border(self, 0, 0, 0, 0.9)
		end
	end
	return b
end

-- Bouton plat (texte), ou onglet / choix avec SetSelected(true).
function Skin.StyleButton(b)
	local theme = Skin.Theme()
	if b.SetBackdrop then
		b:SetBackdrop(FLAT)
		if rawget(b, "selected") then
			b:SetBackdropColor(theme.hl[1] * 0.25, theme.hl[2] * 0.25, theme.hl[3] * 0.25, 0.95)
			b:SetBackdropBorderColor(theme.hl[1], theme.hl[2], theme.hl[3], 1)
		else
			b:SetBackdropColor(0.1, 0.1, 0.13, 0.95)
			b:SetBackdropBorderColor(theme.border[1], theme.border[2], theme.border[3], 0.55)
		end
	end
	if rawget(b, "label") then
		local c = rawget(b, "selected") and theme.hl or Skin.COLORS.white
		b.label:SetTextColor(c[1], c[2], c[3])
	end
end

function Skin.Button(parent, text, width, height, onClick)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(width or 100, height or 22)
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.label:SetPoint("LEFT", 4, 0)
	b.label:SetPoint("RIGHT", -4, 0)
	b:SetFontString(b.label)
	b:SetText(text or "")
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetPoint("TOPLEFT", 1, -1)
	hl:SetPoint("BOTTOMRIGHT", -1, 1)
	hl:SetTexture(WHITE)
	hl:SetBlendMode("ADD")
	hl:SetVertexColor(1, 1, 1, 0.1)
	if onClick then
		b:SetScript("OnClick", onClick)
	end
	function b:SetSelected(on)
		self.selected = on and true or false
		Skin.StyleButton(self)
	end
	b:SetScript("OnEnable", function(self)
		self.label:SetAlpha(1)
	end)
	b:SetScript("OnDisable", function(self)
		self.label:SetAlpha(0.45)
	end)
	Skin.StyleButton(b)
	return b
end

-- Barre de progression fine. bar:SetProgress(0..1 ou nil, couleur).
function Skin.Bar(parent, height)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetHeight(height or 3)
	bar:SetStatusBarTexture(WHITE)
	bar:SetMinMaxValues(0, 1)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetTexture(WHITE)
	bar.bg:SetVertexColor(1, 1, 1, 0.08)
	function bar:SetProgress(frac, color)
		if not frac then
			self:Hide()
			return
		end
		local c = color or (frac >= 1 and Skin.COLORS.green or Skin.Theme().hl)
		self:SetStatusBarColor(c[1], c[2], c[3], 0.9)
		self:SetValue(math.max(0, math.min(1, frac)))
		self:Show()
	end
	bar:Hide()
	return bar
end

-- Avancement d'une étape (objectifs « 3/8 ») : 0..1, ou nil si l'étape n'a rien à compter.
function UI.StopProgress(s)
	if not s or s.kind == "turnin" or s.kind == "pickup" or s.kind == "service" then
		return nil
	end
	local have, need = 0, 0
	for _, t in ipairs(s.tasks or {}) do
		local o = t.objective
		local n = o and tonumber(o.numRequired)
		if n and n > 0 then
			need = need + n
			have = have + math.min(n, tonumber(o.numFulfilled) or 0)
		end
	end
	if need == 0 then
		return nil
	end
	return have / need
end

local function Duration(seconds)
	seconds = seconds or 0
	if seconds < 50 then
		return "< 1 min"
	end
	local minutes = math.floor(seconds / 60 + 0.5)
	if minutes >= 60 then
		return string.format("~%d h %02d", math.floor(minutes / 60), minutes % 60)
	end
	return "~" .. minutes .. " min"
end

-- Heure (horloge réelle) à laquelle on atteint `seconds` après le calcul du trajet.
local function Clock(plan, seconds)
	if not (plan and plan.at and date) then
		return nil
	end
	return date("%H:%M", plan.at + math.floor(seconds or 0))
end

local function Thousands(n)
	local s = tostring(math.floor(n or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (out:gsub("^%s+", ""))
end

-- Fourchette (« 12–15 min ») ; une seule valeur quand l'écart est faible.
local function Minutes(seconds)
	return math.floor((seconds or 0) / 60 + 0.5)
end

local function HM(m)
	if m >= 60 then
		return string.format("%d h %02d", math.floor(m / 60), m % 60)
	end
	return m .. " min"
end

local function DurationRange(lo, hi)
	local a, b = Minutes(lo), Minutes(hi)
	if b - a < 2 or hi < 50 then
		return Duration(((lo or 0) + (hi or 0)) / 2)
	end
	if b < 60 then
		return a .. "–" .. b .. " min"
	end
	return HM(a) .. "–" .. HM(b)
end

-- Incertitude d'une étape (écarts-types, secondes) : ton écart habituel, mesuré, en route et sur place.
-- Une étape de 8 monstres varie moins, en proportion, qu'un seul monstre ; il reste un fond de 15 %
-- (autres joueurs, réapparitions) qu'aucune mesure n'efface.
local function Units(s)
	local n = 0
	for _, t in ipairs(s.tasks or {}) do
		local o = t.objective
		if o and (o.numRequired or 0) > 0 then
			n = n + math.max(1, o.numRequired - (o.numFulfilled or 0))
		end
	end
	return math.max(1, n)
end

local function Spread()
	local ok, spread = pcall(ns.Spread)
	return ok and type(spread) == "table" and spread or { work = 0.35, travel = 0.25 }
end

function UI.StopSpread(s, spread)
	spread = spread or Spread()
	local rw = math.sqrt(spread.work ^ 2 / Units(s) + 0.15 ^ 2)
	local rt = s.legExact and 0.1 or spread.travel
	return (s.leg or 0) * rt, (s.work or 0) * rw
end

-- Fourchette du trajet complet : les écarts d'étape en étape se compensent en partie, mais pas
-- l'erreur d'ensemble (tout plus lent ou plus rapide que prévu), grande tant que ton rythme n'est pas mesuré.
function UI.PlanRange(plan)
	local spread = Spread()
	local var = 0
	for _, s in ipairs(plan.order or {}) do
		local a, b = UI.StopSpread(s, spread)
		var = var + a * a + b * b
	end
	local total = (plan.travel or 0) + (plan.workTime or 0)
	local system = (spread.system or 0.2) * total
	local sigma = math.sqrt(var + system * system)
	return math.max(total * 0.5, total - sigma), total + sigma, total
end

-- « à pied (1 min) · vol vers Orgrimmar (3 min) · à pied (2 min) »
local MODES = {
	walk = "à pied", flight = "vol", boat = "bateau", zeppelin = "zeppelin", lift = "ascenseur", tram = "tram",
	portal = "portail", passage = "passage", teleport = "téléportation",
}
local function Safe(text)
	return (tostring(text or ""):gsub("|", "/"))
end

function UI.RouteText(route)
	if type(route) ~= "table" or #route == 0 then
		return nil
	end
	local parts = {}
	for _, leg in ipairs(route) do
		local mode = MODES[leg.mode] or Safe(leg.mode)
		local to = leg.mode ~= "walk" and leg.to and (" vers " .. Safe(leg.to)) or ""
		parts[#parts + 1] = mode .. to .. " (" .. Duration(leg.seconds):gsub("^~", "") .. ")"
	end
	return table.concat(parts, " · ")
end

local function StopIcon(s)
	if s.kind == "service" then
		return (s.service and s.service.kind == "trainer") and ICONS.trainer or ICONS.service
	end
	if s.kind == "area" then
		local t = s.tasks[1] and s.tasks[1].objective and s.tasks[1].objective.type
		return ICONS[t or ""] or ICONS.area
	end
	return ICONS[s.kind] or ICONS.area
end

local function PickupText(s)
	if s.kind == "pickup" or #s.pickups == 0 then
		return ""
	end
	if #s.pickups == 1 then
		return " |cff00ff00+ prendre « " .. (s.pickups[1].name or "?") .. " »|r"
	end
	return " |cff00ff00+ prendre " .. #s.pickups .. " quêtes|r"
end

-------------------------------------------------------------------------------
-- Petit menu contextuel maison (indépendant des API de menus du client)
-------------------------------------------------------------------------------
local function HideMenu()
	if menu then
		menu:Hide()
	end
	if catcher then
		catcher:Hide()
	end
end

function UI.ShowMenu(items)
	if not menu then
		menu = CreateFrame("Frame", "ItineraireMenu", UIParent, "BackdropTemplate")
		menu:SetFrameStrata("FULLSCREEN_DIALOG")
		menu:SetClampedToScreen(true)
		menu.buttons = {}
		tinsert(UISpecialFrames, "ItineraireMenu")
		catcher = CreateFrame("Button", nil, UIParent)
		catcher:SetAllPoints(UIParent)
		catcher:SetFrameStrata("FULLSCREEN")
		catcher:RegisterForClicks("AnyUp")
		catcher:SetScript("OnClick", HideMenu)
		menu:SetScript("OnHide", function()
			catcher:Hide()
		end)
	end
	local width = 120
	for i, item in ipairs(items) do
		local b = menu.buttons[i]
		if not b then
			b = CreateFrame("Button", nil, menu)
			b:SetHeight(18)
			b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			b.text:SetPoint("LEFT", 8, 0)
			b.text:SetJustifyH("LEFT")
			local hl = b:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints()
			hl:SetTexture(WHITE)
			hl:SetBlendMode("ADD")
			hl:SetVertexColor(1, 1, 1, 0.1)
			b:RegisterForClicks("AnyUp")
			menu.buttons[i] = b
		end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 4, -6 - (i - 1) * 18)
		b:SetPoint("RIGHT", -4, 0)
		local label = item.text
		if item.checked ~= nil then
			label = (item.checked and "|cff00ff00[x]|r " or "[  ] ") .. label
		end
		if item.title then
			label = "|cffffd200" .. label .. "|r"
		end
		b.text:SetText(label)
		width = math.max(width, b.text:GetStringWidth() + 24)
		b:SetScript("OnClick", function()
			HideMenu()
			if item.func then
				item.func()
			end
		end)
		b:SetEnabled(not item.title)
		b:Show()
	end
	for i = #items + 1, #menu.buttons do
		menu.buttons[i]:Hide()
	end
	menu:SetSize(width, #items * 18 + 12)
	Skin.Panel(menu, 0.96)
	local scale = UIParent:GetEffectiveScale()
	local x, y = GetCursorPosition()
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
	catcher:Show()
	menu:Show()
end

-------------------------------------------------------------------------------
-- Menus
-------------------------------------------------------------------------------
local function GuideNotice()
	local guide = ns.plan and ns.plan.group and ns.plan.group.guide
	if guide then
		UI.ShowMenu({
			{ text = "Trajet du groupe", title = true },
			{ text = "C'est " .. guide .. " (le guide) qui choisit l'ordre des étapes.", title = true },
			{ text = "Désactiver le partage de groupe", func = function()
				ns.Group.SetEnabled(false)
			end },
			{ text = "Fermer" },
		})
		return true
	end
end

local function RowMenu(row)
	local s = row.stop
	if not s or GuideNotice() then
		return
	end
	local items = { { text = s.number .. ". " .. s.title, title = true } }
	items[#items + 1] = {
		text = ns.session.pinned == s.key and "Ne plus la forcer en premier" or "Faire cette étape d'abord",
		func = function()
			ns.session.pinned = ns.session.pinned ~= s.key and s.key or nil
			ns.SetPaused(false)
			ns.RequestPlan("pin", 0)
		end,
	}
	for _, q in ipairs(s.quests) do
		if ns.session.focus ~= q.id then
			items[#items + 1] = {
				text = "Suivre « " .. q.title .. " » (toute la quête en premier)",
				func = function()
					ns.SetFocus(q.id, "ui")
				end,
			}
		end
	end
	items[#items + 1] = {
		text = "Passer cette étape pour l'instant",
		func = function()
			ns.SkipStop(s.key)
		end,
	}
	items[#items + 1] = { text = "Fermer" }
	UI.ShowMenu(items)
end

local STATUS_COLOR = {
	["à rendre"] = "ff00ff00", ["sur le trajet"] = "ffffffff", ["JcJ"] = "ffff9933",
}

-- Bouton « P » allumé tant que le pilote automatique est actif.
function UI.SetPilote(on)
	local b = buttons and buttons.pilote
	if b and b.SetActive then
		b:SetActive(on)
	end
	if banner and rawget(banner, "pilot") then
		banner.pilot:SetShown(on and true or false)
		UI.UpdateBannerTime()
	end
end

-- Bouton « ? » allumé tant que la route des rendus est active.
function UI.SetTurnins(on)
	local b = buttons and buttons.turnins
	if b and b.SetActive then
		b:SetActive(on)
	end
end

function UI.QuestMenu()
	if GuideNotice() then
		return
	end
	local plan = ns.plan
	local items = { { text = "Quelle quête suivre ? Toute la quête passe avant le reste.", title = true } }
	if ns.session.focus then
		items[#items + 1] = {
			text = "Arrêter de suivre « " .. (ns.session.focusTitle or ns.session.focus) .. " »",
			func = function()
				ns.SetFocus(nil, "ui")
			end,
		}
	end
	local quests = {}
	for _, q in ipairs(plan and plan.quests or {}) do
		quests[#quests + 1] = q
	end
	table.sort(quests, function(a, b)
		local ra, rb = a.status == "à rendre" and 0 or 1, b.status == "à rendre" and 0 or 1
		if ra ~= rb then
			return ra < rb
		end
		return (a.level or 0) < (b.level or 0)
	end)
	for _, q in ipairs(quests) do
		local st = q.status or ""
		local color = STATUS_COLOR[st] or (st:find("^à la fin") and "ffff7777") or "ff888888"
		items[#items + 1] = {
			text = string.format("[%d] %s  |c%s%s|r", q.level or 0, q.title, color, st),
			checked = ns.session.focus == q.id,
			func = function()
				if ns.session.focus == q.id then
					ns.SetFocus(nil, "ui")
				else
					ns.SetFocus(q.id, "ui")
				end
			end,
		}
	end
	if #quests == 0 then
		items[#items + 1] = { text = "Journal vide." }
	end
	items[#items + 1] = { text = "Fermer" }
	UI.ShowMenu(items)
end

local function OptionsMenu()
	UI.ShowMenu({
		{ text = "Itinéraire", title = true },
		{
			text = "Réglages (tout-en-un : trajet, Questie, flèche)…",
			func = function()
				ns.Options.Toggle(true, "trajet")
			end,
		},
		{
			text = "Pilote automatique (quêtes, vols, marchand, maître…)",
			checked = not ns.piloteMissing and ns.Pilote.Config().on == true,
			func = function()
				if not ns.piloteMissing then
					ns.Pilote.SetOn(not ns.Pilote.Config().on)
				end
			end,
		},
		{
			text = "Équipement : tes améliorations (récompenses, vendeurs, butins, métiers)…",
			func = function()
				ns.GearUI.Toggle(true, "items")
			end,
		},
		{
			text = "Quel donjon faire pour mon équipement ?",
			func = function()
				ns.GearUI.Toggle(true, "dungeons")
			end,
		},
		{
			text = "Route des rendus (seulement les quêtes terminées)",
			checked = ns.session.turnins == true,
			func = function()
				ns.ToggleTurnins()
			end,
		},
		{
			text = "Finir la région avant d'en sortir (avec toutes ses quêtes)",
			checked = ns.db.regionMode ~= false,
			func = function()
				ns.db.regionMode = ns.db.regionMode == false
				ns.RequestPlan("option", 0)
			end,
		},
		{
			text = "Proposer les quêtes à prendre (région et trajet)",
			checked = ns.db.includePickups,
			func = function()
				ns.db.includePickups = not ns.db.includePickups
				ns.RequestPlan("option", 0)
			end,
		},
		{
			text = "Inclure les donjons",
			checked = ns.db.includeDungeons,
			func = function()
				ns.db.includeDungeons = not ns.db.includeDungeons
				ns.RequestPlan("option", 0)
			end,
		},
		{
			text = "Partage de groupe (2 à 5 joueurs)",
			checked = ns.db.groupShare == true,
			func = function()
				ns.Group.SetEnabled(not ns.db.groupShare)
				UI.SetStatus(ns.StatusText())
			end,
		},
		{
			text = "Bandeau « prochaine étape » près de la flèche",
			checked = S().banner ~= false,
			func = function()
				S().banner = S().banner == false
				UI.RefreshBanner(ns.plan)
			end,
		},
		{
			text = "Rapport à copier (en cas de souci)…",
			func = function()
				ns.ShowReport()
			end,
		},
		{
			text = "Assistant de départ…",
			func = function()
				ns.Options.ShowWizard()
			end,
		},
		{
			text = "Personnaliser la fenêtre…",
			func = function()
				ns.Options.Toggle(true, "fenetre")
			end,
		},
		{
			text = S().locked and "Déverrouiller la fenêtre et le bandeau" or "Verrouiller la fenêtre et le bandeau",
			func = function()
				S().locked = not S().locked
				UI.ApplySettings()
			end,
		},
		{
			text = "Réafficher les étapes passées",
			func = function()
				ns.ResetChoices()
			end,
		},
		{
			text = "Masquer la fenêtre (/iti pour la rouvrir)",
			func = function()
				UI.Toggle(false)
			end,
		},
		{ text = "Fermer" },
	})
end

-------------------------------------------------------------------------------
-- Lignes
-------------------------------------------------------------------------------
local function SavePosition()
	local point, _, rel, x, y = frame:GetPoint()
	S().point, S().rel, S().x, S().y = point, rel, x, y
end

local function RowTooltip(row)
	local s = row.stop
	if not s then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(s.number .. ". " .. s.title, 1, 0.82, 0, true)
	if s.subtitle and s.subtitle ~= "" then
		GameTooltip:AddLine(s.subtitle, 0.8, 0.8, 0.8, true)
	end
	for _, line in ipairs(s.details or {}) do
		GameTooltip:AddLine("• " .. line, 1, 1, 1, true)
	end
	if s.lateWhy then
		GameTooltip:AddLine("À la fin du trajet : " .. s.lateWhy .. " (trop dur pour ton niveau, pour l'instant).", 1, 0.45, 0.45, true)
	end
	if s.gateLevel then
		GameTooltip:AddLine("Avancée : tu auras le niveau " .. s.gateLevel .. " en arrivant ici (estimation).", 1, 0.82, 0, true)
	end
	if s.tour then
		GameTooltip:AddLine(string.format("Tournée des rendus : %d quêtes, étapes %d à %d.", s.tour.quests, s.tour.first, s.tour.last), 0.4, 1, 0.4, true)
	end
	GameTooltip:AddLine(" ")
	local dl, dw = UI.StopSpread(s)
	local leg, work = s.leg or 0, s.work or 0
	GameTooltip:AddLine(string.format("Trajet %s%s · sur place %s", DurationRange(leg - dl, leg + dl),
		s.legExact and " (temps exact de la flèche)" or "", DurationRange(work - dw, work + dw)), 0.6, 0.8, 1)
	local route = UI.RouteText(s.route)
	if route then
		GameTooltip:AddLine("Chemin : " .. route, 0.6, 0.8, 1, true)
	elseif s.legSP and math.abs(s.legSP - leg) >= 60 then
		GameTooltip:AddLine("Shortest Path estime ce trajet à " .. Duration(s.legSP) .. ".", 0.6, 0.8, 1, true)
	end
	local arrive, leave = Clock(ns.plan, (s.eta or 0) - (s.work or 0)), Clock(ns.plan, s.eta)
	if arrive then
		GameTooltip:AddLine("Arrivée vers " .. arrive .. ", fini vers " .. leave .. ".", 0.6, 0.8, 1)
	end
	local pace = ns.PaceText and ns.PaceText()
	GameTooltip:AddLine(pace and ("Temps calculés avec ton rythme : " .. pace .. ".")
		or "Temps par défaut : ils s'ajusteront à ton rythme en jouant.", 0.5, 0.5, 0.5, true)
	GameTooltip:AddLine("Clic gauche : faire cette étape d'abord", 0.5, 0.5, 0.5)
	GameTooltip:AddLine("Clic droit : suivre une quête, passer l'étape", 0.5, 0.5, 0.5)
	GameTooltip:Show()
end

-- Applique la police, la hauteur et les colonnes visibles à une ligne.
local function StyleRow(row)
	local s = S()
	local f = Find(UI.FONTS, s.font)
	row.num:SetFontObject(f.num)
	row.title:SetFontObject(f.title)
	row.sub:SetFontObject(f.sub)
	row.time:SetFontObject(s.font == "grand" and "GameFontHighlight" or "GameFontHighlightSmall")
	row:SetHeight(s.compact and f.hc or f.h)
	local iconSize = s.compact and math.max(12, f.hc - 4) or 18
	row.icon:SetSize(iconSize, iconSize)
	row.icon:SetShown(s.icons)
	local left = s.icons and (28 + iconSize + 6) or 30
	local right = s.times and -52 or -6
	row.title:ClearAllPoints()
	if s.compact then
		row.title:SetPoint("LEFT", left, 0)
	else
		row.title:SetPoint("TOPLEFT", left, -3)
	end
	row.title:SetPoint("RIGHT", right, 0)
	row.sub:ClearAllPoints()
	row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -1)
	row.sub:SetPoint("RIGHT", right, 0)
	row.sub:SetShown(not s.compact)
	row.time:SetShown(s.times)
	local theme = Find(UI.THEMES, s.theme)
	row.bg:SetColorTexture(theme.hl[1], theme.hl[2], theme.hl[3], 0.12)
	row.accent:SetColorTexture(theme.hl[1], theme.hl[2], theme.hl[3], 0.95)
	-- barre d'avancement des objectifs, sous le texte de l'étape
	row.bar:ClearAllPoints()
	row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", left, 1)
	row.bar:SetPoint("RIGHT", row, "RIGHT", right, 0)
	row.compact = s.compact
end

local function MakeRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:Hide()
	-- étape en cours : liseré à gauche, aux couleurs du thème
	row.accent = row:CreateTexture(nil, "BORDER")
	row.accent:SetPoint("TOPLEFT", 0, -2)
	row.accent:SetPoint("BOTTOMLEFT", 0, 2)
	row.accent:SetWidth(3)
	row.accent:Hide()
	-- une ligne sur deux très légèrement teintée (lecture plus facile)
	row.stripe = row:CreateTexture(nil, "BACKGROUND", nil, -1)
	row.stripe:SetAllPoints()
	row.stripe:SetColorTexture(1, 1, 1, 0.025)
	row.stripe:Hide()
	row.bar = Skin.Bar(row, 2)
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetTexture(WHITE)
	hl:SetBlendMode("ADD")
	hl:SetVertexColor(1, 1, 1, 0.07)
	row.num = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.num:SetPoint("LEFT", 0, 0)
	row.num:SetWidth(26)
	row.num:SetJustifyH("RIGHT")
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetPoint("LEFT", 30, 0)
	row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.title:SetJustifyH("LEFT")
	row.title:SetWordWrap(false)
	row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.sub:SetJustifyH("LEFT")
	row.sub:SetWordWrap(false)
	row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.time:SetPoint("RIGHT", -4, 0)
	row.time:SetJustifyH("RIGHT")
	row:SetScript("OnEnter", RowTooltip)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self, button)
		if not self.stop then
			return
		end
		if button == "RightButton" then
			RowMenu(self)
		elseif GuideNotice() then
			return
		else
			if ns.session.pinned == self.stop.key then
				ns.session.pinned = nil
			else
				ns.session.pinned = self.stop.key
			end
			ns.SetPaused(false)
			ns.RequestPlan("pin", 0)
		end
	end)
	StyleRow(row)
	return row
end

local function Row(i)
	if not rows[i] then
		rows[i] = MakeRow(frame)
	end
	return rows[i]
end

-------------------------------------------------------------------------------
-- Fenêtre
-------------------------------------------------------------------------------
-- Boutons de la barre de titre : icônes du jeu (lisibles d'un coup d'œil), bulle avec le titre et l'explication.
local HEADER_BUTTONS = {
	{ key = "options", icon = "Interface\\Icons\\INV_Misc_Gear_01", title = "Options",
		tip = "Réglages, route des rendus, équipement, pilote, rapport…" },
	{ key = "recalc", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", title = "Recalculer",
		tip = "Recalculer le trajet (et reprendre le guidage s'il était en pause)." },
	{ key = "quest", icon = "Interface\\GossipFrame\\AvailableQuestIcon", crop = false, title = "Quête à suivre",
		tip = "Choisir LA quête à faire en premier (le bouton « focus » du suivi de Questie marche aussi)." },
	{ key = "turnins", icon = "Interface\\GossipFrame\\ActiveQuestIcon", crop = false, title = "Route des rendus",
		tip = "Un trajet qui ne fait que rendre tes quêtes terminées. Re-clic : retour au trajet complet." },
	{ key = "gear", icon = "Interface\\Icons\\INV_Shield_04", title = "Équipement",
		tip = "Tes améliorations (récompenses, vendeurs, butins de donjon, métiers), « Quel donjon faire ? » et « Y aller »." },
	{ key = "journal", icon = "Interface\\Icons\\INV_Misc_Book_09", title = "Journal des donjons", rightClick = true,
		tip = "Ouvre DungeonJournal (d'ExehnTV) sur le donjon où tu es, sinon sur le prochain donjon de ton trajet. Clic droit : choisir un donjon de ton niveau." },
	{ key = "pilote", icon = "Interface\\Icons\\Ability_Hunter_Pathfinding", title = "Pilote automatique",
		tip = "Bordure verte = actif : il prend et rend les quêtes, prend le vol prévu, passe les cinématiques, répare et vend les objets gris, apprend tes techniques. MAJ en parlant à un PNJ : tu reprends la main. Clic : marche / arrêt." },
}

local function SmallButton(def, onClick)
	return Skin.IconButton(frame, def.key, def.icon, def.title, def.tip, onClick, 18, def.crop)
end

function UI.Create()
	if frame then
		return
	end
	local s = S()
	frame = CreateFrame("Frame", "ItineraireFrame", UIParent, "BackdropTemplate")
	frame:SetSize(s.width or 360, 120)
	frame:SetBackdrop(BACKDROP)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	if frame.SetResizeBounds then
		frame:SetResizeBounds(260, 60, 700, 4000)
	elseif frame.SetMinResize then
		frame:SetMinResize(260, 60)
		frame:SetMaxResize(700, 4000)
	end
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if not S().locked then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	frame:SetPoint(s.point or "LEFT", UIParent, s.rel or "LEFT", s.x or 20, s.y or 120)

	titleText = Skin.Header(frame, "Itinéraire", "Interface\\Icons\\INV_Misc_Map_01")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetSize(20, 20)
	close:SetPoint("TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function()
		UI.Toggle(false)
	end)
	local actions = {
		options = OptionsMenu,
		recalc = function()
			ns.SetPaused(false)
			ns.Guide.Reset()
			ns.RequestPlan("button", 0)
		end,
		quest = UI.QuestMenu,
		turnins = function()
			ns.ToggleTurnins()
		end,
		gear = function()
			ns.GearUI.Toggle()
		end,
		journal = function(_, mouse)
			if ns.djMissing then
				ns.Print("DungeonJournal arrive avec un nouveau fichier d'Itinéraire : quitte et relance complètement WoW.")
				return
			end
			ns.DJ.Button(mouse == "RightButton")
		end,
		pilote = function()
			if ns.piloteMissing then
				ns.Print("le pilote arrive avec un nouveau fichier : quitte et relance complètement WoW.")
				return
			end
			ns.Pilote.SetOn(not ns.Pilote.Config().on)
		end,
	}
	local prev = close
	for _, def in ipairs(HEADER_BUTTONS) do
		local b = SmallButton(def, actions[def.key])
		if def.rightClick then
			b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		end
		b:SetPoint("RIGHT", prev, "LEFT", prev == close and -2 or -4, 0)
		buttons[def.key] = b
		prev = b
	end

	summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	summary:SetPoint("TOPLEFT", 10, -30)
	summary:SetPoint("RIGHT", -10, 0)
	summary:SetJustifyH("LEFT")

	status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	status:SetPoint("RIGHT", -10, 0)
	status:SetJustifyH("LEFT")
	status:SetTextColor(1, 0.5, 0.3)

	rows = {}

	more = Skin.Button(frame, "", 220, 18)
	more:SetScript("OnClick", function()
		ns.session.expanded = not ns.session.expanded
		ns.session.scroll = 0
		if ns.plan then
			UI.Refresh(ns.plan)
		end
	end)
	more:Hide()

	-- La molette fait défiler les étapes : 1, 2, 3… jusqu'à la dernière.
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		local plan = ns.plan
		if not plan then
			return
		end
		local maxOffset = math.max(0, #plan.order - UI.PageSize())
		ns.session.scroll = math.max(0, math.min(maxOffset, (ns.session.scroll or 0) - delta * 3))
		UI.Refresh(plan)
	end)

	advice = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	advice:SetJustifyH("LEFT")
	advice:SetSpacing(2)
	adviceLine = Skin.Line(frame, 0.3)
	adviceLine:Hide()
	-- Le bloc « À savoir » se replie en une ligne (clic).
	adviceBtn = CreateFrame("Button", nil, frame)
	adviceBtn:SetAllPoints(advice)
	adviceBtn:RegisterForClicks("LeftButtonUp")
	adviceBtn:SetScript("OnClick", function()
		S().adviceCollapsed = not S().adviceCollapsed
		if ns.plan then
			UI.Refresh(ns.plan)
		end
	end)

	-- Poignée en bas à droite : élargir / rétrécir la fenêtre.
	grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -3, 3)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function()
		if not S().locked then
			frame:StartSizing("RIGHT")
		end
	end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		S().width = math.floor(frame:GetWidth() + 0.5)
		SavePosition()
		UI.Layout()
	end)
	frame:SetScript("OnSizeChanged", function()
		if advice then
			advice:SetWidth(frame:GetWidth() - 20)
		end
	end)

	-- Fondu quand la souris n'est pas sur la fenêtre (option).
	local fadeTimer = 0
	frame:SetScript("OnUpdate", function(self, elapsed)
		fadeTimer = fadeTimer + elapsed
		if fadeTimer < 0.2 then
			return
		end
		fadeTimer = 0
		local st = S()
		local target = 1
		if st.fade and not (MouseIsOver(self) or (menu and menu:IsShown())) then
			target = st.fadeAlpha or 0.4
		end
		if math.abs(self:GetAlpha() - target) > 0.01 then
			self:SetAlpha(target)
		end
	end)

	UI.CreateBanner()
	UI.ApplySettings()
	UI.SetStatus("En attente de Questie…")
	UI.UpdateVisibility()
end

function UI.PageSize()
	local n = S().rows or 8
	if ns.session.expanded then
		n = n * 2
	end
	return math.max(1, math.min(30, n))
end

-- Applique tous les réglages de la fenêtre (appelé par les options).
function UI.ApplySettings()
	if not frame then
		return
	end
	local s = S()
	frame:SetScale(s.scale or 1)
	frame:SetWidth(s.width or 360)
	Skin.Panel(frame, s.alpha or 0.82)
	Skin.HeaderColors(frame)
	Skin.StyleButton(more)
	if adviceLine then
		local theme = Skin.Theme()
		adviceLine:SetVertexColor(theme.border[1], theme.border[2], theme.border[3], 0.3)
	end
	advice:SetWidth((s.width or 360) - 20)
	grip:SetShown(not s.locked)
	summary:SetShown(s.summary ~= false)
	for _, row in ipairs(rows) do
		StyleRow(row)
	end
	UI.StyleBanner()
	UI.RefreshBanner(ns.plan)
	if ns.plan then
		UI.Refresh(ns.plan)
	else
		UI.Layout()
	end
end

function UI.UpdateVisibility()
	if not frame then
		return
	end
	local s = S()
	local show = s.shown ~= false
	if show and s.hideCombat and InCombatLockdown() then
		show = false
	end
	if show and s.hideInstance then
		local inInstance = IsInInstance()
		if inInstance then
			show = false
		end
	end
	frame:SetShown(show)
	UI.UpdateBannerVisibility()
end

function UI.SetStatus(text)
	if status then
		status:SetText(text or "")
	end
	UI.Layout()
end

local shownRows = 0
function UI.Layout(count)
	if not frame then
		return
	end
	local s = S()
	shownRows = count or shownRows
	local y = -30
	if s.summary ~= false then
		y = y - (summary:GetStringHeight() or 10) - 2
	end
	local statusText = status:GetText()
	status:ClearAllPoints()
	status:SetPoint("TOPLEFT", 10, y - 1)
	status:SetPoint("RIGHT", -10, 0)
	if statusText and statusText ~= "" then
		y = y - status:GetStringHeight() - 4
	end
	y = y - 4
	for i = 1, math.max(shownRows, #rows) do
		local row = rows[i]
		if i <= shownRows then
			row = Row(i)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 6, y)
			row:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
			row:Show()
			y = y - row:GetHeight()
		elseif row then
			row:Hide()
		end
	end
	if more:IsShown() then
		more:ClearAllPoints()
		more:SetPoint("TOP", frame, "TOP", 0, y - 4)
		y = y - 26
	end
	local text = advice:GetText()
	if s.advice ~= false and text and text ~= "" then
		-- un trait discret sépare les étapes du bloc « À savoir »
		adviceLine:ClearAllPoints()
		adviceLine:SetPoint("TOPLEFT", 8, y - 4)
		adviceLine:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
		adviceLine:Show()
		advice:ClearAllPoints()
		advice:SetPoint("TOPLEFT", 10, y - 9)
		advice:Show()
		adviceBtn:Show()
		y = y - 13 - advice:GetStringHeight()
	else
		advice:Hide()
		adviceBtn:Hide()
		adviceLine:Hide()
	end
	frame:SetHeight(-y + 14)
end

local function Quoted(q)
	return "« " .. q.title .. " »"
end

local function AdviceText(plan)
	local lines = {}
	local side = plan.side
	if (plan.laterCount or 0) > 0 then
		lines[#lines + 1] = "|cffff7777" .. plan.laterCount .. " étape(s) en fin de trajet|r : quêtes trop dures ou zones trop hautes pour ton niveau, gardées pour plus tard."
	end
	if (plan.awayCount or 0) > 0 then
		lines[#lines + 1] = string.format("|cff999999Région %s d'abord|r : %d étape(s) ailleurs (%s) passent après.",
			plan.regionName or "actuelle", plan.awayCount, table.concat(plan.awayZones or {}, ", "))
	end
	if plan.candidates and #plan.candidates > 0 then
		local xp, time = 0, 0
		for _, q in ipairs(plan.candidates) do
			xp, time = xp + (q.xp or 0), time + (q.extraTime or 0)
		end
		lines[#lines + 1] = string.format("|cff66ccff%d quête(s) proposée(s)|r sur ton trajet (~%s XP pour ~%d min) : étapes « Prendre ». Pas envie ? Clic droit > Passer l'étape.",
			#plan.candidates, Thousands(xp), math.floor(time / 60 + 0.5))
	end
	for _, errand in ipairs(plan.errands or {}) do
		lines[#lines + 1] = "|cffffd100" .. errand.label .. "|r : " .. (errand.why[1] or "")
	end
	if plan.hearth then
		lines[#lines + 1] = string.format("|cffffd100Pierre de foyer|r à l'étape %d (%s) : ~%d min gagnées.",
			plan.hearth.step, plan.hearth.name or "ton auberge", math.floor(plan.hearth.gain / 60 + 0.5))
	end
	if plan.bindAdvice then
		lines[#lines + 1] = string.format("|cffffd100Auberge|r : lie ta pierre de foyer chez %s (%s), ~%d min de mieux sur ce trajet.",
			plan.bindAdvice.name or "l'aubergiste", plan.bindAdvice.zone or "?", math.floor(plan.bindAdvice.gain / 60 + 0.5))
	end
	if (plan.promotedCount or 0) > 0 then
		lines[#lines + 1] = "|cffffd100" .. plan.promotedCount .. " étape(s) avancée(s)|r : trop dures maintenant, mais tu auras le niveau en route."
	end
	for _, d in pairs(side.dungeons) do
		local names = {}
		for _, q in ipairs(d.quests) do
			names[#names + 1] = Quoted(q)
		end
		lines[#lines + 1] = "|cff66ccffDonjon " .. d.name .. "|r : " .. table.concat(names, ", ")
			.. " |cff888888(menu … puis « Inclure les donjons »)|r"
	end
	for _, q in ipairs(side.pvp) do
		lines[#lines + 1] = "|cffff9933JcJ|r " .. Quoted(q) .. " : se fait en champ de bataille"
	end
	for _, q in ipairs(side.failed) do
		lines[#lines + 1] = "|cffff5555Échouée|r " .. Quoted(q) .. " : abandonne-la puis reprends-la"
	end
	for _, u in ipairs(side.unknown) do
		lines[#lines + 1] = "|cff888888Position inconnue|r " .. Quoted(u.q) .. " (" .. u.what .. ") : suis les indications de Questie"
	end
	if #lines == 0 then
		return "", 0
	end
	if S().adviceCollapsed then
		return string.format("|cffffd200À savoir|r (%d) |cff888888— clic pour voir|r", #lines), #lines
	end
	return "|cffffd200À savoir|r |cff888888(clic pour replier)|r\n" .. table.concat(lines, "\n"), #lines
end

function UI.Refresh(plan)
	if not frame then
		return
	end
	local order = plan.order or {}
	if #order == 0 then
		summary:SetText(plan.turninOnly and "Aucune quête terminée à rendre."
			or plan.logCount and plan.logCount > 0 and "Rien à faire sur le trajet pour l'instant."
			or "Journal vide : prends des quêtes (les « ! » de Questie).")
	else
		local lo, hi = UI.PlanRange(plan)
		local first, last = Clock(plan, lo), Clock(plan, hi)
		local finish = first and (first == last and first or (first .. "–" .. last))
		local text = string.format("%d étape%s · %s", #order, #order > 1 and "s" or "", DurationRange(lo, hi))
			.. (finish and (" (fin vers " .. finish .. ")") or "")
		if plan.turninOnly then
			text = "|cffffd100Rendus seulement|r · " .. text
		end
		if plan.group then
			text = "|cff66ccffGroupe (guide : " .. plan.group.guide .. ")|r · " .. text
		elseif plan.groupMode then
			text = "|cff66ccffGroupe (tu guides)|r · " .. text
		end
		if plan.xp and plan.xp > 0 then
			text = text .. " · ~" .. Thousands(plan.xp) .. " XP"
		end
		if plan.levelEnd and plan.level and plan.levelEnd >= plan.level + 0.05 then
			text = text .. " · niv " .. string.format("%.1f", plan.levelEnd):gsub("%.", ",") .. " à la fin"
		end
		summary:SetText(text)
	end
	local page = UI.PageSize()
	local offset = math.max(0, math.min(ns.session.scroll or 0, #order - page))
	ns.session.scroll = offset
	local visible = math.max(0, math.min(page, #order - offset))
	for i = 1, visible do
		local row, s = Row(i), order[offset + i]
		row.stop = s
		row.num:SetText(s.number .. ".")
		row.icon:SetTexture(StopIcon(s))
		local title = s.title .. PickupText(s)
		if s.focus then
			title = "|cff66ccff»|r " .. title
		end
		if ns.session.pinned == s.key then
			title = "|cff66ccff[1er]|r " .. title
		end
		if S().compact and s.lateWhy then
			title = title .. " |cffff7777(plus tard)|r"
		end
		row.title:SetText(title)
		local sub = s.subtitle or ""
		if s.tour then
			if s.tour.index == 1 then
				sub = string.format("|cff66ff66Tournée : %d quêtes (étapes %d–%d)|r · ", s.tour.quests, s.tour.first, s.tour.last) .. sub
			else
				sub = sub .. string.format(" · |cff66ff66tournée %d/%d|r", s.tour.index, s.tour.size)
			end
		end
		if s.kind == "pickup" and s.candidate then
			sub = sub .. " · |cff66ccff" .. (s.candidate.chainOf and "suite" or s.candidate.inRegion and "dans la région" or "sur ton trajet") .. "|r"
		elseif s.kind == "service" and s.service.urgent then
			sub = sub .. " · |cffff7777urgent|r"
		end
		if s.elite and not s.lateWhy then
			sub = sub .. " · |cffff9933élites|r"
		end
		local who = s.owners and ns.Group and ns.Group.OwnersText(s.owners, plan.groupSize or (plan.group and plan.group.size))
		if who then
			sub = sub .. " · |cff66ccff" .. who .. "|r"
		end
		if s.hearth then
			sub = sub .. " · |cffffd100pierre de foyer|r"
		end
		if s.away then
			sub = sub .. " · |cff999999après la région|r"
		end
		if s.lateWhy then
			sub = sub .. " · |cffff7777plus tard (" .. s.lateWhy .. ")|r"
		elseif s.gateLevel then
			sub = sub .. " · |cffffd100dès le niv " .. s.gateLevel .. "|r"
		end
		if s.levelUp then
			sub = sub .. " · |cff66ff66niv " .. s.levelUp .. " ici|r"
		end
		row.sub:SetText(sub)
		local current = s.number == 1
		row.time:SetText(current and ("» " .. Duration(s.leg)) or Duration(s.leg))
		row.time:SetTextColor(unpack(current and Skin.Theme().hl or Skin.COLORS.grey))
		row.num:SetTextColor(unpack(current and Skin.Theme().hl or Skin.COLORS.grey))
		row.bg:SetShown(current)
		row.accent:SetShown(current)
		row.stripe:SetShown(not current and (offset + i) % 2 == 0)
		-- avancement des objectifs de l'étape (« 3/8 » -> barre), pas en mode compact
		local progress = not row.compact and UI.StopProgress(s) or nil
		row.bar:SetProgress(progress and progress > 0 and progress or nil)
	end
	for i = visible + 1, #rows do
		rows[i].stop = nil
	end
	if #order > (S().rows or 8) then
		local range = string.format("étapes %d–%d sur %d", offset + 1, offset + visible, #order)
		more:SetText(ns.session.expanded and ("Réduire · " .. range) or ("Voir plus · " .. range))
		more:Show()
	else
		more:Hide()
	end
	advice:SetText(AdviceText(plan))
	UI.SetStatus(ns.StatusText())
	UI.Layout(visible)
end

-------------------------------------------------------------------------------
-- Bandeau « prochaine étape » : en gros, près de la flèche, ce qu'il y a à faire maintenant
-------------------------------------------------------------------------------

local function Short(text, max)
	text = tostring(text or "")
	if #text <= max then
		return text
	end
	local cut = max
	-- ne jamais couper un caractère accentué en deux
	while cut > 1 and text:byte(cut + 1) and text:byte(cut + 1) >= 0x80 and text:byte(cut + 1) < 0xC0 do
		cut = cut - 1
	end
	return text:sub(1, cut) .. "…"
end

local function PlaceBanner()
	banner:ClearAllPoints()
	local pos = S().bannerPos
	if type(pos) == "table" and type(pos[3]) == "number" and type(pos[4]) == "number" then
		banner:SetPoint(pos[1] or "CENTER", UIParent, pos[2] or "CENTER", pos[3], pos[4])
		return
	end
	-- Pas encore déplacé : juste au-dessus de la flèche de Shortest Path (là où elle est).
	local db = rawget(_G, "ShortestPathForeverDB")
	local x, y = type(db) == "table" and db.arrowX, type(db) == "table" and db.arrowY
	if type(x) == "number" and type(y) == "number" then
		banner:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", x, y + 45)
	else
		banner:SetPoint("BOTTOM", UIParent, "TOP", 0, -118)
	end
end

-- Temps restant jusqu'à l'étape : celui de la flèche (vrai chemin) quand elle y va, sinon à pied.
local function BannerTime(s)
	local p = ns.Geo.Player()
	local d = ns.Geo.Yards(p, s)
	if d and d <= math.max(s.radius or 0, 25) then
		local work = (s.work or 0) >= 50 and (" · ~" .. Minutes(s.work) .. " min sur place") or ""
		return "|cff66ff66Sur place|r" .. work, true
	end
	local api = ns.Geo.SPApi()
	if api and api.Journey and ns.session.previous == s.key then
		local ok, journey = pcall(api.Journey)
		if ok and type(journey) == "table" and journey.owner == ns.OWNER and type(journey.secondsLeft) == "number"
			and journey.secondsLeft > 0 then
			local leg = type(journey.legs) == "table" and journey.legs[1]
			local how = type(leg) == "table" and leg.mode ~= "walk" and type(leg.text) == "string" and Safe(leg.text) or nil
			return Duration(journey.secondsLeft) .. (how and (" · " .. how) or "")
		end
	end
	local walk = s.legWalk ~= false and ns.Geo.Walk(p, s)
	return Duration(walk or s.leg)
end

function UI.UpdateBannerTime()
	if not (banner and banner:IsShown()) then
		return
	end
	local s = banner.stop
	if ns.session.paused or not s then
		return
	end
	local plan = ns.plan
	local nextStop = plan and plan.order and plan.order[2]
	local line, here = BannerTime(s)
	if plan and plan.turninOnly then
		line = "|cffffd100Rendus|r · " .. line
	end
	if nextStop then
		line = line .. " |cff888888· ensuite : " .. Short(nextStop.title, 40) .. "|r"
	end
	banner.line:SetText(line)
	-- sur place : bordure verte (on y est)
	if here ~= rawget(banner, "here") then
		banner.here = here or false
		UI.StyleBanner()
	end
	local chip = banner.pilot:IsShown() and 48 or 0
	local width = math.max((banner.title:GetStringWidth() or 0) + chip, banner.line:GetStringWidth() or 0) + 62
	banner:SetWidth(math.max(260, math.min(560, width)))
end

function UI.UpdateBannerVisibility()
	if not banner then
		return
	end
	local s = S()
	local plan = ns.plan
	local show = s.banner ~= false and ns.ready and ((plan and plan.order and plan.order[1]) or ns.session.paused) and true or false
	if show and s.hideCombat and InCombatLockdown() then
		show = false
	end
	if show and s.hideInstance and IsInInstance() then
		show = false
	end
	banner:SetShown(show)
end

function UI.RefreshBanner(plan)
	if not banner then
		return
	end
	plan = plan or ns.plan
	local s = plan and plan.order and plan.order[1]
	banner.stop = s
	local paused = ns.session.paused and true or false
	if paused then
		banner.icon:SetTexture(ICONS.area)
		banner.title:SetText("|cffff9933Guidage en pause|r")
		banner.line:SetText("Clic droit : reprendre (ou bouton de recalcul de la fenêtre)")
		banner.bar:SetProgress(nil)
	elseif s then
		banner.icon:SetTexture(StopIcon(s))
		local who = plan.group and ("|cff66ccff[" .. plan.group.guide .. "]|r ") or ""
		banner.title:SetText(who .. "|cffffd200" .. (s.number or 1) .. ".|r " .. Short(s.title, 70) .. PickupText(s))
		banner.bar:SetProgress(UI.StopProgress(s))
	end
	-- nouvelle étape : le bandeau s'allume un instant
	local key = paused and "pause" or (s and s.key)
	if key ~= rawget(banner, "lastKey") then
		banner.lastKey = key
		if rawget(banner, "flash") and banner:IsShown() then
			banner.flash:Stop()
			banner.flash:Play()
		end
	end
	if paused ~= rawget(banner, "paused") then
		banner.paused = paused
		UI.StyleBanner()
	end
	banner.pilot:SetShown(not ns.piloteMissing and ns.Pilote and ns.Pilote.Config and ns.Pilote.Config().on == true or false)
	UI.UpdateBannerVisibility()
	UI.UpdateBannerTime()
end

local function BannerMenu()
	if ns.session.paused then
		UI.ShowMenu({
			{ text = "Guidage en pause", title = true },
			{
				text = "Reprendre le guidage",
				func = function()
					ns.SetPaused(false)
					ns.RequestPlan("bandeau", 0)
				end,
			},
			{ text = "Fermer" },
		})
	elseif banner.stop then
		RowMenu(banner)
	end
end

function UI.CreateBanner()
	if banner then
		return
	end
	banner = CreateFrame("Button", "ItineraireBanner", UIParent, "BackdropTemplate")
	banner:SetSize(360, 50)
	banner:SetClampedToScreen(true)
	banner:SetMovable(true)
	banner:EnableMouse(true)
	banner:SetFrameStrata("MEDIUM")
	banner:RegisterForDrag("LeftButton")
	banner:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	banner:SetScript("OnDragStart", function(self)
		if not S().locked then
			self:StartMoving()
		end
	end)
	banner:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, rel, x, y = self:GetPoint()
		S().bannerPos = { point, rel, x, y }
	end)
	-- icône du type d'étape dans un cadre
	banner.iconFrame = CreateFrame("Frame", nil, banner)
	banner.iconFrame:SetSize(30, 30)
	banner.iconFrame:SetPoint("LEFT", 9, 0)
	Skin.Border(banner.iconFrame, 0, 0, 0, 0.9)
	banner.icon = banner.iconFrame:CreateTexture(nil, "ARTWORK")
	banner.icon:SetAllPoints()
	banner.title = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	banner.title:SetPoint("TOPLEFT", 48, -8)
	banner.title:SetJustifyH("LEFT")
	banner.title:SetWordWrap(false)
	banner.line = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	banner.line:SetPoint("TOPLEFT", banner.title, "BOTTOMLEFT", 0, -3)
	banner.line:SetJustifyH("LEFT")
	banner.line:SetWordWrap(false)
	-- avancement des objectifs de l'étape
	banner.bar = Skin.Bar(banner, 3)
	banner.bar:SetPoint("BOTTOMLEFT", 48, 6)
	banner.bar:SetPoint("RIGHT", -10, 0)
	-- « PILOTE » en vert quand le pilote automatique est actif
	banner.pilot = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	banner.pilot:SetPoint("TOPRIGHT", -8, -6)
	banner.pilot:SetText("PILOTE")
	banner.pilot:SetTextColor(0.35, 0.95, 0.45)
	banner.pilot:Hide()
	-- s'allume un instant à chaque nouvelle étape
	if banner.CreateAnimationGroup then
		banner.flash = banner:CreateAnimationGroup()
		local fade = banner.flash:CreateAnimation("Alpha")
		fade:SetFromAlpha(0.35)
		fade:SetToAlpha(1)
		fade:SetDuration(0.35)
		fade:SetSmoothing("OUT")
	end
	banner:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			BannerMenu()
		else
			UI.Toggle()
		end
	end)
	banner:SetScript("OnEnter", function(self)
		if self.stop and not ns.session.paused then
			RowTooltip(self)
			GameTooltip:AddLine("Clic : afficher / masquer la fenêtre · glisser : déplacer", 0.5, 0.5, 0.5)
			GameTooltip:Show()
		end
	end)
	banner:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	local tick = 0
	banner:SetScript("OnUpdate", function(_, elapsed)
		tick = tick + elapsed
		if tick >= 0.5 then
			tick = 0
			UI.UpdateBannerTime()
		end
	end)
	PlaceBanner()
	banner:Hide()
end

function UI.StyleBanner()
	if not banner then
		return
	end
	local s = S()
	banner:SetScale(s.bannerScale or 1)
	-- bordure : verte sur place, orange en pause, sinon celle du thème
	local border = rawget(banner, "paused") and Skin.COLORS.orange or rawget(banner, "here") and Skin.COLORS.green or nil
	Skin.Panel(banner, math.max(0.7, s.alpha or 0.82), border)
end

function UI.ResetBannerPosition()
	S().bannerPos = nil
	if banner then
		PlaceBanner()
	end
end

-------------------------------------------------------------------------------
-- Boîte de texte à copier (rapport)
-------------------------------------------------------------------------------
local copy

-- Texte brut : sans les codes couleur du jeu (sinon ils partiraient dans le copier-coller).
local function Plain(text)
	text = tostring(text or "")
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", "/")
	return text
end

function UI.ShowCopyBox(title, hint, text)
	if not copy then
		copy = CreateFrame("Frame", "ItineraireCopy", UIParent, "BackdropTemplate")
		copy:SetSize(640, 440)
		copy:SetPoint("CENTER")
		copy:SetFrameStrata("DIALOG")
		copy:SetClampedToScreen(true)
		copy:SetMovable(true)
		copy:EnableMouse(true)
		copy:RegisterForDrag("LeftButton")
		copy:SetScript("OnDragStart", copy.StartMoving)
		copy:SetScript("OnDragStop", copy.StopMovingOrSizing)
		tinsert(UISpecialFrames, "ItineraireCopy")
		copy.titleText = Skin.Header(copy, "Itinéraire", "Interface\\Icons\\INV_Misc_Note_01")
		copy.hint = copy:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		copy.hint:SetPoint("TOPLEFT", 16, -34)
		copy.hint:SetPoint("RIGHT", -16, 0)
		copy.hint:SetJustifyH("LEFT")
		local close = CreateFrame("Button", nil, copy, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -2, -2)
		local ok, scroll = pcall(CreateFrame, "ScrollFrame", "ItineraireCopyScroll", copy, "UIPanelScrollFrameTemplate")
		if not ok then
			scroll = CreateFrame("ScrollFrame", nil, copy)
			scroll:EnableMouseWheel(true)
			scroll:SetScript("OnMouseWheel", function(self, delta)
				local max = self:GetVerticalScrollRange() or 0
				self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - delta * 40)))
			end)
		end
		scroll:SetPoint("TOPLEFT", 16, -60)
		scroll:SetPoint("BOTTOMRIGHT", -34, 44)
		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetAutoFocus(false)
		edit:SetFontObject("GameFontHighlightSmall")
		edit:SetWidth(580)
		if edit.SetMaxLetters then
			edit:SetMaxLetters(0)
		end
		edit:SetScript("OnEscapePressed", function()
			copy:Hide()
		end)
		-- Lecture seule : une frappe remet le texte d'origine.
		edit:SetScript("OnTextChanged", function(self, user)
			if user then
				self:SetText(copy.text or "")
				self:HighlightText()
			end
		end)
		scroll:SetScrollChild(edit)
		copy.edit = edit
		local select = Skin.Button(copy, "Tout sélectionner", 150, 22, function()
			copy.edit:SetFocus()
			copy.edit:HighlightText()
		end)
		select:SetPoint("BOTTOMLEFT", 14, 12)
		local done = Skin.Button(copy, "Fermer", 90, 22, function()
			copy:Hide()
		end)
		done:SetPoint("BOTTOMRIGHT", -14, 12)
		copy.buttons = { select, done }
	end
	copy.text = Plain(text)
	Skin.Panel(copy, 0.97)
	Skin.HeaderColors(copy)
	for _, b in ipairs(copy.buttons) do
		Skin.StyleButton(b)
	end
	copy.titleText:SetText(title or "Itinéraire")
	copy.hint:SetText(hint or "")
	copy.edit:SetText(copy.text)
	copy:Show()
	copy.edit:SetFocus()
	copy.edit:HighlightText()
	return copy.text
end

function UI.Toggle(show)
	if not frame then
		return
	end
	if show == nil then
		show = not frame:IsShown()
	end
	S().shown = show
	UI.UpdateVisibility()
end

function UI.ResetPosition()
	if not frame then
		return
	end
	local s = S()
	s.point, s.rel, s.x, s.y = "LEFT", "LEFT", 20, 120
	frame:ClearAllPoints()
	frame:SetPoint("LEFT", UIParent, "LEFT", 20, 120)
end
