-- Itinéraire : pilote automatique (« autopilot » des guides de montée de niveau), en restant dans ce que le jeu permet
-- aux addons :
--   - prendre et rendre les quêtes, choisir la récompense (option), confirmer les escortes ;
--   - les dialogues utiles selon l'étape (maître de vol, maître de classe, marchand) ;
--   - prendre le vol prévu par le trajet chez le maître de vol ;
--   - passer les cinématiques ;
--   - réparer et vendre les objets gris chez un marchand ;
--   - apprendre les techniques du maître de classe ;
--   - un bouton (avec raccourci clavier) pour l'objet de quête à utiliser maintenant.
-- Le personnage ne se déplace JAMAIS tout seul : le jeu l'interdit aux addons (et un programme qui le ferait serait un
-- bot). Maintenir MAJ (Shift) en parlant à un PNJ : le pilote ne touche à rien.
--
-- Prise et rendu des quêtes repris de Questdon (MIT, voir TIERS.txt), testés sur Forever : quêtes répétables, grises
-- (option) ou qui coûtent de l'or laissées au joueur, valeurs « secrètes » de Forever comptées comme « non ».
-- Si le jeu bloque une action (ADDON_ACTION_BLOCKED), la fonction concernée se coupe toute seule et le rapport le dit.
local _, ns = ...
local Pilote = {}
ns.Pilote = Pilote

local DEFAULTS = {
	on = true, accept = true, turnin = true, reward = false, grey = true, gossip = true, flights = true,
	cinematics = true, merchant = true, trainer = true, itemButton = true,
	-- Autonomie.lua : talents (« demander », « auto », « non »), plan (« auto » = selon ton rôle), équipement, sacs
	talents = "demander", talentPlan = "auto", equip = true, equipBoE = "demander", bags = true, actionbars = true,
}
Pilote.DEFAULTS = DEFAULTS
Pilote.log = {}
local blocked = {} -- [clé] = fonction bloquée par le jeu (cette session)

local function Call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
	if ok then
		return a, b, c, d, e, f, g, h
	end
	return nil
end

local function Num(v)
	local ok, n = pcall(function()
		return type(v) == "number" and v or nil
	end)
	return ok and n or nil
end

-- Vrai seulement pour un vrai « true » lisible (une valeur secrète de Forever compte pour « non »).
local function True(v)
	local ok, r = pcall(function()
		return v == true
	end)
	return ok and r or false
end

function Pilote.Config()
	if not ns.db then
		return DEFAULTS
	end
	if type(ns.db.pilote) ~= "table" then
		ns.db.pilote = {}
	end
	local cfg = ns.db.pilote
	for k, v in pairs(DEFAULTS) do
		if cfg[k] == nil then
			cfg[k] = v
		end
	end
	return cfg
end

-- La fonction `key` du pilote est-elle active maintenant ? (MAJ maintenue : non, pour tout ce qui touche aux PNJ)
local function Active(key, ignoreShift)
	local cfg = Pilote.Config()
	if not cfg.on or cfg[key] == false or blocked[key] then
		return false
	end
	if not ignoreShift and IsShiftKeyDown and Call(IsShiftKeyDown) then
		return false
	end
	return true
end
Pilote.Active = Active

local function Note(text)
	local log = Pilote.log
	log[#log + 1] = date("%H:%M:%S") .. " " .. text
	while #log > 15 do
		table.remove(log, 1)
	end
end

-------------------------------------------------------------------------------
-- Quêtes : prendre, rendre
-------------------------------------------------------------------------------
local function Repeatable(questID, flag)
	if True(flag) then
		return true
	end
	questID = Num(questID)
	if not questID then
		return false
	end
	return ns.Data.Flag("IsRepeatable", questID) or ns.Data.Flag("IsDailyQuest", questID)
end

local function LogFull()
	local n = 0
	for i = 1, Num(C_QuestLog and Call(C_QuestLog.GetNumQuestLogEntries)) or 0 do
		local info = Call(C_QuestLog.GetInfo, i)
		if type(info) == "table" and not info.isHeader and not info.isHidden then
			n = n + 1
		end
	end
	return n >= ns.Data.MaxQuests()
end

-- Une quête que tu as « passée » dans Itinéraire (clic droit > Passer) : le pilote ne la prend pas.
local function SkippedByPlayer(questID)
	local skipped = ns.session and ns.session.skipped or {}
	return questID and skipped["P:" .. questID] and true or false
end

local function Trivial(flag)
	return flag ~= nil and (True(flag) or not pcall(function()
		return flag == true
	end))
end

local function CostsGold()
	local money = Num(GetQuestMoneyToGet and Call(GetQuestMoneyToGet)) or 0
	return money > 0
end

local function OnGossip()
	if not C_GossipInfo then
		return
	end
	if Active("turnin") and C_GossipInfo.GetActiveQuests then
		for _, q in ipairs(Call(C_GossipInfo.GetActiveQuests) or {}) do
			local id = type(q) == "table" and True(q.isComplete) and Num(q.questID)
			if id and id > 0 and not Repeatable(id, q.repeatable) then
				Note("rendre " .. id)
				Call(C_GossipInfo.SelectActiveQuest, id)
				return
			end
		end
	end
	if Active("accept") and C_GossipInfo.GetAvailableQuests and not LogFull() then
		local cfg = Pilote.Config()
		for _, q in ipairs(Call(C_GossipInfo.GetAvailableQuests) or {}) do
			local id = type(q) == "table" and Num(q.questID)
			if id and id > 0 and not True(q.isIgnored) and not Repeatable(id, q.repeatable) and not SkippedByPlayer(id)
				and not (cfg.grey and Trivial(q.isTrivial)) then
				Note("prendre " .. id)
				Call(C_GossipInfo.SelectAvailableQuest, id)
				return
			end
		end
	end
	Pilote.UsefulGossip()
end

local function OnGreeting()
	if Active("turnin") then
		for i = 1, Num(Call(GetNumActiveQuests)) or 0 do
			local _, complete = Call(GetActiveTitle, i)
			if True(complete) and not Repeatable(Call(GetActiveQuestID, i)) then
				Note("rendre (liste) " .. i)
				Call(SelectActiveQuest, i)
				return
			end
		end
	end
	if Active("accept") and not LogFull() then
		local cfg = Pilote.Config()
		for i = 1, Num(Call(GetNumAvailableQuests)) or 0 do
			local isTrivial, _, isRepeat, _, id = Call(GetAvailableQuestInfo, i)
			if not (cfg.grey and Trivial(isTrivial)) and not Repeatable(id, isRepeat) and not SkippedByPlayer(Num(id)) then
				Note("prendre (liste) " .. i)
				Call(SelectAvailableQuest, i)
				return
			end
		end
	end
end

local function OnDetail()
	if not Active("accept") then
		return
	end
	local id = Num(Call(GetQuestID))
	if QuestGetAutoAccept and True(Call(QuestGetAutoAccept)) then
		Call(AcknowledgeAutoAcceptQuest)
		return
	end
	if SkippedByPlayer(id) then
		return
	end
	if Pilote.Config().grey and id and C_QuestLog and C_QuestLog.IsQuestTrivial and True(Call(C_QuestLog.IsQuestTrivial, id)) then
		return -- grise : à toi de voir
	end
	if LogFull() then
		ns.Print("pilote : journal de quêtes plein, quête pas prise.")
		return
	end
	Note("accepter " .. tostring(id))
	Call(AcceptQuest)
end

local function OnProgress()
	if not Active("turnin") or not True(Call(IsQuestCompletable)) then
		return
	end
	if Repeatable(Call(GetQuestID)) or CostsGold() then
		return -- répétable ou payante : à toi
	end
	Note("terminer " .. tostring(Call(GetQuestID)))
	Call(CompleteQuest)
end

local function OnComplete()
	if not Active("turnin") then
		return
	end
	if Repeatable(Call(GetQuestID)) or CostsGold() then
		return
	end
	local choices = Num(Call(GetNumQuestChoices)) or 0
	if choices <= 1 then
		Note("récompense (seule) " .. tostring(Call(GetQuestID)))
		Call(GetQuestReward, choices)
	end
	-- plusieurs récompenses : Gear.Advise conseille, puis Pilote.OnRewardChoice prend (si l'option est active)
end

-- Appelé par Gear quand la récompense conseillée est connue.
function Pilote.OnRewardChoice(choice)
	if not (choice and Active("turnin") and Active("reward")) then
		return
	end
	if Repeatable(Call(GetQuestID)) or CostsGold() then
		return
	end
	local index = choice.index
	C_Timer.After(0.4, function()
		if (Num(Call(GetNumQuestChoices)) or 0) >= index and not (IsShiftKeyDown and Call(IsShiftKeyDown)) then
			Note("récompense choisie " .. tostring(choice.item and choice.item.link))
			Call(GetQuestReward, index)
		end
	end)
end

-------------------------------------------------------------------------------
-- Dialogues utiles selon l'étape : vol, maître de classe, marchand
-------------------------------------------------------------------------------
local ICON_KIND = { [132057] = "taxi", [132058] = "trainer", [132060] = "vendor" }

local function OptionKind(option)
	if type(option) ~= "table" then
		return nil
	end
	local icon = option.icon
	if Num(icon) and ICON_KIND[icon] then
		return ICON_KIND[icon]
	end
	if type(icon) == "string" then
		local lower = icon:lower()
		return lower:find("taxi") and "taxi" or lower:find("trainer") and "trainer" or lower:find("vendor") and "vendor" or nil
	end
	local kind = type(option.type) == "string" and option.type:lower() or nil
	return (kind == "taxi" or kind == "trainer" or kind == "vendor") and kind or nil
end

function Pilote.UsefulGossip()
	if not (Active("gossip") and C_GossipInfo and C_GossipInfo.GetOptions) then
		return
	end
	local want = {}
	if Pilote.FlightTarget() then
		want.taxi = true
	end
	local first = ns.plan and ns.plan.order and ns.plan.order[1]
	local service = first and first.kind == "service" and first.service
	if service and service.kind == "trainer" then
		want.trainer = true
	elseif service and service.kind == "repair" then
		want.vendor = true
	end
	if not next(want) then
		return
	end
	for _, option in ipairs(Call(C_GossipInfo.GetOptions) or {}) do
		local kind = OptionKind(option)
		local id = Num(option.gossipOptionID)
		if kind and want[kind] and id then
			Note("dialogue : " .. kind)
			Call(C_GossipInfo.SelectOption, id)
			return
		end
	end
end

-------------------------------------------------------------------------------
-- Vols : le vol prévu par Shortest Path pour le trajet d'Itinéraire
-------------------------------------------------------------------------------
-- Destination du prochain vol du trajet en cours (point {map, x, y, wx, wy}) ou nil.
function Pilote.FlightTarget()
	local api = ns.Geo.SPApi and ns.Geo.SPApi()
	if not (api and api.Journey) then
		return nil
	end
	local journey = Call(api.Journey)
	if type(journey) ~= "table" or journey.owner ~= ns.OWNER or type(journey.legs) ~= "table" then
		return nil
	end
	local leg = journey.legs[1]
	if leg and leg.mode == "walk" then
		leg = journey.legs[2]
	end
	local to = leg and leg.mode == "flight" and type(leg.to) == "table" and leg.to
	if not (to and Num(to.map) and Num(to.x) and Num(to.y)) then
		return nil
	end
	local wx, wy, inst = ns.Geo.World(to.map, to.x, to.y)
	if not wx then
		return nil
	end
	return { map = to.map, x = to.x, y = to.y, wx = wx, wy = wy, inst = inst, text = leg.text }
end

local function Reachable(slot, state)
	if state ~= nil then
		local reach = Enum and Enum.FlightPathState and Enum.FlightPathState.Reachable
		if reach ~= nil then
			return state == reach
		end
	end
	return Call(TaxiNodeGetType, slot) == "REACHABLE"
end

-- Les nœuds du maître de vol : { slot, name, wx, wy, inst, reachable }.
function Pilote.TaxiNodes()
	local nodes = {}
	local map = Num(GetTaxiMapID and Call(GetTaxiMapID))
	if map and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes then
		for _, n in ipairs(Call(C_TaxiMap.GetAllTaxiNodes, map) or {}) do
			local x, y
			local pos = type(n) == "table" and n.position
			if type(pos) == "table" then
				x, y = Num(pos.x), Num(pos.y)
				if not x and pos.GetXY then
					x, y = Call(pos.GetXY, pos)
				end
			end
			local slot = Num(n.slotIndex)
			local wx, wy, inst
			if x and y then
				wx, wy, inst = ns.Geo.World(map, x, y) -- (pas « x and World() » : ça ne garderait que wx)
			end
			if slot and wx then
				nodes[#nodes + 1] = { slot = slot, name = n.name, wx = wx, wy = wy, inst = inst, reachable = Reachable(slot, n.state) }
			end
		end
	end
	if #nodes == 0 and NumTaxiNodes then
		for slot = 1, Num(Call(NumTaxiNodes)) or 0 do
			local x, y = Call(TaxiNodePosition, slot)
			local wx, wy, inst
			if map and Num(x) and Num(y) then
				wx, wy, inst = ns.Geo.World(map, x, y)
			end
			if wx then
				nodes[#nodes + 1] = { slot = slot, name = Call(TaxiNodeName, slot), wx = wx, wy = wy, inst = inst,
					reachable = Reachable(slot) }
			end
		end
	end
	return nodes
end

local function OnTaxiMap()
	if not Active("flights") then
		return
	end
	local target = Pilote.FlightTarget()
	if not target then
		return
	end
	local best, bestD
	for _, n in ipairs(Pilote.TaxiNodes()) do
		local d = n.reachable and ns.Geo.Yards(n, target)
		if d and (not bestD or d < bestD) then
			best, bestD = n, d
		end
	end
	if not best or bestD > 300 then
		return -- pas sûr de la destination : à toi de choisir
	end
	C_Timer.After(0.3, function()
		if IsShiftKeyDown and Call(IsShiftKeyDown) then
			return
		end
		Note("vol vers " .. tostring(best.name))
		ns.Print("pilote : vol vers " .. tostring(best.name) .. ".")
		Call(TakeTaxiNode, best.slot)
	end)
end

-------------------------------------------------------------------------------
-- Cinématiques
-------------------------------------------------------------------------------
local function OnCinematic()
	if not Active("cinematics", true) then
		return
	end
	C_Timer.After(0.2, function()
		Note("cinématique passée")
		if rawget(_G, "CinematicFrame_CancelCinematic") then
			Call(CinematicFrame_CancelCinematic)
		elseif rawget(_G, "StopCinematic") then
			Call(StopCinematic)
		end
	end)
end

local function OnMovie()
	if not Active("cinematics", true) then
		return
	end
	C_Timer.After(0.2, function()
		local frame = rawget(_G, "MovieFrame")
		if frame and frame.StopMovie and Call(frame.IsShown, frame) then
			Note("vidéo passée")
			Call(frame.StopMovie, frame)
		elseif rawget(_G, "GameMovieFinished") then
			Call(GameMovieFinished)
		end
	end)
end

-------------------------------------------------------------------------------
-- Marchand : réparer, vendre les objets gris (un par un, comme Questdon : rien de perdu si un sac bouge)
-------------------------------------------------------------------------------
local JUNK_ADDONS = { "Scrap", "AutoVendor", "Peddler", "SellJunk", "Vendor", "LeatrixPlus", "Leatrix_Plus" }
local merchantOpen = false
local sellTicker

local function Loaded(name)
	local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
	return fn and Call(fn, name) and true or false
end

-- Un autre addon le fait déjà ? (on lui laisse : jamais deux ventes en même temps)
local function OtherMerchantAddon()
	for _, name in ipairs(JUNK_ADDONS) do
		if Loaded(name) then
			return name
		end
	end
	local qd = rawget(_G, "QuestdonDB")
	if Loaded("Questdon") and type(qd) == "table" and (qd.autoRepair or qd.sellJunk or qd.autoSellJunk) then
		return "Questdon"
	end
	return nil
end

local function Repair()
	if not (CanMerchantRepair and Call(CanMerchantRepair)) then
		return
	end
	local cost, needed = Call(GetRepairAllCost)
	cost = Num(cost) or 0
	if not True(needed) or cost <= 0 then
		return
	end
	if (Num(Call(GetMoney)) or 0) >= cost then
		Note("réparation " .. cost)
		Call(RepairAllItems)
		ns.Print("pilote : réparé pour " .. ns.Gear.Money(cost) .. ".")
	else
		ns.Print("pilote : pas assez d'or pour réparer (" .. ns.Gear.Money(cost) .. ").")
	end
end

local function Junk()
	local list = {}
	local C = C_Container
	if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then
		return list
	end
	for bag = 0, 4 do
		for slot = 1, Num(Call(C.GetContainerNumSlots, bag)) or 0 do
			local info = Call(C.GetContainerItemInfo, bag, slot)
			if type(info) == "table" and info.quality == 0 and not True(info.hasNoValue) and not True(info.isLocked) then
				local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
				local ok, _, _, _, _, _, _, _, _, _, _, sell = pcall(fn, info.itemID) -- (11e valeur : prix de vente)
				sell = ok and sell or 0
				list[#list + 1] = { bag = bag, slot = slot, itemID = info.itemID, value = (Num(sell) or 0) * (Num(info.stackCount) or 1) }
			end
		end
	end
	return list
end

local function StillJunk(entry)
	local info = Call(C_Container.GetContainerItemInfo, entry.bag, entry.slot)
	return type(info) == "table" and info.itemID == entry.itemID and info.quality == 0 and not True(info.isLocked)
end

local function SellJunk()
	local list = Junk()
	if #list == 0 then
		return
	end
	if sellTicker then
		sellTicker:Cancel()
	end
	local i, sold, earned = 0, 0, 0
	sellTicker = C_Timer.NewTicker(0.15, function(t)
		i = i + 1
		local entry = list[i]
		while entry and not StillJunk(entry) do
			i = i + 1
			entry = list[i]
		end
		if not entry or not merchantOpen then
			t:Cancel()
			sellTicker = nil
			if sold > 0 then
				ns.Print("pilote : " .. sold .. " objet(s) gris vendu(s) pour " .. ns.Gear.Money(earned) .. ".")
			end
			return
		end
		Call(C_Container.UseContainerItem, entry.bag, entry.slot)
		sold, earned = sold + 1, earned + entry.value
	end, #list + 1)
	Note("vente des objets gris (" .. #list .. ")")
end

local function OnMerchant()
	if not Active("merchant", true) then
		return
	end
	local other = OtherMerchantAddon()
	if other then
		if not Pilote.saidOther then
			Pilote.saidOther = true
			ns.Print("pilote : " .. other .. " s'occupe déjà de réparer / vendre, Itinéraire le laisse faire.")
		end
		return
	end
	-- (Forever : la fenêtre du marchand n'est pas encore affichée à MERCHANT_SHOW ; on attend un peu)
	C_Timer.After(0.3, function()
		if merchantOpen then
			Repair()
			SellJunk()
		end
	end)
end

-------------------------------------------------------------------------------
-- Maître de classe : apprendre tout ce qui est disponible (un par un)
-------------------------------------------------------------------------------
local function OnTrainer()
	if not Active("trainer") or (IsTradeskillTrainer and Call(IsTradeskillTrainer)) then
		return
	end
	C_Timer.After(0.3, function()
		local list = {}
		for i = 1, Num(Call(GetNumTrainerServices)) or 0 do
			local name, _, category = Call(GetTrainerServiceInfo, i)
			if category == "available" then
				list[#list + 1] = { index = i, name = name, cost = Num(Call(GetTrainerServiceCost, i)) or 0 }
			end
		end
		if #list == 0 then
			return
		end
		-- de la dernière à la première : les numéros des suivantes ne bougent pas quand une technique est apprise
		table.sort(list, function(a, b)
			return a.index > b.index
		end)
		local learned, spent, k = {}, 0, 0
		C_Timer.NewTicker(0.3, function(t)
			k = k + 1
			local s = list[k]
			if not s then
				t:Cancel()
				if #learned > 0 then
					ns.Print("pilote : appris " .. table.concat(learned, ", ") .. " (" .. ns.Gear.Money(spent) .. ").")
				end
				return
			end
			if (Num(Call(GetMoney)) or 0) >= s.cost then
				Call(BuyTrainerService, s.index)
				learned[#learned + 1] = tostring(s.name)
				spent = spent + s.cost
			end
		end, #list + 1)
		Note("maître : " .. #list .. " technique(s)")
	end)
end

-------------------------------------------------------------------------------
-- Bouton de l'objet de quête (cadre sécurisé : changé seulement hors combat)
-------------------------------------------------------------------------------
local button, pendingButton

local function QuestSourceItems(questID)
	local set = {}
	local quest = ns.Data.Quest(questID)
	for _, id in ipairs(type(quest) == "table" and type(quest.requiredSourceItems) == "table" and quest.requiredSourceItems or {}) do
		set[id] = true
	end
	return set
end

-- L'objet de quête à utiliser maintenant : { itemID, bag, slot } ou nil.
function Pilote.QuestItem()
	local C = C_Container
	if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then
		return nil
	end
	local weight = {}
	local order = ns.plan and ns.plan.order or {}
	for k = 1, math.min(3, #order) do
		for _, q in ipairs(order[k].quests or {}) do
			for id in pairs(QuestSourceItems(q.id)) do
				weight[id] = math.max(weight[id] or 0, k == 1 and 3 or 2)
			end
		end
	end
	for _, q in ipairs(ns.plan and ns.plan.quests or {}) do
		for id in pairs(QuestSourceItems(q.id)) do
			weight[id] = math.max(weight[id] or 0, 1)
		end
	end
	local best, bestW
	local spellOf = (C_Item and C_Item.GetItemSpell) or rawget(_G, "GetItemSpell")
	for bag = 0, 4 do
		for slot = 1, Num(Call(C.GetContainerNumSlots, bag)) or 0 do
			local info = Call(C.GetContainerItemInfo, bag, slot)
			local id = type(info) == "table" and Num(info.itemID)
			if id and Call(spellOf, id) then
				local w = weight[id]
				if not w then
					local quest = C.GetContainerItemQuestInfo and Call(C.GetContainerItemQuestInfo, bag, slot)
					if type(quest) == "table" and Num(quest.questID) and not True(quest.isActive) then
						w = 0.5 -- un objet qui commence une quête
					end
				end
				if w and (not bestW or w > bestW) then
					best, bestW = { itemID = id, bag = bag, slot = slot, icon = info.iconFileID }, w
				end
			end
		end
	end
	return best
end

local function UpdateButton()
	if not button then
		return
	end
	if InCombatLockdown and InCombatLockdown() then
		pendingButton = true
		return
	end
	pendingButton = false
	local item = Active("itemButton", true) and Pilote.QuestItem()
	if item then
		button:SetAttribute("type", "item")
		button:SetAttribute("item", "item:" .. item.itemID)
		button.itemID = item.itemID
		button.icon:SetTexture(item.icon or (C_Item and C_Item.GetItemIconByID and Call(C_Item.GetItemIconByID, item.itemID))
			or "Interface\\Icons\\INV_Misc_QuestionMark")
		local count = Num((C_Item and C_Item.GetItemCount and Call(C_Item.GetItemCount, item.itemID)) or Call(GetItemCount, item.itemID)) or 0
		button.count:SetText(count > 1 and count or "")
		local key = GetBindingKey and Call(GetBindingKey, "CLICK ItineraireItemButton:LeftButton")
		button.hotkey:SetText(type(key) == "string" and key:gsub("SHIFT%-", "s-"):gsub("CTRL%-", "c-"):gsub("ALT%-", "a-") or "")
		local start, duration = Call((C_Container and C_Container.GetItemCooldown) or rawget(_G, "GetItemCooldown"), item.itemID)
		if Num(start) and Num(duration) and duration > 0 then
			button.cooldown:SetCooldown(start, duration)
		end
		button:Show()
	else
		button.itemID = nil
		button:Hide()
	end
end
Pilote.UpdateButton = UpdateButton

local function SavePosition()
	local point, _, rel, x, y = button:GetPoint()
	ns.db.ui.itemButtonPos = { point, rel, x, y }
end

function Pilote.CreateButton()
	if button then
		return button
	end
	button = CreateFrame("Button", "ItineraireItemButton", UIParent, "SecureActionButtonTemplate")
	button:SetSize(42, 42)
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetMovable(true)
	button:RegisterForDrag("LeftButton")
	button:SetClampedToScreen(true)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.border = button:CreateTexture(nil, "OVERLAY")
	button.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	button.border:SetBlendMode("ADD")
	button.border:SetVertexColor(1, 0.82, 0)
	button.border:SetPoint("CENTER")
	button.border:SetSize(76, 76)
	button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	button.count:SetPoint("BOTTOMRIGHT", -2, 2)
	-- le raccourci clavier choisi, en petit en haut à gauche (comme sur les barres d'action)
	button.hotkey = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
	button.hotkey:SetPoint("TOPLEFT", 3, -3)
	if ns.UI and ns.UI.Skin then
		ns.UI.Skin.Border(button, 0, 0, 0, 1)
	end
	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.cooldown:SetAllPoints()
	button:SetScript("OnDragStart", function(self)
		if IsShiftKeyDown() and not InCombatLockdown() then
			self:StartMoving()
		end
	end)
	button:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.itemID and GameTooltip.SetItemByID then
			pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID)
		end
		GameTooltip:AddLine("Itinéraire : objet de quête à utiliser (raccourci : Échap > Options > Raccourcis > Itinéraire). MAJ + glisser : déplacer.", 0.6, 0.8, 1, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	local pos = ns.db and ns.db.ui and ns.db.ui.itemButtonPos
	if type(pos) == "table" and Num(pos[3]) and Num(pos[4]) then
		button:SetPoint(pos[1] or "CENTER", UIParent, pos[2] or "CENTER", pos[3], pos[4])
	else
		button:SetPoint("TOP", UIParent, "TOP", -190, -150)
	end
	button:Hide()
	return button
end

-------------------------------------------------------------------------------
-- Questie : une seule main sur les quêtes
-------------------------------------------------------------------------------
-- Quand le pilote prend et rend les quêtes, ceux de Questie sont coupés (sinon deux addons cliquent en même temps) ;
-- remis comme avant si le pilote s'arrête.
function Pilote.SyncQuestie()
	local Ext = ns.Options and ns.Options.Ext
	if not Ext then
		return
	end
	local cfg = Pilote.Config()
	local mine = cfg.on and (cfg.accept or cfg.turnin)
	if mine then
		local accept, complete = Ext.GetQuestie("autoaccept"), Ext.GetQuestie("autocomplete")
		if accept or complete then
			cfg.questiePrev = { autoaccept = accept, autocomplete = complete }
			Ext.SetQuestie("autoaccept", false)
			Ext.SetQuestie("autocomplete", false)
			ns.Print("pilote : il prend et rend les quêtes lui-même, les réglages automatiques de Questie sont coupés"
				.. " (remis si tu arrêtes le pilote).")
		end
	elseif type(cfg.questiePrev) == "table" then
		Ext.SetQuestie("autoaccept", cfg.questiePrev.autoaccept and true or false)
		Ext.SetQuestie("autocomplete", cfg.questiePrev.autocomplete and true or false)
		cfg.questiePrev = nil
	end
end

function Pilote.SetOn(on)
	Pilote.Config().on = on and true or false
	Pilote.SyncQuestie()
	UpdateButton()
	ns.Print("pilote automatique " .. (on and "|cff00ff00activé|r (MAJ en parlant à un PNJ : tu reprends la main)" or "arrêté") .. ".")
	if ns.UI and ns.UI.SetPilote then
		ns.UI.SetPilote(on)
	end
end

-------------------------------------------------------------------------------
-- Actions bloquées par le jeu : la fonction se coupe toute seule
-------------------------------------------------------------------------------
local FUNC_KEY = {
	TakeTaxiNode = "flights", CinematicFrame_CancelCinematic = "cinematics", StopCinematic = "cinematics",
	StopMovie = "cinematics", RepairAllItems = "merchant", UseContainerItem = "merchant", BuyTrainerService = "trainer",
	AcceptQuest = "accept", CompleteQuest = "turnin", GetQuestReward = "turnin", SelectOption = "gossip",
	LearnTalent = "talents", EquipItemByName = "equip", EquipCursorItem = "equip", EquipPendingItem = "equip",
	PickupContainerItem = "bags", PutItemInBag = "bags", PlaceAction = "actionbars", PickupSpell = "actionbars",
}

local function OnBlocked(addon, func)
	if addon ~= "Itineraire" and addon ~= ns.OWNER then
		return
	end
	func = tostring(func or "")
	-- (« TakeTaxiNode() », « C_Container.UseContainerItem() » : le dernier nom, sans les parenthèses)
	local name = (func:gsub("%(.*%)", "")):match("([%w_]+)$") or func
	local key = FUNC_KEY[name] or "itemButton"
	if blocked[key] then
		return
	end
	blocked[key] = func
	Note("BLOQUÉ par le jeu : " .. func)
	ns.Print("pilote : le jeu a bloqué « " .. func .. " » : cette partie du pilote est coupée pour la session"
		.. " (le reste continue). /iti rapport pour les détails.")
end

-------------------------------------------------------------------------------
-- Événements
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
local HANDLERS = {
	GOSSIP_SHOW = OnGossip, QUEST_GREETING = OnGreeting, QUEST_DETAIL = OnDetail, QUEST_PROGRESS = OnProgress,
	QUEST_COMPLETE = OnComplete, TAXIMAP_OPENED = OnTaxiMap, CINEMATIC_START = OnCinematic, PLAY_MOVIE = OnMovie,
	TRAINER_SHOW = OnTrainer,
	QUEST_ACCEPT_CONFIRM = function()
		if Active("accept") and not LogFull() then
			Note("escorte acceptée")
			Call(ConfirmAcceptQuest)
		end
	end,
	MERCHANT_SHOW = function()
		merchantOpen = true
		OnMerchant()
	end,
	MERCHANT_CLOSED = function()
		merchantOpen = false
	end,
	ADDON_ACTION_BLOCKED = OnBlocked,
	ADDON_ACTION_FORBIDDEN = OnBlocked,
	BAG_UPDATE_DELAYED = function()
		UpdateButton()
	end,
	UPDATE_BINDINGS = function()
		UpdateButton() -- (le raccourci affiché sur le bouton)
	end,
	PLAYER_REGEN_ENABLED = function()
		if pendingButton then
			UpdateButton()
		end
	end,
}
for event in pairs(HANDLERS) do
	pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...)
	local fn = HANDLERS[event]
	if not (fn and ns.ready) then
		return
	end
	local ok, err = pcall(fn, ...)
	if not ok and ns.OnError then
		ns.OnError("pilote (" .. event .. ") : " .. tostring(err))
	end
end)

-- Au démarrage (Questie prêt) et après chaque calcul du trajet.
function Pilote.Init()
	local cfg = Pilote.Config()
	if ns.Auto and ns.Auto.Init then
		pcall(ns.Auto.Init)
	end
	Pilote.CreateButton()
	Pilote.SyncQuestie()
	UpdateButton()
	if ns.UI and ns.UI.SetPilote then
		ns.UI.SetPilote(cfg.on)
	end
end

function Pilote.OnPlan()
	UpdateButton()
end

function Pilote.ReportLine()
	local cfg = Pilote.Config()
	local parts = {}
	for _, key in ipairs({ "accept", "turnin", "reward", "gossip", "flights", "cinematics", "merchant", "trainer", "itemButton",
		"talents", "equip", "bags", "actionbars" }) do
		local v = cfg[key]
		parts[#parts + 1] = key .. (blocked[key] and "=BLOQUÉ" or type(v) == "string" and ("=" .. v) or (v and "" or "=non"))
	end
	return "Pilote : " .. (cfg.on and "ACTIF" or "arrêté") .. " · " .. table.concat(parts, " ")
		.. (button and rawget(button, "itemID") and (" · objet " .. rawget(button, "itemID")) or "")
		.. (#Pilote.log > 0 and ("\n  dernières actions : " .. table.concat(Pilote.log, " | ")) or "")
end
