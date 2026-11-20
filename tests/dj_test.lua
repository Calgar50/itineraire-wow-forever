-- DungeonJournal (lu pendant le jeu, ForeverDungeonJournal_NS) : donjons fusionnés avec les données reprises,
-- butins et récompenses des quêtes de donjon dans l'équipement, quêtes à prendre avant un donjon, repères des
-- quêtes que Questie ne connaît pas, ouverture du journal. Le faux DungeonJournal ci-dessous imite la forme de
-- ses tables (version 2.1.0) avec des données inventées pour le test.
dofile(TESTS .. "/wow_mock.lua")
time = function() return 1800000000 end

function UnitClass() return "Guerrier", "WARRIOR", 1 end
function UnitFactionGroup() return "Horde", "Horde" end
function UnitRace() return "Orc", "Orc" end
TALENTS = { { "Armes", 0 }, { "Fureur", 0 }, { "Protection", 5 } }
function GetTalentTabInfo(tab) local t = TALENTS[tab] return t[1], "icon", t[2], "file" end
function GetAddOnMetadata(name, field)
	if field ~= "Version" then return nil end
	return ({ ForeverDungeonJournal = "2.1.0", Itineraire = "2.3.0" })[name]
end

ITEMS = {}
local function item(id, name, equipLoc, classID, subclassID, req, stats)
	ITEMS[id] = { name = name, equipLoc = equipLoc, classID = classID, subclassID = subclassID, req = req or 10,
		stats = stats or {}, sell = 100, quality = 3, ilvl = (req or 10) + 5 }
end
local function link(id) return "|cff0070dd|Hitem:" .. id .. "::::::::|h[" .. ITEMS[id].name .. "]|h|r" end
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
item(7102, "Tunique de cuir", "INVTYPE_CHEST", 4, 2, 8, { RESISTANCE0_NAME = 60, ITEM_MOD_STAMINA_SHORT = 2 })
EQUIPPED = { [5] = 7102 }
function GetInventoryItemLink(_, slot) return EQUIPPED[slot] and link(EQUIPPED[slot]) end
function GetItemCount() return 0 end

-- Objets du faux journal
item(9001, "Casque d'Oggleflint", "INVTYPE_HEAD", 4, 3, 14, { RESISTANCE0_NAME = 160, ITEM_MOD_STAMINA_SHORT = 6 })
item(9002, "Bouclier des troggs", "INVTYPE_SHIELD", 4, 6, 14, { RESISTANCE0_NAME = 300, ITEM_MOD_STAMINA_SHORT = 5 })
item(9003, "Casque de l'Alliance", "INVTYPE_HEAD", 4, 3, 14, { RESISTANCE0_NAME = 150, ITEM_MOD_STAMINA_SHORT = 6 })
item(9010, "Bottes de Rahauro", "INVTYPE_FEET", 4, 3, 14, { RESISTANCE0_NAME = 120, ITEM_MOD_STAMINA_SHORT = 5 })
item(9011, "Gants de l'Alliance", "INVTYPE_HAND", 4, 3, 14, { RESISTANCE0_NAME = 100, ITEM_MOD_STAMINA_SHORT = 5 })
item(9012, "Ceinture du futur", "INVTYPE_WAIST", 4, 3, 18, { RESISTANCE0_NAME = 100, ITEM_MOD_STAMINA_SHORT = 7 })
item(9013, "Brassards du paladin", "INVTYPE_WRIST", 4, 3, 14, { RESISTANCE0_NAME = 90, ITEM_MOD_STAMINA_SHORT = 5 })
item(9020, "Cape du Creux", "INVTYPE_CLOAK", 4, 1, 15, { RESISTANCE0_NAME = 30, ITEM_MOD_STAMINA_SHORT = 6 })

-- Le faux DungeonJournal (chargé avant Itinéraire : OptionalDeps)
CALLS = {}
ForeverDungeonJournalFrame = { shown = false, IsShown = function(f) return f.shown end, Show = function(f) f.shown = true end }
ForeverDungeonJournal_NS = {
	DB = {
		["Ragefire Chasm"] = {
			level = "13-18",
			entrance = { mapID = 1454, x = 0.526, y = 0.490, label = "Ragefire Chasm Entrance", markerType = "dungeon" },
			quests = {
				{ id = 95001, name = "Ragefire Errand", faction = "Horde", level = 15, requires = 12,
					pickup = "Rahauro, Elder Rise, Thunder Bluff", turnin = "Rahauro, Thunder Bluff",
					rewardItems = { { 9010, "Bottes de Rahauro", 3 } }, rewardChoice = true,
					startMap = { mapID = 1456, x = 0.70, y = 0.29, label = "Rahauro \226\128\148 Elder Rise", targetName = "Rahauro" } },
				{ id = 95002, name = "Alliance Only", faction = "Alliance", level = 15, requires = 10,
					pickup = "Somewhere", turnin = "Somewhere", rewardItems = { { 9011, "Gants de l'Alliance", 3 } } },
				{ id = 95003, name = "Later Quest", faction = "Both", level = 20, requires = 18,
					pickup = "Thrall, Orgrimmar", turnin = "Thrall, Orgrimmar", rewardItems = { { 9012, "Ceinture du futur", 3 } } },
				{ id = 95004, name = "Turn Me In", faction = "Horde", level = 15, requires = 10,
					pickup = "Grunt, the Barrens", turnin = "Grunt, the Barrens", rewardItems = {},
					turninMap = { mapID = 1413, x = 0.50, y = 0.50, label = "Grunt \226\128\148 Crossroads", targetName = "Grunt" } },
				{ id = 95005, name = "Kill Inside", faction = "Both", level = 15, requires = 10,
					pickup = "Rahauro, Thunder Bluff", turnin = "Bazzalan's corpse, inside the dungeon", rewardItems = {} },
				{ id = 95006, name = "Paladin Thing", faction = "Both", level = 15, requires = 10, classOnly = "PALADIN",
					pickup = "Somewhere", turnin = "Somewhere", rewardItems = { { 9013, "Brassards du paladin", 3 } } },
				"pas une quête", { id = "pas un nombre" },
			},
			bosses = {
				{ name = "Oggleflint", npcID = 11517, loot = { { 9001, "Casque d'Oggleflint", "Head, Mail", 3 } } },
				{ name = "Trash Drops", trash = true, listHidden = true, loot = { { 9002, "Bouclier des troggs", "Off Hand, Shield", 3, "Trogg" } } },
				{ name = "Alliance Captain", factionOnly = "Alliance", loot = { { 9003, "Casque de l'Alliance", "Head, Mail", 3 } } },
				"pas un boss", { name = "Sans butin", loot = { "pas un objet" } },
			},
		},
		["Test Hollow"] = {
			level = "14-20",
			entrance = { mapID = 1411, x = 0.40, y = 0.60, label = "Test Hollow Entrance" },
			quests = {},
			bosses = { { name = "Hollow King", npcID = 99001, loot = { { 9020, "Cape du Creux", "Back", 3 } } } },
		},
		["Onyxia Attunement"] = { level = "48+", questChainPage = true, quests = {}, bosses = {} },
		["Cassé"] = { bosses = "rien", quests = 12 },
	},
	QUEST_START_MAPS = {
		[95003] = { mapID = 1454, x = 0.32, y = 0.378, label = "Thrall" },
	},
	LocalizeDungeonName = function(key) return ({ ["Ragefire Chasm"] = "Gouffre de Ragefeu" })[key] end,
	LocalizeQuestField = function(id, field, fallback) return id == 95001 and field == "name" and "Course à Ragefeu" or fallback end,
	LocalizeBossName = function(name) return name end,
	LocalizeFreeText = function(text) return text end,
	TurnInInsideDungeon = function(text) return text:lower():find("inside", 1, true) ~= nil end,
	OpenQuestPage = function(key, id) CALLS[#CALLS + 1] = "quest:" .. key .. ":" .. tostring(id) end,
	OpenBossPage = function(key, index) CALLS[#CALLS + 1] = "boss:" .. key .. ":" .. tostring(index) end,
	ToggleJournal = function() CALLS[#CALLS + 1] = "toggle" end,
}

-- Journal : 95004 finie (Questie ne sait pas où la rendre), 95005 en cours (objectif inconnu de Questie).
LOG[1] = { info = { questID = 95004, title = "Turn Me In", level = 15, suggestedGroup = 0 }, objectives = {}, complete = true }
QUESTS[95004] = { Id = 95004, name = "Turn Me In", level = 15, xp = 300 }
LOG[2] = { info = { questID = 95005, title = "Kill Inside", level = 15, suggestedGroup = 0 },
	objectives = { { text = "Bazzalan tué : 0/1", type = "monster", finished = false, numFulfilled = 0, numRequired = 1 } } }
QUESTS[95005] = { Id = 95005, name = "Kill Inside", level = 15, xp = 500 }

Enum = { TooltipDataType = { Item = 0 } }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) TIP_FN = fn end }

local files = { "Donnees/Butins.lua", "Donnees/Objets.lua", "Donnees/Entrees.lua", "Donnees/Recettes.lua", "Donnees/PNJ.lua",
	"Donnees/Marchandises.lua", "Solver.lua", "Geo.lua", "Data.lua", "DungeonJournal.lua", "Planner.lua", "Guide.lua", "UI.lua",
	"Options.lua", "Group.lua", "Gear.lua", "GearUI.lua", "Core.lua" }
PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.515, 0.303
local ns = LoadAddon(ADDON_DIR, files)
Fire("ADDON_LOADED", "Itineraire")
Fire("PLAYER_LOGIN")
Advance(5)
local D, G, DJ = ns.Data, ns.Gear, ns.DJ
MENU = nil
ns.UI.ShowMenu = function(items) MENU = items end

-- 1. Donjons : celui de DungeonJournal remplace le Gouffre de Ragefeu des données reprises, sans rien perdre.
local dungeons = D.Dungeons()
local byId = {}
for _, d in ipairs(dungeons) do byId[d.id] = d end
local rfc = byId["dj:Ragefire Chasm"]
assert(rfc, "donjon de DungeonJournal absent")
assert(not byId[226], "l'ancien Gouffre de Ragefeu est resté en double")
assert(D.DungeonAlias(226) == "dj:Ragefire Chasm", "alias de l'ancien id")
assert(rfc.name == "Gouffre de Ragefeu" and rfc.min == 13 and rfc.max == 18, "nom/niveaux : " .. rfc.name)
assert(rfc.entrance and rfc.entrance.map == 1454 and rfc.entrance.hint == "DungeonJournal", "entrée de DungeonJournal")
local oggle, names, seen272999 = nil, {}, false
for _, b in ipairs(rfc.bosses) do
	names[#names + 1] = b.name
	if b.english == "Oggleflint" then oggle = b end
	for _, id in ipairs(b.items or {}) do if id == 272999 then seen272999 = true end end
	assert(b.english ~= "Alliance Captain", "boss de l'Alliance gardé pour un Horde")
end
assert(oggle and oggle.items[1] == 9001 and seen272999, "objets des données reprises non fusionnés dans le boss")
assert(table.concat(names, ","):find("Taragaman"), "boss des données reprises perdu : " .. table.concat(names, ","))
assert(byId["dj:Test Hollow"] and byId["dj:Test Hollow"].entrance.map == 1411, "nouveau donjon de Forever absent")
assert(not byId["dj:Onyxia Attunement"], "une page de chaîne de quêtes n'est pas un donjon")
assert(#dungeons >= 30, "donjons : " .. #dungeons)
local raid = false
for _, d in ipairs(dungeons) do if d.raid then raid = true end end
assert(raid, "les raids des données reprises ont disparu")

-- 2. États des quêtes.
assert(DJ.QuestState(DJ.Quest(95001), {}) == "maintenant")
assert(DJ.QuestState(DJ.Quest(95002), {}) == "non", "quête de l'Alliance")
local st, req = DJ.QuestState(DJ.Quest(95003), {})
assert(st == "plus tard" and req == 18, "quête de plus haut niveau : " .. tostring(st))
assert(DJ.QuestState(DJ.Quest(95006), {}) == "non", "quête de paladin pour un guerrier")
assert(DJ.QuestState(DJ.Quest(95004), { [95004] = true }) == "log")
assert(DJ.StartPoint(DJ.Quest(95001)).name == "Rahauro", "donneur de la quête")

-- 3. Repères : rendu de 95004 (repère de DungeonJournal) et objectif de 95005 (entrée du donjon).
local turnStop, objStop
for _, s in ipairs(ns.plan.order) do
	if s.questSet[95004] and s.kind == "turnin" then turnStop = s end
	if s.questSet[95005] and s.kind ~= "turnin" then objStop = s end
end
assert(turnStop and turnStop.hint == "DungeonJournal" and turnStop.map == 1413, "rendu donné par DungeonJournal")
assert(objStop and objStop.hint == "DungeonJournal" and objStop.map == 1454, "objectif : entrée du donjon")
assert(table.concat(objStop.details, " / "):find("approximatif"), "lieu approximatif non signalé")

-- 4. Équipement : butins (boss, monstres), récompenses des quêtes de donjon.
assert(G.Rescan())
Advance(3)
assert(G.state.phase == "fini", "analyse : " .. tostring(G.state.phase) .. " " .. tostring(G.state.error))
local found = {}
for _, e in ipairs(G.results.list) do
	found[e.id] = e
	print(string.format("  %s %s · %s · %s", e.name, G.GainText(e), e.slotName, e.best.text))
end
assert(found[9001] and found[9001].best.kind == "dungeon" and found[9001].best.dj == "Ragefire Chasm"
	and found[9001].best.djBoss == 1, "butin d'Oggleflint")
assert(found[9002] and found[9002].best.text:find("butin des monstres"), "butin des monstres")
assert(not found[9003], "butin d'un boss de l'Alliance proposé")
assert(found[9010] and found[9010].best.kind == "dquest" and found[9010].best.points[1].map == 1456
	and found[9010].best.text:find("Course à Ragefeu") and found[9010].best.text:find("Rahauro"), "récompense de quête de donjon")
assert(not found[9011], "récompense d'une quête de l'Alliance proposée")
assert(found[9012] and found[9012].best.kind == "later" and found[9012].best.text:find("niveau 18"), "récompense pour plus tard")
assert(not found[9013], "récompense d'une quête de paladin proposée")
assert(found[9020] and found[9020].best.dungeonName == "Test Hollow", "butin du nouveau donjon")

-- 5. « Y aller » vers la quête qui donne les bottes.
G.SetGoal(9010, true)
Advance(5)
local goalStop
for _, s in ipairs(ns.plan.order) do
	if s.kind == "service" and s.service.key == "objet9010" then goalStop = s end
end
assert(goalStop and goalStop.map == 1456 and goalStop.service.title:find("Quête pour"), "étape vers le donneur")

-- 6. Objectif « Donjon » enregistré avec l'ancien id : repris, et ses quêtes à prendre avant (sans doublon).
G.Config().dungeonGoals[226] = true
ns.RequestPlan("test", 0)
Advance(5)
assert(G.Config().dungeonGoals["dj:Ragefire Chasm"] and not G.Config().dungeonGoals[226], "objectif non repris")
local dungeonStop, djqStop
for _, s in ipairs(ns.plan.order) do
	if s.kind == "service" and s.service.key == "donjondj:Ragefire Chasm" then dungeonStop = s end
	if s.kind == "service" and s.service.key == "djq95001" then djqStop = s end
end
assert(dungeonStop and dungeonStop.map == 1454, "étape vers l'entrée du donjon")
assert(not djqStop, "la quête déjà visée pour les bottes est en double")
local why = table.concat(dungeonStop.service.why, " / ")
assert(why:find("Kill Inside") and why:find("Course à Ragefeu"), "quêtes du donjon absentes : " .. why)
G.SetGoal(9010, false)
Advance(5)
for _, s in ipairs(ns.plan.order) do
	if s.kind == "service" and s.service.key == "djq95001" then djqStop = s end
end
assert(djqStop and djqStop.map == 1456, "quête à prendre avant le donjon absente du trajet")

-- 7. Fenêtre Équipement : menus « DungeonJournal ».
ns.GearUI.Toggle(true, "dungeons")
ns.GearUI.Refresh()
local row
for _, f in ipairs(FRAMES) do
	local r = rawget(f, "dungeonEntry")
	if r and r.dungeon.id == "dj:Ragefire Chasm" then row = f end
end
assert(row, "ligne du donjon absente")
row.scripts.OnEnter(row)
row.scripts.OnClick(row, "RightButton")
local open
for _, it in ipairs(MENU or {}) do if it.text == "Ouvrir dans DungeonJournal" then open = it end end
assert(open, "menu sans « Ouvrir dans DungeonJournal »")
open.func()
assert(ForeverDungeonJournalFrame.shown and CALLS[#CALLS] == "boss:Ragefire Chasm:nil", "journal non ouvert : " .. tostring(CALLS[#CALLS]))
ns.GearUI.Toggle(true, "items")
ns.GearUI.Refresh()
for _, f in ipairs(FRAMES) do
	local e = rawget(f, "entry")
	if e and e.id == 9010 then row = f end
end
row.scripts.OnClick(row, "RightButton")
open = nil
for _, it in ipairs(MENU or {}) do if it.text == "Voir dans DungeonJournal" then open = it end end
assert(open, "menu de l'objet sans « Voir dans DungeonJournal »")
open.func()
assert(CALLS[#CALLS] == "quest:Ragefire Chasm:95001", "page de quête : " .. tostring(CALLS[#CALLS]))

-- 8. /iti dj, rapport.
SlashCmdList.ITINERAIRE("dj gouffre")
assert(CALLS[#CALLS] == "boss:Ragefire Chasm:nil", "/iti dj gouffre : " .. tostring(CALLS[#CALLS]))
local report = ns.ReportText()
assert(report:find("DungeonJournal 2.1.0 : lu %(2 donjons, 6 quêtes"), "rapport : " .. report:match("DungeonJournal[^\n]*"))
print(report:match("DungeonJournal[^\n]*"))
print("OK dungeonjournal")
