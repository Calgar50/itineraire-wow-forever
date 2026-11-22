-- Vider mes sacs (3.2.0) : ce qui ne sert pas ou plus, avec la raison ; jamais la pierre de foyer, les outils, les
-- objets de quête, les améliorations ni ce qui sert à tes métiers ; vente au prochain marchand (le trajet en ajoute
-- un), destruction au 2e clic et seulement pour ce qui ne se vend pas.
dofile(TESTS .. "/wow_mock.lua")
NOW = 1800000000
time = function() return NOW end
date = function(fmt, t) return os.date(fmt, t or NOW) end
function UnitLevel() return 25 end
function UnitClass() return "Guerrier", "WARRIOR" end
C_QuestLog.GetMaxNumQuestsCanAccept = function() return 25 end
NPCS[9] = { id = 9, name = "Sergra", spawns = { [17] = { { 52.2, 31.0 } } }, friendly = true }
NPCS[801] = { id = 801, name = "Marchand de la Croisée", spawns = { [17] = { { 51.8, 29.9 } } }, friendly = true }
TOWNSFOLK = { townsfolk = { Repair = { 801 }, Innkeeper = {} }, classSpecificTownsfolk = {} }
local importModule = QuestieLoader.ImportModule
QuestieLoader.ImportModule = function(self, name)
	if name == "Townsfolk" then return TOWNSFOLK end
	return importModule(self, name)
end
LOG[1] = { info = { questID = 1500, title = "À rendre", level = 25, suggestedGroup = 0 }, objectives = {}, complete = true }
QUESTS[1500] = { Id = 1500, name = "À rendre", level = 25, xp = 2000, Finisher = { NPC = { 9 } } }

-- Le sac (sac à dos seulement) et les objets
local BAG = {}
local function put(slot, id, opts)
	opts = opts or {}
	BAG[slot] = { itemID = id, stackCount = opts.count or 1, quality = opts.quality or 1, hasNoValue = opts.noValue or false,
		isBound = opts.bound or false, hyperlink = "item:" .. id, isLocked = false, quest = opts.quest }
end
ITEMS = {}
local function item(id, name, quality, classID, subclassID, extra)
	extra = extra or {}
	ITEMS[id] = { name = name, link = "item:" .. id, quality = quality, req = extra.req or 0, equipLoc = extra.equipLoc or "",
		sell = extra.sell or 25, classID = classID, subclassID = subclassID }
end
item(6948, "Pierre de foyer", 1, 15, 0, { sell = 0 }); put(1, 6948)
item(2901, "Pioche de mineur", 1, 2, 14, { equipLoc = "INVTYPE_WEAPON" }); put(2, 2901)
item(100, "Os ébréché", 0, 15, 0, { sell = 50 }); put(3, 100, { quality = 0, count = 3 })
item(200, "Brassards usés", 2, 4, 4, { equipLoc = "INVTYPE_WRIST", sell = 120 }); put(4, 200, { quality = 2, bound = true })
item(201, "Bottes vertes", 2, 4, 4, { equipLoc = "INVTYPE_FEET", sell = 300 }); put(5, 201, { quality = 2 })
item(202, "Casque pour plus tard", 2, 4, 4, { equipLoc = "INVTYPE_HEAD", req = 28 }); put(6, 202, { quality = 2, bound = true })
item(203, "Robe de mage", 1, 4, 1, { equipLoc = "INVTYPE_ROBE", sell = 40 }); put(7, 203, { bound = true })
item(204, "Grande hache", 1, 2, 1, { equipLoc = "INVTYPE_2HWEAPON", sell = 80 }); put(8, 204, { bound = true })
item(300, "Pain dur", 1, 0, 5, { req = 5, sell = 1 }); put(9, 300, { count = 10 })
item(2840, "Barre de cuivre", 1, 7, 7, { sell = 10 }); put(10, 2840, { count = 12 })
item(2770, "Minerai de cuivre", 1, 7, 7, { sell = 5 }); put(11, 2770, { count = 8 })
item(2589, "Étoffe de lin", 1, 7, 5, { sell = 2 }); put(12, 2589, { count = 9 })
item(400, "Lettre scellée", 1, 12, 0, { sell = 0 }); put(13, 400, { quest = true })
item(500, "Caillou sans valeur", 0, 15, 0, { sell = 0 }); put(14, 500, { quality = 0, noValue = true })
item(600, "Patron : chemise de lin", 1, 9, 2, { sell = 20 }); put(15, 600)
item(601, "Plans : ceinture en cuivre", 1, 9, 4, { sell = 20 }); put(16, 601)
EVAL = {
	[200] = { gain = -5, pct = -12, slot = 9 }, [201] = { gain = -2, pct = -4, slot = 8 }, [202] = { gain = 10, pct = 20, slot = 1 },
	[203] = false, [204] = false,
}
WHY = { [203] = "ta classe ne peut pas le porter", [204] = "arme à deux mains (un tank garde son bouclier)",
	[2901] = "pas un équipement" }

MERCHANT, SOLD, DELETED, CURSOR = false, {}, {}, nil
C_Container = {
	GetContainerNumSlots = function(bag) return bag == 0 and 20 or 0 end,
	GetContainerNumFreeSlots = function(bag)
		if bag ~= 0 then return 0, 0 end
		local n = 0
		for s = 1, 20 do if not BAG[s] then n = n + 1 end end
		return n, 0
	end,
	GetContainerItemInfo = function(bag, slot)
		local e = bag == 0 and BAG[slot]
		if not e then return nil end
		local copy = {}
		for k, v in pairs(e) do copy[k] = v end
		return copy
	end,
	GetContainerItemQuestInfo = function(bag, slot)
		local e = bag == 0 and BAG[slot]
		return { isQuestItem = e and e.quest or false }
	end,
	UseContainerItem = function(bag, slot)
		if MERCHANT and BAG[slot] then
			SOLD[#SOLD + 1] = BAG[slot].itemID
			BAG[slot] = nil
		end
	end,
	PickupContainerItem = function(bag, slot) CURSOR = slot end,
}
function CursorHasItem() return CURSOR ~= nil end
function ClearCursor() CURSOR = nil end
function DeleteCursorItem()
	if CURSOR and BAG[CURSOR] then
		DELETED[#DELETED + 1] = BAG[CURSOR].itemID
		BAG[CURSOR] = nil
	end
	CURSOR = nil
end

PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.52, 0.31
local ns = LoadAddon(ADDON_DIR, { "Solver.lua", "Geo.lua", "Data.lua", "Planner.lua", "Guide.lua", "UI.lua", "Options.lua",
	"Group.lua", "Gear.lua", "GearUI.lua", "Pilote.lua", "Autonomie.lua", "Montee.lua", "MonteeUI.lua", "Controle.lua",
	"Tri.lua", "Sacs.lua", "Core.lua" })
ns.ext = { RECETTES = {
	[2663] = { 164, 0, "t", 0, 2853, 1, "2840:2", 4, 3, "", "", 2 },
	[2657] = { 186, 0, "t", 0, 2840, 1, "2770:1", 7, 7, "", "", 0 },
} }
Fire("ADDON_LOADED", "Itineraire")
Fire("PLAYER_LOGIN")
Advance(5)
-- Équipement et métiers simulés (forge + minage)
ns.Gear.Info = function(it)
	local id = tonumber(tostring(it):match("(%d+)"))
	return ITEMS[id]
end
ns.Gear.Evaluate = function(it, opts)
	local id = tonumber(tostring(it):match("(%d+)"))
	if opts and opts.now and ITEMS[id] and ITEMS[id].req > 25 then return nil, "pas avant le niveau " .. ITEMS[id].req end
	local e = EVAL[id]
	if e then return e end
	return nil, WHY[id] or "pas un équipement"
end
ns.Gear.ReadProfessions = function() return { [164] = { rank = 60, max = 75 }, [186] = { rank = 70, max = 150 } } end
ns.Pilote.Config = function() return { on = true, merchant = false } end

-- 1. L'analyse
local list, waiting = ns.Sacs.Analyse()
local byId = {}
for _, e in ipairs(list) do
	byId[e.itemID] = e
	print(e.itemID, e.name, e.checked, e.sellable, e.reason)
end
local function Is(id, checked)
	assert(byId[id], "objet " .. id .. " pas proposé")
	assert(byId[id].checked == checked, "objet " .. id .. " coché : " .. tostring(byId[id].checked))
end
for _, id in ipairs({ 6948, 2901, 202, 2840, 2770, 400, 601 }) do
	assert(not byId[id], "objet utile proposé : " .. id)
end
Is(100, true); Is(200, true); Is(201, false); Is(203, true); Is(204, false); Is(300, false); Is(2589, false)
Is(500, true); Is(600, false)
assert(byId[100].value == 150 and byId[100].sellable, "valeur du gris")
assert(not byId[500].sellable, "objet sans valeur vendable ?")
assert(byId[204].reason:find("rôle"), byId[204].reason)

-- 2. Pas de marchand : vente prévue au prochain, le trajet ajoute un marchand
SlashCmdList.ITINERAIRE("sacs")
assert(ns.Sacs.Shown(), "/iti sacs n'ouvre pas la fenêtre")
local function Button(pattern)
	for _, f in ipairs(FRAMES) do
		if f.kind == "Button" and tostring(rawget(f, "text") or ""):find(pattern) then return f end
	end
end
local sell = Button("prochain marchand")
assert(sell and tostring(sell.text):find("3 coch"), "bouton de vente : " .. tostring(sell and sell.text)) -- 100, 200, 203
sell.scripts.OnClick(sell)
assert(ns.Sacs.PendingCount() == 3, "vente prévue : " .. ns.Sacs.PendingCount())
Advance(3)
local stop
for _, s in ipairs(ns.plan.order) do
	if s.kind == "service" and s.service.label == "Vendre ce qui ne sert plus" then stop = s end
end
assert(stop, "pas d'arrêt marchand pour la vente prévue")
print("arrêt :", stop.title)

-- 3. Chez le marchand : seulement ce qui était coché, et toujours jugé inutile
MERCHANT = true
Fire("MERCHANT_SHOW")
Advance(3)
table.sort(SOLD)
assert(table.concat(SOLD, ",") == "100,200,203", "vendus : " .. table.concat(SOLD, ","))
assert(ns.Sacs.PendingCount() == 0, "vente prévue pas vidée")
assert(BAG[5] and BAG[6] and BAG[10] and BAG[1], "un objet non coché a été vendu")

-- 4. Détruire : seulement les objets cochés qui ne se vendent pas, au 2e clic
ns.Sacs.Refresh()
local destroy = Button("Détruire les 1")
assert(destroy, "bouton détruire")
destroy.scripts.OnClick(destroy)
assert(#DELETED == 0, "détruit dès le 1er clic")
destroy.scripts.OnClick(destroy)
Advance(2)
assert(table.concat(DELETED, ",") == "500", "détruits : " .. table.concat(DELETED, ","))
MERCHANT = false
Fire("MERCHANT_CLOSED")
Advance(2)
print("OK sacs")
