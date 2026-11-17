-- Itinéraire : fenêtre « Équipement » (/iti equipement, bouton … > Équipement).
-- Les améliorations trouvées pour ton personnage, emplacement par emplacement, avec leur source ;
-- « Y aller » ajoute la source au trajet (vendeur, PNJ, donjon, ou la quête qui le donne).
local _, ns = ...
local GearUI = {}
ns.GearUI = GearUI

local ROWS = 10
local ROW_H = 36
local frame, rows, statusText, roleBtn, emptyText
local offset = 0

local BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 14,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local QUALITY = { [0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee", [5] = "ffff8000" }

local function Gear()
	return ns.Gear
end

local function RoleText()
	local G = Gear()
	local role, why = G.Role()
	return (G.ROLE_LABEL[role] or role) .. " |cff888888(" .. why .. ")|r"
end

local function StatusLine()
	local G = Gear()
	local st = G.state
	local r = G.results
	local parts = { "Rôle : " .. RoleText() }
	if G.Busy() then
		local pct = (st.total or 0) > 0 and math.floor((st.done or 0) / st.total * 100) or 0
		parts[#parts + 1] = "|cffffd200analyse (" .. tostring(st.phase) .. ") " .. pct .. " %|r"
	elseif r then
		parts[#parts + 1] = #r.list .. " amélioration(s) au niveau " .. r.level
	end
	return table.concat(parts, " · ")
end

local function SourceLine(e)
	local s = e.best
	if not s then
		return ""
	end
	local more = #e.sources > 1 and (" |cff888888(+" .. (#e.sources - 1) .. " autre(s))|r") or ""
	return e.slotName .. " · " .. s.text .. more
end

local function ShowTooltip(row)
	local e = row.entry
	if not e then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if e.link and GameTooltip.SetHyperlink then
		pcall(GameTooltip.SetHyperlink, GameTooltip, e.link)
	else
		GameTooltip:AddLine(e.name or "?", 1, 1, 1)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Itinéraire : " .. Gear().GainText(e) .. " pour ton rôle (" .. e.slotName .. ")", 0.3, 1, 0.3, true)
	for _, s in ipairs(e.sources or {}) do
		GameTooltip:AddLine("· " .. s.text, 1, 1, 1, true)
	end
	if e.req and e.req > (UnitLevel("player") or 1) then
		GameTooltip:AddLine("Portable au niveau " .. e.req .. ".", 1, 0.6, 0.2, true)
	end
	GameTooltip:AddLine("Clic : ajouter au trajet / retirer · Clic droit : plus d'options", 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

local function Actionable(e)
	local s = e and e.best
	return s and s.kind ~= "later" and s.kind ~= "journal" and s.points and s.points[1] and true or false
end

local function ToggleGoal(e)
	local G = Gear()
	if not Actionable(e) then
		if e.best and e.best.kind == "journal" then
			ns.Print(e.link .. " : c'est la récompense d'une quête de ton journal, elle est déjà sur ton trajet.")
		else
			ns.Print(e.link .. " : pas encore accessible (" .. (e.best and e.best.text or "source inconnue") .. ").")
		end
		return
	end
	local on = not G.IsGoal(e.id)
	G.SetGoal(e.id, on)
	ns.Print(on and ("ajouté au trajet : " .. e.link .. " — " .. e.best.text .. ".")
		or ("retiré du trajet : " .. e.link .. "."))
	GearUI.Refresh()
end

local function RowMenu(e)
	local G = Gear()
	local items = { { text = e.name or "?", title = true } }
	if Actionable(e) then
		items[#items + 1] = {
			text = G.IsGoal(e.id) and "Retirer du trajet" or "Ajouter au trajet (Y aller)",
			func = function()
				ToggleGoal(e)
			end,
		}
	end
	items[#items + 1] = {
		text = "Ne plus me le proposer",
		func = function()
			G.Ignore(e.id)
			GearUI.Refresh()
			ns.RequestPlan("équipement", 0)
		end,
	}
	items[#items + 1] = { text = "Fermer" }
	ns.UI.ShowMenu(items)
end

local function MakeRow(i)
	local row = CreateFrame("Button", nil, frame)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", 10, -64 - (i - 1) * ROW_H)
	row:SetPoint("RIGHT", -10, 0)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(30, 30)
	row.icon:SetPoint("LEFT", 0, 0)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
	row.name:SetPoint("RIGHT", -110, 0)
	row.name:SetJustifyH("LEFT")
	row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
	row.sub:SetPoint("RIGHT", -110, 0)
	row.sub:SetJustifyH("LEFT")
	row.gain = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.gain:SetPoint("TOPRIGHT", -2, -2)
	row.go = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.go:SetSize(80, 18)
	row.go:SetPoint("BOTTOMRIGHT", -2, 1)
	row.go:SetScript("OnClick", function()
		ToggleGoal(row.entry)
	end)
	row:SetScript("OnClick", function(self, button)
		if not self.entry then
			return
		end
		if button == "RightButton" then
			RowMenu(self.entry)
		else
			ToggleGoal(self.entry)
		end
	end)
	row:SetScript("OnEnter", ShowTooltip)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return row
end

local function RoleMenu()
	local G = Gear()
	local cfg = G.Config()
	local items = { { text = "Rôle pour noter les objets", title = true } }
	for _, r in ipairs(G.ROLES) do
		items[#items + 1] = {
			text = r.key == "auto" and "Auto (d'après tes talents)" or r.label,
			checked = (cfg.role or "auto") == r.key,
			func = function()
				cfg.role = r.key
				G.ResetWorn()
				G.Rescan()
				GearUI.Refresh()
			end,
		}
	end
	items[#items + 1] = { text = "Fermer" }
	ns.UI.ShowMenu(items)
end

local function Build()
	frame = CreateFrame("Frame", "ItineraireGear", UIParent, "BackdropTemplate")
	frame:SetSize(430, 64 + ROWS * ROW_H + 52)
	frame:SetPoint("CENTER", 0, 40)
	frame:SetBackdrop(BACKDROP)
	frame:SetBackdropColor(0.03, 0.03, 0.06, 0.96)
	frame:SetBackdropBorderColor(0.4, 0.6, 0.9, 1)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	tinsert(UISpecialFrames, "ItineraireGear")

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText("Équipement — tes améliorations")
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	statusText:SetPoint("TOPLEFT", 14, -36)
	statusText:SetPoint("RIGHT", -150, 0)
	statusText:SetJustifyH("LEFT")

	roleBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	roleBtn:SetSize(64, 20)
	roleBtn:SetPoint("TOPRIGHT", -84, -32)
	roleBtn:SetText("Rôle…")
	roleBtn:SetScript("OnClick", RoleMenu)
	local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	refresh:SetSize(72, 20)
	refresh:SetPoint("LEFT", roleBtn, "RIGHT", 4, 0)
	refresh:SetText("Actualiser")
	refresh:SetScript("OnClick", function()
		Gear().ResetWorn()
		Gear().Rescan()
		GearUI.Refresh()
	end)

	rows = {}
	for i = 1, ROWS do
		rows[i] = MakeRow(i)
	end
	emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	emptyText:SetPoint("TOPLEFT", 16, -80)
	emptyText:SetPoint("RIGHT", -16, 0)
	emptyText:SetJustifyH("LEFT")

	local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	note:SetPoint("BOTTOMLEFT", 14, 12)
	note:SetPoint("RIGHT", -14, 0)
	note:SetJustifyH("LEFT")
	note:SetText("Notes calculées avec les caractéristiques des objets et la base de Questie (récompenses, vendeurs, butins). "
		.. "Les taux de butin ne sont pas connus. Molette : faire défiler.")

	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		local r = Gear().results
		local n = r and #r.list or 0
		offset = math.max(0, math.min(math.max(0, n - ROWS), offset - delta * 2))
		GearUI.Refresh()
	end)
	-- Pendant l'analyse : l'avancement se met à jour tout seul.
	local acc = 0
	frame:SetScript("OnUpdate", function(_, elapsed)
		acc = acc + elapsed
		if acc > 0.5 then
			acc = 0
			if Gear().Busy() then
				statusText:SetText(StatusLine())
			end
		end
	end)
end

function GearUI.Refresh()
	if not frame or not frame:IsShown() then
		return
	end
	local G = Gear()
	statusText:SetText(StatusLine())
	local list = G.results and G.results.list or {}
	offset = math.max(0, math.min(offset, math.max(0, #list - ROWS)))
	for i = 1, ROWS do
		local row = rows[i]
		local e = list[offset + i]
		row.entry = e
		if e then
			row.icon:SetTexture(e.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
			row.name:SetText("|c" .. (QUALITY[e.quality] or "ffffffff") .. (e.name or "?") .. "|r"
				.. ((e.req or 0) > (UnitLevel("player") or 1) and (" |cffff9933(niv " .. e.req .. ")|r") or ""))
			row.sub:SetText(SourceLine(e))
			row.gain:SetText("|cff00ff00" .. G.GainText(e) .. "|r")
			local goal = G.IsGoal(e.id)
			row.go:SetText(goal and "Sur le trajet" or (Actionable(e) and "Y aller" or "—"))
			row.go:SetEnabled(Actionable(e))
			row:Show()
		else
			row:Hide()
		end
	end
	if #list == 0 then
		emptyText:SetText(G.Busy() and "Analyse en cours : la base de Questie est passée en revue (quelques secondes à une minute)…"
			or G.results and "Aucune amélioration trouvée à ton niveau pour l'instant (récompenses, vendeurs et butins connus)."
			or "Pas encore d'analyse : clique sur « Actualiser ».")
		emptyText:Show()
	else
		emptyText:Hide()
	end
end

function GearUI.Toggle(show)
	if not frame then
		Build()
	end
	if show == nil then
		show = not frame:IsShown()
	end
	if show then
		frame:Show()
		if not Gear().results and not Gear().Busy() then
			Gear().Rescan()
		end
		GearUI.Refresh()
	else
		frame:Hide()
	end
end
