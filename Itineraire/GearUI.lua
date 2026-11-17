-- Itinéraire : fenêtre « Équipement » (/iti equipement, bouton E, menu … > Équipement).
-- Onglet « Améliorations » : ce qui t'améliorerait à ton niveau, emplacement par emplacement, avec sa source ;
-- onglet « Donjons » : quel donjon (ou raid) faire pour ton équipement. « Y aller » ajoute la source au trajet.
local _, ns = ...
local GearUI = {}
ns.GearUI = GearUI

local ROWS = 10
local ROW_H = 36
local TOP = 88
local frame, rows, statusText, emptyText, tabs
local offset = 0
local tab = "items"

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

-- Composants d'une recette : « 8 × Barre de cuivre, 2 × Pierre brute ».
local function Reagents(text)
	local parts = {}
	for id, n in tostring(text or ""):gmatch("(%d+):(%d+)") do
		id = tonumber(id)
		local info = Gear().Info(id)
		local fallback = ns.Data.ItemFallback(id)
		parts[#parts + 1] = n .. " × " .. (info and info.name or fallback and fallback.name or ("objet " .. id))
		if not info then
			Gear().RequestLoad(id)
		end
	end
	return table.concat(parts, ", ")
end

local function ShowItemTooltip(row)
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
		if (s.kind == "craft" or s.kind == "recipe") and s.reagents and s.reagents ~= "" then
			GameTooltip:AddLine("   composants : " .. Reagents(s.reagents), 0.7, 0.7, 0.7, true)
		end
	end
	if e.req and e.req > (UnitLevel("player") or 1) then
		GameTooltip:AddLine("Portable au niveau " .. e.req .. ".", 1, 0.6, 0.2, true)
	end
	GameTooltip:AddLine("Clic : ajouter au trajet / retirer · Clic droit : plus d'options", 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

local function ShowDungeonTooltip(row)
	local r = row.dungeonEntry
	if not r then
		return
	end
	local d = r.dungeon
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(d.name .. " (niv " .. d.min .. "-" .. d.max .. ")", 1, 0.82, 0)
	GameTooltip:AddLine(r.count .. " emplacement(s) amélioré(s) pour toi :", 1, 1, 1)
	local shown = 0
	table.sort(r.items, function(a, b)
		return a.gain > b.gain
	end)
	for _, e in ipairs(r.items) do
		if shown < 10 then
			local boss = ""
			for _, s in ipairs(e.sources or {}) do
				if s.kind == "dungeon" and s.dungeon == d.id then
					boss = " — " .. s.name
					break
				end
			end
			GameTooltip:AddLine("· " .. (e.link or e.name) .. " " .. Gear().GainText(e) .. boss, 1, 1, 1, true)
			shown = shown + 1
		end
	end
	if not d.entrance then
		GameTooltip:AddLine("Entrée inconnue : pas de « Y aller » pour ce donjon.", 1, 0.5, 0.3, true)
	end
	GameTooltip:AddLine("Clic : ajouter l'entrée au trajet / retirer", 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

local function Actionable(e)
	return Gear().Target(e) ~= nil
end

local function ToggleGoal(e)
	local G = Gear()
	local target = G.Target(e)
	if not target then
		local s = e.best
		if s and s.kind == "journal" then
			ns.Print(e.link .. " : c'est la récompense d'une quête de ton journal, elle est déjà sur ton trajet.")
		elseif s and s.kind == "craft" then
			ns.Print(e.link .. " : " .. s.text .. ".")
		else
			ns.Print(e.link .. " : pas encore accessible (" .. (s and s.text or "source inconnue") .. ").")
		end
		return
	end
	local on = not G.IsGoal(e.id)
	G.SetGoal(e.id, on)
	ns.Print(on and ("ajouté au trajet : " .. e.link .. " — " .. target.text .. ".") or ("retiré du trajet : " .. e.link .. "."))
	GearUI.Refresh()
end

local function ToggleDungeon(r)
	local G, d = Gear(), r.dungeon
	if not d.entrance then
		ns.Print(d.name .. " : entrée inconnue, impossible de l'ajouter au trajet.")
		return
	end
	local on = not G.IsDungeonGoal(d.id)
	G.SetDungeonGoal(d.id, on)
	ns.Print(on and ("ajouté au trajet : l'entrée de " .. d.name .. ".") or ("retiré du trajet : " .. d.name .. "."))
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
	row:SetPoint("TOPLEFT", 10, -TOP - (i - 1) * ROW_H)
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
	row.go:SetSize(84, 18)
	row.go:SetPoint("BOTTOMRIGHT", -2, 1)
	row.go:SetScript("OnClick", function()
		if row.dungeonEntry then
			ToggleDungeon(row.dungeonEntry)
		elseif row.entry then
			ToggleGoal(row.entry)
		end
	end)
	row:SetScript("OnClick", function(self, button)
		if self.dungeonEntry then
			ToggleDungeon(self.dungeonEntry)
		elseif self.entry then
			if button == "RightButton" then
				RowMenu(self.entry)
			else
				ToggleGoal(self.entry)
			end
		end
	end)
	row:SetScript("OnEnter", function(self)
		if self.dungeonEntry then
			ShowDungeonTooltip(self)
		else
			ShowItemTooltip(self)
		end
	end)
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

local function SetTab(key)
	tab = key
	offset = 0
	for k, b in pairs(tabs) do
		if k == key then
			b:LockHighlight()
		else
			b:UnlockHighlight()
		end
	end
	GearUI.Refresh()
end

local function Button(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 20)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

local function Build()
	frame = CreateFrame("Frame", "ItineraireGear", UIParent, "BackdropTemplate")
	frame:SetSize(450, TOP + ROWS * ROW_H + 56)
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
	title:SetText("Équipement")
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	statusText:SetPoint("TOPLEFT", 14, -36)
	statusText:SetPoint("RIGHT", -150, 0)
	statusText:SetJustifyH("LEFT")

	local roleBtn = Button(frame, "Rôle…", 64, RoleMenu)
	roleBtn:SetPoint("TOPRIGHT", -84, -32)
	local refresh = Button(frame, "Actualiser", 72, function()
		Gear().ResetWorn()
		Gear().Rescan()
		GearUI.Refresh()
	end)
	refresh:SetPoint("LEFT", roleBtn, "RIGHT", 4, 0)

	tabs = {}
	tabs.items = Button(frame, "Améliorations", 110, function()
		SetTab("items")
	end)
	tabs.items:SetPoint("TOPLEFT", 12, -58)
	tabs.dungeons = Button(frame, "Donjons", 90, function()
		SetTab("dungeons")
	end)
	tabs.dungeons:SetPoint("LEFT", tabs.items, "RIGHT", 4, 0)

	rows = {}
	for i = 1, ROWS do
		rows[i] = MakeRow(i)
	end
	emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	emptyText:SetPoint("TOPLEFT", 16, -TOP - 12)
	emptyText:SetPoint("RIGHT", -16, 0)
	emptyText:SetJustifyH("LEFT")

	local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	note:SetPoint("BOTTOMLEFT", 14, 12)
	note:SetPoint("RIGHT", -14, 0)
	note:SetJustifyH("LEFT")
	note:SetText("Notes calculées avec les caractéristiques des objets. Sources : Questie, Dropdon et All The Things (donjons), "
		.. "Guildon Crafts (métiers), Finddon et « Data from ForeverDB.net » (vendeurs). Taux de butin inconnus. Molette : défiler.")

	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		local n = GearUI.Count()
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
	SetTab("items")
end

local ranking
function GearUI.Count()
	if tab == "dungeons" then
		return ranking and #ranking or 0
	end
	local r = Gear().results
	return r and #r.list or 0
end

local function FillItems()
	local G = Gear()
	local list = G.results and G.results.list or {}
	offset = math.max(0, math.min(offset, math.max(0, #list - ROWS)))
	for i = 1, ROWS do
		local row = rows[i]
		local e = list[offset + i]
		row.entry, row.dungeonEntry = e, nil
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
	return #list
end

local function FillDungeons()
	local G = Gear()
	ranking = G.DungeonRanking()
	offset = math.max(0, math.min(offset, math.max(0, #ranking - ROWS)))
	for i = 1, ROWS do
		local row = rows[i]
		local r = ranking[offset + i]
		row.entry, row.dungeonEntry = nil, r
		if r then
			local d = r.dungeon
			row.icon:SetTexture(d.raid and "Interface\\Icons\\INV_Misc_Head_Dragon_01" or "Interface\\Icons\\INV_Misc_Key_03")
			row.name:SetText((r.fits and "|cffffffff" or "|cff999999") .. d.name .. "|r |cff888888(niv " .. d.min .. "-" .. d.max .. ")|r")
			row.sub:SetText(r.count .. " emplacement(s) amélioré(s) · boss : " .. table.concat(r.bosses, ", "))
			row.gain:SetText("|cff00ff00+" .. math.floor(r.pct + 0.5) .. " %|r")
			row.go:SetText(G.IsDungeonGoal(d.id) and "Sur le trajet" or (d.entrance and "Y aller" or "—"))
			row.go:SetEnabled(d.entrance and true or false)
			row:Show()
		else
			row:Hide()
		end
	end
	return #ranking
end

function GearUI.Refresh()
	if not frame or not frame:IsShown() then
		return
	end
	local G = Gear()
	statusText:SetText(StatusLine())
	local n = tab == "dungeons" and FillDungeons() or FillItems()
	if n == 0 then
		emptyText:SetText(G.Busy() and "Analyse en cours : base de Questie, donjons, métiers et vendeurs (quelques secondes à une minute)…"
			or G.results and (tab == "dungeons" and "Aucun donjon de ton niveau n'a d'amélioration pour toi pour l'instant."
				or "Aucune amélioration trouvée à ton niveau pour l'instant (récompenses, vendeurs, butins, métiers).")
			or "Pas encore d'analyse : clique sur « Actualiser ».")
		emptyText:Show()
	else
		emptyText:Hide()
	end
end

function GearUI.Toggle(show, which)
	if not frame then
		Build()
	end
	if show == nil then
		show = not frame:IsShown()
	end
	if show then
		frame:Show()
		if which then
			SetTab(which)
		end
		if not Gear().results and not Gear().Busy() then
			Gear().Rescan()
		end
		GearUI.Refresh()
	else
		frame:Hide()
	end
end
