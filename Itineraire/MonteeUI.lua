-- Itinéraire : fenêtre « Ma montée » (frise jusqu'au niveau 60, soirée planifiée, minage et forge).
local _, ns = ...
local MonteeUI = {}
ns.MonteeUI = MonteeUI

local frame, text, scroll, child
local tabs, buttons = {}, {}
local current = "frise"

local TABS = {
	{ key = "frise", label = "Frise jusqu'au 60" },
	{ key = "soiree", label = "Ma soirée" },
	{ key = "metiers", label = "Minage et forge" },
}
local DURATIONS = { { 30, "30 min" }, { 60, "1 h" }, { 90, "1 h 30" }, { 120, "2 h" }, { 180, "3 h" } }

local function Comma(x)
	return (string.format("%.1f", x or 0):gsub("%.", ","))
end

local function Minutes(seconds)
	local m = math.floor((seconds or 0) / 60 + 0.5)
	if m >= 60 then
		return string.format("%d h %02d", math.floor(m / 60), m % 60)
	end
	return m .. " min"
end
MonteeUI.Minutes = Minutes

local function Clock(t)
	return date("%H:%M", math.floor(t or 0))
end

function MonteeUI.SoireeLines()
	local lines = {}
	local s = ns.SoireeActive and ns.SoireeActive()
	local plan = ns.plan
	if s then
		local left = s.fin - time()
		lines[#lines + 1] = string.format("|cffb48cffSoirée en cours|r jusqu'à %s (%s).", Clock(s.fin),
			left > 0 and ("encore " .. Minutes(left)) or "c'est l'heure : direction l'auberge")
		local so = plan and plan.soiree
		if so then
			lines[#lines + 1] = string.format("%d quête(s) ce soir : celles qui rapportent le plus d'XP par minute dans ton temps.",
				so.chosen or 0)
			local inn = so.innStep and plan.order[so.innStep]
			if inn then
				lines[#lines + 1] = string.format("Fin à l'étape %d : %s, vers %s, au niveau %s.", so.innStep, inn.title,
					Clock((plan.at or time()) + (so.endEta or 0)), Comma(so.levelEnd))
			elseif so.skippedInn then
				lines[#lines + 1] = "Auberge passée : la soirée finit à sa dernière étape."
			elseif so.noInn then
				lines[#lines + 1] = "Aucune auberge trouvée près de la fin : déconnecte-toi en ville si tu peux (repos plus rapide)."
			end
			if (so.afterCount or 0) > 0 then
				lines[#lines + 1] = string.format("%d étape(s) gardée(s) pour la prochaine soirée (« après la soirée ») : aucune quête n'est écartée.",
					so.afterCount)
			end
		elseif plan and plan.groupMode then
			lines[#lines + 1] = "En groupe, le trajet est celui du guide : la soirée reprendra quand tu joueras seul."
		else
			lines[#lines + 1] = "Calcul en cours…"
		end
		if s.niveau then
			lines[#lines + 1] = string.format("|cff888888Début : niveau %d (%d %%) à %s ; %d quête(s) rendue(s) depuis.|r", s.niveau,
				(s.xpMax or 0) > 0 and math.floor((s.xp or 0) / s.xpMax * 100) or 0, Clock(s.debut), s.rendues or 0)
		end
		lines[#lines + 1] = ""
		lines[#lines + 1] = "Autre durée : boutons ci-dessous (repart de maintenant). Arrêter : bouton « Arrêter » ou /iti soiree stop."
	else
		lines[#lines + 1] = "Pas de soirée en cours."
		lines[#lines + 1] = ""
		lines[#lines + 1] = "Dis combien de temps tu as : Itinéraire garde les quêtes qui rapportent le plus d'XP dans ce temps "
			.. "et finit le trajet dans une auberge, où ton repos monte 4 fois plus vite qu'en pleine nature. Si ta pierre de "
			.. "foyer est prête à la fin et fait gagner du temps, c'est elle qui t'y emmène."
		lines[#lines + 1] = "Le reste du journal passe après l'auberge : aucune quête n'est écartée."
		lines[#lines + 1] = ""
		lines[#lines + 1] = "Boutons ci-dessous, ou dans le tchat : /iti soiree 1h30 · /iti soiree 45 · /iti soiree 23h (jusqu'à 23 h)."
	end
	return lines
end

local function Lines(tab)
	if tab == "soiree" then
		return MonteeUI.SoireeLines()
	elseif tab == "metiers" then
		return ns.Montee.CraftLines()
	end
	return ns.Montee.FriseLines()
end

function MonteeUI.Refresh()
	if not (frame and frame:IsShown()) then
		return
	end
	local ok, lines = pcall(Lines, current)
	if not ok then
		local err = tostring(lines)
		lines = { "|cffff5555Erreur|r : " .. err, "Tape /iti rapport et colle le texte : je corrigerai." }
		if ns.OnError then
			ns.OnError("montée : " .. err)
		end
	end
	text:SetText(table.concat(lines, "\n"))
	child:SetHeight(math.max(20, (text:GetStringHeight() or 0) + 12))
	for key, list in pairs(buttons) do
		for _, b in ipairs(list) do
			b:SetShown(key == current)
		end
	end
	for _, t in ipairs(tabs) do
		t:SetSelected(t.key == current)
	end
	ns.UI.Skin.Panel(frame, 0.97)
	ns.UI.Skin.HeaderColors(frame)
end

local function Create()
	local Skin = ns.UI.Skin
	frame = CreateFrame("Frame", "ItineraireMontee", UIParent, "BackdropTemplate")
	frame:SetSize(560, 470)
	frame:SetPoint("CENTER", 0, 40)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "ItineraireMontee")
	Skin.Header(frame, "Ma montée", "Interface\\Icons\\INV_Scroll_03", 26)
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	local x = 12
	for _, def in ipairs(TABS) do
		local b = Skin.Button(frame, def.label, 170, 22, function()
			current = def.key
			MonteeUI.Refresh()
		end)
		b.key = def.key
		b:SetPoint("TOPLEFT", x, -34)
		x = x + 176
		tabs[#tabs + 1] = b
	end
	local ok, sf = pcall(CreateFrame, "ScrollFrame", "ItineraireMonteeScroll", frame, "UIPanelScrollFrameTemplate")
	if not ok then
		sf = CreateFrame("ScrollFrame", nil, frame)
		sf:EnableMouseWheel(true)
		sf:SetScript("OnMouseWheel", function(self, delta)
			local max = self:GetVerticalScrollRange() or 0
			self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - delta * 40)))
		end)
	end
	scroll = sf
	scroll:SetPoint("TOPLEFT", 14, -66)
	scroll:SetPoint("BOTTOMRIGHT", -32, 44)
	child = CreateFrame("Frame", nil, scroll)
	child:SetSize(510, 20)
	scroll:SetScrollChild(child)
	text = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("TOPLEFT", 2, -2)
	text:SetWidth(505)
	text:SetJustifyH("LEFT")
	text:SetJustifyV("TOP")
	text:SetSpacing(3)
	-- Boutons du bas, selon l'onglet.
	buttons.soiree = {}
	local bx = 12
	for _, d in ipairs(DURATIONS) do
		local b = Skin.Button(frame, d[2], 72, 22, function()
			ns.SoireeStart(d[1])
			MonteeUI.Refresh()
		end)
		b:SetPoint("BOTTOMLEFT", bx, 12)
		bx = bx + 78
		buttons.soiree[#buttons.soiree + 1] = b
	end
	local stop = Skin.Button(frame, "Arrêter", 90, 22, function()
		ns.SoireeStop("bouton")
		MonteeUI.Refresh()
	end)
	stop:SetPoint("BOTTOMRIGHT", -12, 12)
	buttons.soiree[#buttons.soiree + 1] = stop
	local again = Skin.Button(frame, "Recalculer", 110, 22, function()
		MonteeUI.Refresh()
	end)
	again:SetPoint("BOTTOMRIGHT", -12, 12)
	buttons.frise = { again }
	local refresh = Skin.Button(frame, "Actualiser", 110, 22, function()
		MonteeUI.Refresh()
	end)
	refresh:SetPoint("BOTTOMRIGHT", -12, 12)
	buttons.metiers = { refresh }
	frame:Hide()
end

-- Ouvre (ou ferme) la fenêtre ; `tab` : « frise », « soiree » ou « metiers ».
function MonteeUI.Toggle(show, tab)
	if not frame then
		Create()
	end
	if tab then
		current = tab
	end
	if show == nil then
		show = not frame:IsShown() or (tab ~= nil)
	end
	if show then
		frame:Show()
		pcall(ns.Montee.BuildIndex)
		MonteeUI.Refresh()
	else
		frame:Hide()
	end
end

function MonteeUI.Shown()
	return frame and frame:IsShown() or false
end
