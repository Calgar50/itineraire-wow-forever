-- Fusion : vraies données reprises (Donnees/*.lua : donjons, entrées, recettes, PNJ, marchandises), repère du jeu
-- pour les quêtes que Questie ne place pas, ligne dans la bulle des objets, classement des donjons.
dofile(TESTS .. "/wow_mock.lua")
time = function() return 1800000000 end

function UnitClass() return "Guerrier", "WARRIOR", 1 end
function UnitFactionGroup() return "Horde", "Horde" end
TALENTS = { { "Armes", 0 }, { "Fureur", 0 }, { "Protection", 5 } }
function GetTalentTabInfo(tab) local t = TALENTS[tab] return t[1], "icon", t[2], "file" end

-- Objets du jeu (remplis plus bas avec de vrais identifiants pris dans les données).
ITEMS = {}
local function item(id, name, equipLoc, classID, subclassID, req, stats, sell)
	ITEMS[id] = { name = name, equipLoc = equipLoc, classID = classID, subclassID = subclassID, req = req or 10,
		stats = stats or {}, sell = sell or 100, quality = 2, ilvl = (req or 10) + 5 }
end
local function link(id) return "|cff1eff00|Hitem:" .. id .. "::::::::|h[" .. ITEMS[id].name .. "]|h|r" end
local function idOf(x) return type(x) == "number" and x or tonumber(tostring(x):match("item:(%d+)")) end
C_Item = {
	GetItemInfo = function(x)
		local id = idOf(x)
		local it = ITEMS[id]
		if not it then return nil end
		return it.name, link(id), it.quality, it.ilvl, it.req, "", "", 1, it.equipLoc, "icon" .. id, it.sell, it.classID, it.subclassID
	end,
	GetItemInfoInstant = function(x)
		local id = idOf(x)
		local it = ITEMS[id]
		if not it then return nil end
		return id, "", "", it.equipLoc, "icon" .. id, it.classID, it.subclassID
	end,
	GetItemStats = function(l) local it = ITEMS[idOf(l)] return it and it.stats end,
	RequestLoadItemDataByID = function() end,
}
item(7100, "Vieux bouclier", "INVTYPE_SHIELD", 4, 6, 8, { RESISTANCE0_NAME = 50, ITEM_MOD_STAMINA_SHORT = 1 })
item(7102, "Tunique de cuir", "INVTYPE_CHEST", 4, 2, 8, { RESISTANCE0_NAME = 60, ITEM_MOD_STAMINA_SHORT = 2 })
EQUIPPED = { [17] = 7100, [5] = 7102 }
function GetInventoryItemLink(_, slot) return EQUIPPED[slot] and link(EQUIPPED[slot]) end
function GetItemCount() return 0 end

-- Forge 50/75 (Forever : GetProfessions / GetProfessionInfo).
function GetProfessions() return 1, nil, nil, nil, nil end
function GetProfessionInfo(i) if i == 1 then return "Forge", "icon", 50, 75, 0, 0, 164 end end

-- Les données reprises (comme dans le .toc).
local files = { "Donnees/Butins.lua", "Donnees/Objets.lua", "Donnees/Entrees.lua", "Donnees/Recettes.lua", "Donnees/PNJ.lua",
	"Donnees/Marchandises.lua", "Solver.lua", "Geo.lua", "Data.lua", "Planner.lua", "Guide.lua", "UI.lua", "Options.lua",
	"Group.lua", "Gear.lua", "GearUI.lua", "Core.lua" }

-- 0. Choix de vrais identifiants dans les données (avant le chargement : on lit les fichiers d'abord à part).
local peek = {}
for _, f in ipairs({ "Donnees/Butins.lua", "Donnees/Recettes.lua", "Donnees/PNJ.lua", "Donnees/Marchandises.lua" }) do
	assert(loadfile(ADDON_DIR .. "/" .. f))("Itineraire", peek)
end
local E = peek.ext
-- un objet du Gouffre de Ragefeu (226), donjon de la Horde à Orgrimmar
local rfc = E.BUTINS[226]
assert(rfc and rfc.min <= 16 and #rfc.bosses > 0, "Gouffre de Ragefeu absent des données")
local rfcBoss = rfc.bosses[1]
local rfcItem = rfcBoss.items[1]
item(rfcItem, "Bouclier de Ragefeu", "INVTYPE_SHIELD", 4, 6, 14, { RESISTANCE0_NAME = 200, ITEM_MOD_STAMINA_SHORT = 6 }, 300)
-- une recette de forge apprise chez l'entraîneur, qui fabrique une pièce d'armure
local craftSpell, craftItem
for spell, r in pairs(E.RECETTES) do
	if r[1] == 164 and r[3] == "t" and (tonumber(r[2]) or 0) <= 60 and (tonumber(r[5]) or 0) > 0 and not craftSpell then
		craftSpell, craftItem = spell, r[5]
	end
end
assert(craftSpell, "pas de recette de forge dans les données")
item(craftItem, "Plastron forgé", "INVTYPE_HEAD", 4, 3, 12, { RESISTANCE0_NAME = 140, ITEM_MOD_STAMINA_SHORT = 5 }, 200)
-- un objet vendu par un vendeur de la Horde (ou neutre) d'Orgrimmar ou des Tarides, d'après Finddon
local sideOf, placesOf = {}, {}
for line in E.PNJ:gmatch("[^\n]+") do
	local id, side, spots = line:match("^(%d+)%^[^%^]*%^[^%^]*%^(%a)%^[^%^]*%^[^%^]*%^([^%^]+)")
	if id then sideOf[tonumber(id)], placesOf[tonumber(id)] = side, spots end
end
local goodsItem, goodsVendor
for line in E.MARCHANDISES:gmatch("[^\n]+") do
	local id, free = line:match("^(%d+)%^[^%^]+%^%l?%^(%w*)%^")
	if id and free and not goodsItem then
		for i = 1, #free - 3, 4 do
			local npc = tonumber(free:sub(i, i + 3), 36)
			local spots = placesOf[npc]
			if spots and (sideOf[npc] == "H" or sideOf[npc] == "N") and (spots:find("^1454:") or spots:find("^1413:"))
				and not ITEMS[tonumber(id)] then
				goodsItem, goodsVendor = tonumber(id), npc
				break
			end
		end
	end
end
assert(goodsItem, "pas d'objet vendu à Orgrimmar ou dans les Tarides dans les données")
item(goodsItem, "Cape du marchand", "INVTYPE_CLOAK", 4, 1, 13, { RESISTANCE0_NAME = 25, ITEM_MOD_STAMINA_SHORT = 3 }, 100)

-- Journal : une quête dont Questie ignore les objectifs, une autre finie dont il ignore le PNJ de rendu.
LOG[1] = { info = { questID = 3001, title = "Mystère des Tarides", level = 15, suggestedGroup = 0 },
	objectives = { { text = "Indice trouvé : 0/1", type = "object", finished = false, numFulfilled = 0, numRequired = 1 } } }
QUESTS[3001] = { Id = 3001, name = "Mystère des Tarides", level = 15, xp = 500 }
LOG[2] = { info = { questID = 3002, title = "Rapport perdu", level = 15, suggestedGroup = 0 }, objectives = {}, complete = true }
QUESTS[3002] = { Id = 3002, name = "Rapport perdu", level = 15, xp = 300 }
-- Le jeu, lui, sait où aller (ses repères de carte).
C_QuestLog.GetQuestsOnMap = function(map)
	if map == 1413 then
		return { { questID = 3001, x = 0.6, y = 0.4 }, { questID = 3002, x = 0.45, y = 0.55 } }
	end
	return {}
end
-- La bulle des objets (API moderne).
Enum = { TooltipDataType = { Item = 0 } }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) TIP_FN = fn end }

PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.515, 0.303
local ns = LoadAddon(ADDON_DIR, files)
Fire("ADDON_LOADED", "Itineraire")
Fire("PLAYER_LOGIN")
Advance(5)
local D, G = ns.Data, ns.Gear

-- 1. Les données reprises sont là et se lisent.
local dungeons = D.Dungeons()
local withEntrance = 0
for _, d in ipairs(dungeons) do
	if d.entrance then withEntrance = withEntrance + 1 end
end
print("donjons :", #dungeons, "avec entrée :", withEntrance)
assert(#dungeons >= 30, "donjons : " .. #dungeons)
local rfcData
for _, d in ipairs(dungeons) do if d.id == 226 then rfcData = d end end
assert(rfcData and rfcData.entrance and rfcData.entrance.map == 1454, "entrée du Gouffre de Ragefeu")
local vendor = D.ExtNpc(goodsVendor)
assert(vendor and D.ExtNpcFriendly(vendor), "vendeur Finddon")
assert(#D.ExtNpcPlaces(vendor) > 0, "positions du vendeur")
local sells = D.ExtVendors(goodsItem)
assert(sells and #sells >= 1, "marchandises")
assert(D.ItemFallback(rfcItem) == nil or D.ItemFallback(rfcItem).name, "noms de secours")

-- 2. Repère du jeu : les deux quêtes sont sur le trajet, avec la mention « approximatif ».
local objStop, turnStop
for _, s in ipairs(ns.plan.order) do
	if s.questSet[3001] and s.kind ~= "turnin" then objStop = s end
	if s.questSet[3002] and s.kind == "turnin" then turnStop = s end
end
assert(objStop and objStop.hint == "jeu", "objectif inconnu de Questie : pas d'étape au repère du jeu")
assert(turnStop and turnStop.hint == "jeu", "rendu inconnu de Questie : pas d'étape au repère du jeu")
local detail = table.concat(objStop.details, " / ")
assert(detail:find("approximatif"), "la bulle ne dit pas que le lieu est approximatif")
for _, u in ipairs(ns.plan.side.unknown) do
	-- (3001 pas finie : son rendu reste inconnu tant que le jeu ne le montre pas — seul DonData le devinerait)
	assert(u.q.id ~= 3002 and not (u.q.id == 3001 and u.what ~= "où la rendre"), "quête encore « position inconnue » : " .. u.q.id)
end

-- 3. Recherche d'équipement avec les données reprises : donjon, métier, vendeur Finddon.
assert(G.Rescan())
Advance(3)
assert(G.state.phase == "fini", "analyse : " .. tostring(G.state.phase) .. " " .. tostring(G.state.error))
local found = {}
for _, e in ipairs(G.results.list) do
	found[e.id] = e
	print(string.format("  %s %s · %s · %s", e.name, G.GainText(e), e.slotName, e.best.text))
end
assert(found[rfcItem] and found[rfcItem].best.kind == "dungeon", "butin du Gouffre de Ragefeu absent")
assert(found[rfcItem].best.text:find("Ragefire") or found[rfcItem].best.text:find("Ragefeu"), "nom du donjon")
assert(found[craftItem] and found[craftItem].best.kind == "recipe", "objet de forge (recette à apprendre) absent")
assert(found[goodsItem] and found[goodsItem].best.kind == "vendor", "objet du vendeur Finddon absent")

-- 4. La recette apprise (fenêtre de forge ouverte) : « à fabriquer ».
C_TradeSkillUI = {
	GetAllRecipeIDs = function() return { craftSpell, 999999 } end,
	GetRecipeInfo = function(id) return { learned = id == craftSpell } end,
}
Fire("TRADE_SKILL_SHOW")
Advance(5)
local crafted
for _, e in ipairs(G.results.list) do if e.id == craftItem then crafted = e end end
assert(crafted and crafted.best.kind == "craft" and crafted.best.text:find("tu connais la recette"), "recette apprise non vue")

-- 5. Quel donjon faire ? Le Gouffre de Ragefeu, avec « Y aller » vers son entrée.
local ranking = G.DungeonRanking()
assert(ranking[1] and ranking[1].dungeon.id == 226 and ranking[1].count >= 1, "classement des donjons")
G.SetDungeonGoal(226, true)
Advance(5)
local dungeonStop
for _, s in ipairs(ns.plan.order) do
	if s.kind == "service" and s.service.key == "donjon226" then dungeonStop = s end
end
assert(dungeonStop and dungeonStop.map == 1454, "pas d'étape vers l'entrée du donjon")
ns.GearUI.Toggle(true, "dungeons")
ns.GearUI.Refresh()

-- 6. La bulle des objets.
assert(G.tooltipHooked == "TooltipDataProcessor", "bulle non branchée : " .. tostring(G.tooltipHooked))
LINES = {}
local tip = { GetItem = function() return "Bouclier de Ragefeu", link(rfcItem) end, GetName = function() return "GameTooltip" end,
	AddLine = function(_, text) LINES[#LINES + 1] = text end }
TIP_FN(tip, {})
assert(LINES[1] and LINES[1]:find("Itinéraire : .*pour toi"), "ligne de bulle : " .. tostring(LINES[1]))
LINES = {}
TIP_FN({ GetItem = function() return "x", link(rfcItem) end, GetName = function() return "ShoppingTooltip1" end,
	AddLine = function(_, text) LINES[#LINES + 1] = text end }, {})
assert(#LINES == 0, "pas de ligne dans les bulles de comparaison du jeu")
assert(ns.ReportText():find("bulle TooltipDataProcessor"), "rapport sans l'état de la bulle")
print("OK fusion")
