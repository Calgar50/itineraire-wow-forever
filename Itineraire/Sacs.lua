-- Itinéraire : vider tes sacs de ce qui ne sert pas ou plus (/iti sacs), SUR TA DEMANDE seulement.
-- Liste, avec la raison : objets gris, équipement moins bon que le tien ou que ta classe ne porte pas, consommables
-- de bas niveau, composants et recettes de métiers que tu n'as pas. Tu coches, puis :
--   - « Vendre » : tout de suite si un marchand est ouvert, sinon au prochain marchand (le trajet en ajoute un) ;
--     un objet vendu se rachète chez ce marchand tant que tu ne te déconnectes pas ;
--   - « Détruire » (2 clics) : seulement les objets cochés qui ne se vendent pas.
-- Jamais : pierre de foyer, outils de métier, objets de quête, ensembles d'équipement, améliorations (même pour plus
-- tard), composants et recettes de TES métiers, sacs.
local _, ns = ...
local Sacs = {}
ns.Sacs = Sacs

local OLD_CONSUMABLE = 15 -- un consommable 15 niveaux sous le tien ne sert plus guère
local CONFIRM_DELAY = 6
local SELL_STEP = 0.2

-- Pierre de foyer et outils de métier (pioche, marteau, couteau à dépecer, cannes à pêche, clé, bâtonnets d'enchanteur).
local KEEP = {
	[6948] = true, [2901] = true, [5956] = true, [7005] = true, [6256] = true, [6365] = true, [6366] = true,
	[6367] = true, [12225] = true, [19022] = true, [19970] = true, [6219] = true, [10498] = true, [6218] = true,
	[6339] = true, [11130] = true, [11145] = true, [16207] = true,
}
-- Recettes (classe d'objet 9) : sous-classe -> ligne de métier.
local RECIPE_LINE = { [1] = 165, [2] = 197, [3] = 202, [4] = 164, [5] = 185, [6] = 171, [7] = 129, [8] = 333, [9] = 356 }

local function Call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c, d, e = pcall(fn, ...)
	if ok then
		return a, b, c, d, e
	end
	return nil
end

local function Num(v)
	if type(v) ~= "number" then
		return nil
	end
	local ok, secret = pcall(function()
		return (issecretvalue and issecretvalue(v)) or (canaccessvalue and not canaccessvalue(v)) or false
	end)
	if not ok or secret then
		return nil
	end
	return v
end

local function True(v)
	local ok, r = pcall(function()
		return v == true
	end)
	return ok and r or false
end

local function Money(c)
	return ns.Gear.Money and ns.Gear.Money(c) or (tostring(math.floor(c or 0)) .. " pc")
end

local function Bags()
	return Num(rawget(_G, "NUM_BAG_SLOTS")) or 4
end

-- Composants utiles à TES métiers (recettes reprises de Guildon Crafts) : { [objet] = nom du métier }.
local function MyReagents(skills)
	local out = {}
	local ext = ns.Data.Ext()
	for _, r in pairs(ext.RECETTES or {}) do
		if type(r) == "table" and skills[r[1]] then
			for id in tostring(r[7] or ""):gmatch("(%d+):%d+") do
				out[tonumber(id)] = true
			end
		end
	end
	return out
end

-- Ce que l'on proposerait pour cet objet : { reason, checked } ; nil = on le garde ; "attente" = pas encore chargé.
local function Judge(bag, slot, info, ctx)
	local id = Num(info.itemID)
	if not id or KEEP[id] then
		return nil
	end
	local C = C_Container
	local quest = C and C.GetContainerItemQuestInfo and Call(C.GetContainerItemQuestInfo, bag, slot)
	if type(quest) == "table" and (True(quest.isQuestItem) or Num(quest.questID)) then
		return nil -- objet de quête (ou qui en commence une)
	end
	local it = ns.Gear.Info(info.hyperlink or id)
	if not it then
		return "attente"
	end
	if it.classID == 12 then
		return nil
	end
	if it.quality == 0 then
		return { reason = "objet gris (camelote)", checked = true }
	end
	if it.equipLoc ~= "" and it.equipLoc ~= "INVTYPE_BAG" and it.equipLoc ~= "INVTYPE_QUIVER" and it.equipLoc ~= "INVTYPE_AMMO"
		and it.equipLoc ~= "INVTYPE_TABARD" and it.equipLoc ~= "INVTYPE_BODY" then
		local set = C and C.GetContainerItemEquipmentSetInfo and Call(C.GetContainerItemEquipmentSetInfo, bag, slot)
		if True(set) then
			return nil -- dans un de tes ensembles d'équipement
		end
		local e, why = ns.Gear.Evaluate(info.hyperlink or id)
		local bound = True(info.isBound)
		if type(e) == "table" then
			if (e.gain or 0) > 0 then
				return nil -- amélioration (maintenant ou plus tard) : l'équipement automatique s'en charge
			end
			if not bound and (it.quality or 1) >= 2 then
				return { reason = "moins bon que ce que tu portes, pas encore lié : il vaut sans doute plus à l'hôtel des ventes",
					checked = false }
			end
			return { reason = "moins bon que ce que tu portes (" .. ns.Gear.GainText(e) .. ")", checked = true }
		elseif why == "pas chargé" then
			return "attente"
		elseif why == "ta classe ne peut pas le porter" then
			return { reason = "ta classe ne peut pas le porter" .. ((not bound and (it.quality or 1) >= 2) and " (pas lié : hôtel des ventes ?)" or ""),
				checked = bound or (it.quality or 1) < 2 }
		elseif type(why) == "string" and why ~= "pas un équipement" then
			return { reason = why .. " : utile seulement si tu changes de rôle", checked = false }
		end
		return nil
	end
	if it.classID == 0 and (it.req or 0) > 0 and it.req <= ctx.level - OLD_CONSUMABLE then
		return { reason = string.format("consommable de bas niveau (niv %d) : il ne sert presque plus", it.req), checked = false }
	end
	if it.classID == 7 and not ctx.reagents[id] then
		return { reason = "composant d'un métier que tu n'as pas (il vaut souvent plus à l'hôtel des ventes)", checked = false }
	end
	if it.classID == 9 then
		local line = RECIPE_LINE[it.subclassID or -1]
		if line and not ctx.skills[line] then
			return { reason = "recette d'un métier que tu n'as pas (hôtel des ventes ?)", checked = false }
		end
	end
	return nil
end

-- Le contenu des sacs trié : liste { bag, slot, itemID, name, count, value, sellable, reason, checked }, et le nombre
-- d'objets pas encore chargés par le jeu (redemandés).
function Sacs.Analyse()
	local C = C_Container
	local list, waiting = {}, 0
	if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then
		return list, waiting
	end
	local skills = {}
	local okS, s = pcall(ns.Gear.ReadProfessions)
	for line in pairs(okS and type(s) == "table" and s or {}) do
		skills[line] = true
	end
	local ctx = { level = Num(Call(UnitLevel, "player")) or 1, skills = skills, reagents = MyReagents(skills) }
	for bag = 0, Bags() do
		for slot = 1, Num(Call(C.GetContainerNumSlots, bag)) or 0 do
			local info = Call(C.GetContainerItemInfo, bag, slot)
			if type(info) == "table" and Num(info.itemID) then
				local verdict = Judge(bag, slot, info, ctx)
				if verdict == "attente" then
					waiting = waiting + 1
					if ns.Gear.RequestLoad then
						pcall(ns.Gear.RequestLoad, info.itemID)
					end
				elseif type(verdict) == "table" then
					local it = ns.Gear.Info(info.hyperlink or info.itemID) or {}
					local count = Num(info.stackCount) or 1
					local sellable = not True(info.hasNoValue) and (it.sell or 0) > 0
					list[#list + 1] = { bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink, name = it.name or "?",
						quality = it.quality, count = count, value = sellable and it.sell * count or 0, sellable = sellable,
						reason = verdict.reason, checked = verdict.checked }
				end
			end
		end
	end
	return list, waiting
end

-------------------------------------------------------------------------------
-- Vendre (marchand ouvert, ou au prochain) et détruire (ce qui ne se vend pas)
-------------------------------------------------------------------------------
local merchantOpen = false
local pending -- { [itemID] = nombre d'objets à vendre au prochain marchand }
local ticker

local function PiloteSellsGray()
	local ok, cfg = pcall(ns.Pilote.Config)
	return ok and type(cfg) == "table" and cfg.on and cfg.merchant ~= false or false
end

local function Still(entry)
	local info = Call(C_Container.GetContainerItemInfo, entry.bag, entry.slot)
	return type(info) == "table" and info.itemID == entry.itemID and not True(info.isLocked)
end

-- Vend `list` chez le marchand ouvert, un objet toutes les 0,2 s (le serveur n'aime pas les rafales).
function Sacs.SellNow(list, done)
	if not merchantOpen then
		return false
	end
	if ticker then
		ticker:Cancel()
	end
	local queue = {}
	for _, e in ipairs(list) do
		if e.sellable and not (e.quality == 0 and PiloteSellsGray()) then
			queue[#queue + 1] = e
		end
	end
	local i, sold, earned = 0, 0, 0
	ticker = C_Timer.NewTicker(SELL_STEP, function(t)
		i = i + 1
		local entry = queue[i]
		while entry and not Still(entry) do
			i = i + 1
			entry = queue[i]
		end
		if not entry or not merchantOpen then
			t:Cancel()
			ticker = nil
			if sold > 0 then
				ns.Print(string.format("sacs : %d objet(s) vendu(s) pour %s (rachetables chez ce marchand jusqu'à ta déconnexion).",
					sold, Money(earned)))
			end
			if done then
				pcall(done, sold)
			end
			return
		end
		Call(C_Container.UseContainerItem, entry.bag, entry.slot)
		sold, earned = sold + 1, earned + (entry.value or 0)
	end, #queue + 1)
	return true
end

-- Pas de marchand ouvert : on garde la liste pour le prochain ; le trajet ajoute un arrêt « Vendre ».
function Sacs.SellLater(list)
	pending = {}
	local n = 0
	for _, e in ipairs(list) do
		if e.sellable then
			pending[e.itemID] = (pending[e.itemID] or 0) + (e.count or 1)
			n = n + 1
		end
	end
	if n == 0 then
		pending = nil
		return 0
	end
	ns.Print(string.format("sacs : %d objet(s) à vendre au prochain marchand ; le trajet en ajoute un. (/iti sacs pour changer d'avis)", n))
	ns.RequestPlan("sacs", 0.3)
	return n
end

function Sacs.PendingCount()
	local n = 0
	for _ in pairs(pending or {}) do
		n = n + 1
	end
	return n
end

function Sacs.CancelPending()
	pending = nil
	ns.RequestPlan("sacs", 0.3)
end

-- Au marchand : ce qui était prévu (et qui est toujours jugé inutile) est vendu.
local function SellPending()
	if not pending then
		return
	end
	local list = {}
	for _, e in ipairs((Sacs.Analyse())) do
		if pending[e.itemID] then
			list[#list + 1] = e
		end
	end
	pending = nil
	if #list > 0 then
		Sacs.SellNow(list, function()
			ns.RequestPlan("sacs", 0.5)
			pcall(Sacs.Refresh)
		end)
	end
end

-- Détruit les objets cochés qui ne se vendent pas (au 2e clic du joueur). Rend le nombre tenté.
function Sacs.Destroy(list, done)
	local C = C_Container
	local tried = {}
	for _, e in ipairs(list) do
		if not e.sellable and Still(e) and C and C.PickupContainerItem and DeleteCursorItem then
			local ok = pcall(function()
				if CursorHasItem and CursorHasItem() then
					ClearCursor()
				end
				C.PickupContainerItem(e.bag, e.slot)
				DeleteCursorItem()
			end)
			if CursorHasItem and Call(CursorHasItem) then
				Call(ClearCursor) -- (refusé : on repose l'objet)
			end
			tried[#tried + 1] = { entry = e, ok = ok }
		end
	end
	C_Timer.After(1, function()
		local gone, stuck = 0, {}
		for _, t in ipairs(tried) do
			local info = Call(C.GetContainerItemInfo, t.entry.bag, t.entry.slot)
			if type(info) == "table" and info.itemID == t.entry.itemID then
				stuck[#stuck + 1] = t.entry.name
			else
				gone = gone + 1
			end
		end
		if gone > 0 then
			ns.Print("sacs : " .. gone .. " objet(s) sans valeur détruit(s).")
		end
		if #stuck > 0 then
			ns.Print("|cffff9933sacs : le jeu a refusé d'en détruire " .. #stuck .. "|r (" .. table.concat(stuck, ", ")
				.. ") : fais-le à la main (glisse l'objet hors du sac).")
		end
		if done then
			pcall(done)
		end
	end)
	return #tried
end

local events = CreateFrame("Frame")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
events:SetScript("OnEvent", function(_, event)
	if event == "MERCHANT_SHOW" then
		merchantOpen = true
		-- (Forever : la fenêtre du marchand s'affiche juste après l'événement ; le pilote vend d'abord le gris)
		C_Timer.After(0.6, function()
			if merchantOpen then
				SellPending()
				pcall(Sacs.Refresh)
			end
		end)
	else
		merchantOpen = false
		if ticker then
			ticker:Cancel()
			ticker = nil
		end
		pcall(Sacs.Refresh)
	end
end)

function Sacs.MerchantOpen()
	return merchantOpen
end

-------------------------------------------------------------------------------
-- Fenêtre « Vider mes sacs »
-------------------------------------------------------------------------------
local frame, intro, child, scroll, sell, destroy, all, footer
local rows, list, waiting = {}, {}, 0
local armed

local function Counts()
	local nSell, nDestroy, value = 0, 0, 0
	for _, e in ipairs(list) do
		if e.checked then
			if e.sellable then
				nSell, value = nSell + 1, value + (e.value or 0)
			else
				nDestroy = nDestroy + 1
			end
		end
	end
	return nSell, nDestroy, value
end

local function UpdateButtons()
	local nSell, nDestroy, value = Counts()
	if nSell > 0 then
		sell:SetText(merchantOpen and string.format("Vendre les %d coché(s) (~%s)", nSell, Money(value))
			or string.format("Vendre les %d coché(s) au prochain marchand", nSell))
	else
		sell:SetText(Sacs.PendingCount() > 0 and "Annuler la vente prévue" or "Rien à vendre de coché")
	end
	sell:SetEnabled(nSell > 0 or Sacs.PendingCount() > 0)
	if armed and GetTime() - armed <= CONFIRM_DELAY then
		destroy:SetText(string.format("|cffff5555Sûr ? Re-clique : détruire %d|r", nDestroy))
	else
		armed = nil
		destroy:SetText(nDestroy > 0 and string.format("Détruire les %d sans valeur", nDestroy) or "Rien à détruire")
	end
	destroy:SetEnabled(nDestroy > 0)
end

local function RowText(e)
	local box = e.checked and "|cff00ff00[x]|r " or "[  ] "
	local what = e.sellable and ("vendre ~" .. Money(e.value)) or "ne se vend pas : à détruire"
	return box .. tostring(e.link or e.name) .. (e.count > 1 and (" x" .. e.count) or "") .. "  |cff888888(" .. what .. ")|r"
		.. "\n     |cff999999" .. tostring(e.reason) .. "|r"
end

function Sacs.Refresh()
	if not (frame and frame:IsShown()) then
		return
	end
	list, waiting = Sacs.Analyse()
	armed = nil
	intro:SetText("Ce qui ne te sert pas ou plus, avec la raison. Coché d'office : le gris, l'équipement lié moins bon que le tien "
		.. "ou que ta classe ne porte pas. À toi de voir pour le reste. Jamais proposé : pierre de foyer, outils, objets de quête, "
		.. "améliorations (même pour plus tard), ce qui sert à tes métiers, sacs.")
	local y = 0
	for i, e in ipairs(list) do
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
			UpdateButtons()
		end)
		b:Show()
		y = y + 37
	end
	for i = #list + 1, #rows do
		rows[i]:Hide()
	end
	local notes = {}
	if #list == 0 then
		notes[#notes + 1] = "|cff66ff66Rien d'inutile dans tes sacs.|r"
	end
	if waiting > 0 then
		notes[#notes + 1] = "|cff888888" .. waiting .. " objet(s) pas encore chargé(s) par le jeu : la liste se complète dans un instant.|r"
		C_Timer.After(2, function()
			pcall(Sacs.Refresh)
		end)
	end
	if Sacs.PendingCount() > 0 then
		notes[#notes + 1] = "|cffffd100Vente prévue au prochain marchand : " .. Sacs.PendingCount() .. " objet(s).|r"
	end
	notes[#notes + 1] = "|cff888888Un objet vendu se rachète chez le même marchand (onglet Rachat) tant que tu ne te déconnectes pas.|r"
	footer:ClearAllPoints()
	footer:SetPoint("TOPLEFT", 2, -(y + 4))
	footer:SetText(table.concat(notes, "\n"))
	child:SetHeight(math.max(20, y + 8 + (footer:GetStringHeight() or 0)))
	UpdateButtons()
	ns.UI.Skin.Panel(frame, 0.97)
	ns.UI.Skin.HeaderColors(frame)
end

local function Checked()
	local out = {}
	for _, e in ipairs(list) do
		if e.checked then
			out[#out + 1] = e
		end
	end
	return out
end

local function Create()
	local Skin = ns.UI.Skin
	frame = CreateFrame("Frame", "ItineraireSacs", UIParent, "BackdropTemplate")
	frame:SetSize(600, 540)
	frame:SetPoint("CENTER", 20, 20)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "ItineraireSacs")
	Skin.Header(frame, "Vider mes sacs", "Interface\\Icons\\INV_Misc_Bag_08", 26)
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	intro = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	intro:SetPoint("TOPLEFT", 14, -34)
	intro:SetPoint("RIGHT", -14, 0)
	intro:SetJustifyH("LEFT")
	local ok, sf = pcall(CreateFrame, "ScrollFrame", "ItineraireSacsScroll", frame, "UIPanelScrollFrameTemplate")
	if not ok then
		sf = CreateFrame("ScrollFrame", nil, frame)
		sf:EnableMouseWheel(true)
		sf:SetScript("OnMouseWheel", function(self, delta)
			local max = self:GetVerticalScrollRange() or 0
			self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - delta * 40)))
		end)
	end
	scroll = sf
	scroll:SetPoint("TOPLEFT", 14, -86)
	scroll:SetPoint("BOTTOMRIGHT", -32, 46)
	child = CreateFrame("Frame", nil, scroll)
	child:SetSize(545, 20)
	scroll:SetScrollChild(child)
	footer = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	footer:SetWidth(540)
	footer:SetJustifyH("LEFT")
	footer:SetSpacing(2)
	all = Skin.Button(frame, "Tout cocher", 100, 24, function()
		local any = false
		for _, e in ipairs(list) do
			any = any or not e.checked
		end
		for i, e in ipairs(list) do
			e.checked = any
			rows[i]:SetText(RowText(e))
		end
		armed = nil
		UpdateButtons()
	end)
	all:SetPoint("BOTTOMLEFT", 12, 12)
	destroy = Skin.Button(frame, "", 190, 24, function()
		local _, nDestroy = Counts()
		if nDestroy == 0 then
			return
		end
		if not (armed and GetTime() - armed <= CONFIRM_DELAY) then
			armed = GetTime()
			UpdateButtons()
			C_Timer.After(CONFIRM_DELAY + 0.1, function()
				if frame:IsShown() then
					UpdateButtons()
				end
			end)
			return
		end
		armed = nil
		Sacs.Destroy(Checked(), function()
			Sacs.Refresh()
		end)
	end)
	destroy:SetPoint("BOTTOM", -20, 12)
	sell = Skin.Button(frame, "", 250, 24, function()
		local nSell = Counts()
		if nSell == 0 then
			if Sacs.PendingCount() > 0 then
				Sacs.CancelPending()
				ns.Print("sacs : vente prévue annulée.")
				Sacs.Refresh()
			end
			return
		end
		local chosen = Checked()
		if merchantOpen then
			Sacs.SellNow(chosen, function()
				Sacs.Refresh()
			end)
		else
			Sacs.SellLater(chosen)
			Sacs.Refresh()
		end
	end)
	sell:SetPoint("BOTTOMRIGHT", -12, 12)
	frame:Hide()
end

function Sacs.Toggle(show)
	if not frame then
		Create()
	end
	if show == nil then
		show = not frame:IsShown()
	end
	if show then
		frame:Show()
		Sacs.Refresh()
	else
		frame:Hide()
	end
end

function Sacs.Shown()
	return frame and frame:IsShown() or false
end
