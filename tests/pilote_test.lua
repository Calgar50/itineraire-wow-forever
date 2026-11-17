-- Pilote automatique : quêtes (prendre, rendre, récompense), dialogues utiles, vol prévu, cinématiques, marchand,
-- maître de classe, bouton d'objet de quête, MAJ pour reprendre la main, actions bloquées par le jeu, Questie.
dofile(TESTS .. "/wow_mock.lua")
time = function() return 1800000000 end

function UnitClass() return "Guerrier", "WARRIOR", 1 end
function UnitFactionGroup() return "Horde", "Horde" end
TALENTS = { { "Armes", 0 }, { "Fureur", 0 }, { "Protection", 5 } }
function GetTalentTabInfo(tab) local t = TALENTS[tab] return t[1], "icon", t[2], "file" end
SHIFT = false
function IsShiftKeyDown() return SHIFT end
COMBAT = false
function InCombatLockdown() return COMBAT end
MONEY = 10000
function GetMoney() return MONEY end
CALLS = {}
local function Called(name) local n = 0 for _, c in ipairs(CALLS) do if c[1] == name then n = n + 1 end end return n end
local function Last(name) for k = #CALLS, 1, -1 do if CALLS[k][1] == name then return CALLS[k] end end end
local function Spy(name) return function(...) CALLS[#CALLS + 1] = { name, ... } end end

-- Objets (récompenses, objet de quête, objets gris).
ITEMS = {}
local function item(id, name, equipLoc, classID, subclassID, req, stats, sell, quality)
	ITEMS[id] = { name = name, equipLoc = equipLoc, classID = classID, subclassID = subclassID, req = req or 10,
		stats = stats or {}, sell = sell or 100, quality = quality or 2, ilvl = (req or 10) + 5 }
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
		local it = ITEMS[idOf(x)]
		if not it then return nil end
		return idOf(x), "", "", it.equipLoc, "icon", it.classID, it.subclassID
	end,
	GetItemStats = function(l) local it = ITEMS[idOf(l)] return it and it.stats end,
	GetItemSpell = function(id) if id == 9500 then return "Utiliser", 1234 end end,
	GetItemCount = function(id) return id == 9500 and 1 or 0 end,
	RequestLoadItemDataByID = function() end,
}
item(7100, "Vieux bouclier", "INVTYPE_SHIELD", 4, 6, 8, { RESISTANCE0_NAME = 50, ITEM_MOD_STAMINA_SHORT = 1 })
item(7001, "Bouclier du gardien", "INVTYPE_SHIELD", 4, 6, 14, { RESISTANCE0_NAME = 120, ITEM_MOD_STAMINA_SHORT = 4 }, 500)
item(7012, "Robe d'étoffe", "INVTYPE_CHEST", 4, 1, 12, { RESISTANCE0_NAME = 20, ITEM_MOD_INTELLECT_SHORT = 5 }, 400)
item(9500, "Fiole de purification", "", 12, 0, 0, {}, 0, 1)
item(9601, "Os brisé", "", 15, 0, 0, {}, 7, 0)
item(9602, "Lambeau de cuir", "", 15, 0, 0, {}, 12, 0)
EQUIPPED = { [17] = 7100 }
function GetInventoryItemLink(_, slot) return EQUIPPED[slot] and link(EQUIPPED[slot]) end
function GetItemCount() return 0 end

-- Sacs : objet de quête utilisable (sac 0, case 1), deux objets gris (cases 2 et 3).
BAGS = { [0] = { [1] = { itemID = 9500, quality = 1, stackCount = 1, iconFileID = 555 },
	[2] = { itemID = 9601, quality = 0, stackCount = 3 }, [3] = { itemID = 9602, quality = 0, stackCount = 1 } } }
C_Container = {
	GetContainerNumSlots = function(bag) return bag == 0 and 4 or 0 end,
	GetContainerItemInfo = function(bag, slot) return BAGS[bag] and BAGS[bag][slot] end,
	GetContainerItemQuestInfo = function() return {} end,
	UseContainerItem = function(bag, slot) CALLS[#CALLS + 1] = { "UseContainerItem", bag, slot } BAGS[bag][slot] = nil end,
	GetContainerNumFreeSlots = function() return 10, 0 end,
	GetItemCooldown = function() return 0, 0 end,
}

-- Monde : la Croisée.
local function npc(id, name, area, pts, level, friendly)
	NPCS[id] = { id = id, name = name, spawns = { [area] = pts }, friendly = friendly, maxLevel = level }
end
npc(9, "Sergra Darkthorn", 17, { { 52.2, 31.0 } }, nil, true)
npc(106, "Zhévra", 17, { { 55, 33 }, { 56, 34 } }, 12, false)
LOG[1] = { info = { questID = 1001, title = "Les zhévras", level = 15, suggestedGroup = 0 },
	objectives = { { text = "Zhévra purifié : 0/6", type = "monster", finished = false, numFulfilled = 0, numRequired = 6 } } }
QUESTS[1001] = { Id = 1001, name = "Les zhévras", level = 15, xp = 900, Finisher = { NPC = { 9 } }, requiredSourceItems = { 9500 },
	Objectives = { { spawnList = { { Id = 106, Name = "Zhévra", Spawns = NPCS[106].spawns, Hostile = true } } } } }
QUESTS[2050] = { Id = 2050, name = "Quête de tous les jours", level = 15, IsRepeatable = true }
local DB = QuestieLoader:ImportModule("QuestieDB")
function DB.IsRepeatable(id) return id == 2050 end
function DB.IsDailyQuest() return false end

-- Questie : prise et rendu automatiques allumés (le pilote doit les couper, puis les remettre).
Questie.db = { profile = { autocomplete = true, autoAccept = { enabled = true } }, char = { complete = {} } }

-- Shortest Path : trajet d'Itinéraire qui marche jusqu'au maître de vol puis vole vers Orgrimmar.
local API = ShortestPathForever.API
JOURNEY_LEGS = { { mode = "walk", to = { map = 1413, x = 0.5, y = 0.3 } }, { mode = "flight", text = "Voler vers Orgrimmar", to = { map = 1454, x = 0.45, y = 0.64 } } }
API.Journey = function() return { owner = "Itineraire", legs = JOURNEY_LEGS, goal = {} } end

-- Fonctions du jeu appelées par le pilote (espionnées).
AcceptQuest, CompleteQuest, ConfirmAcceptQuest, AcknowledgeAutoAcceptQuest = Spy("AcceptQuest"), Spy("CompleteQuest"), Spy("ConfirmAcceptQuest"), Spy("AcknowledgeAutoAcceptQuest")
GetQuestReward, TakeTaxiNode, RepairAllItems, BuyTrainerService = Spy("GetQuestReward"), Spy("TakeTaxiNode"), Spy("RepairAllItems"), Spy("BuyTrainerService")
CinematicFrame_CancelCinematic = Spy("CancelCinematic")
C_GossipInfo = { SelectActiveQuest = Spy("SelectActiveQuest"), SelectAvailableQuest = Spy("SelectAvailableQuest"), SelectOption = Spy("SelectOption") }

PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.515, 0.303
local ns = LoadAddon(ADDON_DIR, { "Solver.lua", "Geo.lua", "Data.lua", "Planner.lua", "Guide.lua", "UI.lua", "Options.lua",
	"Group.lua", "Gear.lua", "GearUI.lua", "Pilote.lua", "Core.lua" })
Fire("ADDON_LOADED", "Itineraire")
Fire("PLAYER_LOGIN")
Advance(5)
local P = ns.Pilote
local function Printed(pattern) for _, m in ipairs(PRINTED) do if m:find(pattern) then return m end end end

-- 0. Une seule main sur les quêtes : Questie coupé.
assert(P.Config().on and Questie.db.profile.autocomplete == false and Questie.db.profile.autoAccept.enabled == false,
	"les réglages automatiques de Questie devraient être coupés")
assert(Printed("réglages automatiques de Questie sont coupés"))

-- 1. Dialogue : d'abord rendre ce qui est fini, puis prendre (pas les grises, ni les répétables, ni les « passées »).
C_GossipInfo.GetActiveQuests = function() return { { questID = 1001, isComplete = false }, { questID = 1500, isComplete = true } } end
C_GossipInfo.GetAvailableQuests = function() return {
	{ questID = 2050, repeatable = true }, { questID = 2060, isTrivial = true }, { questID = 2070 }, { questID = 2080 } } end
C_GossipInfo.GetOptions = function() return {} end
Fire("GOSSIP_SHOW")
assert(Last("SelectActiveQuest")[2] == 1500, "la quête finie n'est pas rendue en premier")
C_GossipInfo.GetActiveQuests = function() return {} end
ns.session.skipped["P:2070"] = true
Fire("GOSSIP_SHOW")
assert(Last("SelectAvailableQuest")[2] == 2080, "mauvaise quête prise : " .. tostring(Last("SelectAvailableQuest")[2]))
-- MAJ maintenue : rien.
local before = #CALLS
SHIFT = true
Fire("GOSSIP_SHOW")
Fire("QUEST_DETAIL")
SHIFT = false
assert(#CALLS == before, "MAJ maintenue : le pilote ne doit rien faire")

-- 2. Fenêtres de quête : accepter, escorte, terminer (pas si elle coûte de l'or), récompense unique.
function GetQuestID() return 2080 end
Fire("QUEST_DETAIL")
assert(Called("AcceptQuest") == 1)
Fire("QUEST_ACCEPT_CONFIRM")
assert(Called("ConfirmAcceptQuest") == 1)
function IsQuestCompletable() return true end
function GetQuestMoneyToGet() return 0 end
Fire("QUEST_PROGRESS")
assert(Called("CompleteQuest") == 1)
function GetQuestMoneyToGet() return 500 end
Fire("QUEST_PROGRESS")
assert(Called("CompleteQuest") == 1, "une quête qui coûte de l'or ne doit pas être terminée d'office")
function GetQuestMoneyToGet() return 0 end
CHOICES = { 7001 }
function GetNumQuestChoices() return #CHOICES end
function GetQuestItemLink(_, i) return link(CHOICES[i]) end
function GetQuestItemInfo(_, i) return ITEMS[CHOICES[i]].name, "icon", 1, 2, true end
Fire("QUEST_COMPLETE")
Advance(0.5)
assert(Called("GetQuestReward") == 1 and Last("GetQuestReward")[2] == 1, "récompense unique non prise")
-- Plusieurs récompenses : option « choisir » coupée -> rien ; allumée -> la conseillée.
CHOICES = { 7012, 7001 }
local buttons = {}
for i = 1, 2 do buttons[i] = CreateFrame("Button") buttons[i].type = "choice" buttons[i].GetID = function() return i end end
QuestInfoRewardsFrame = { RewardButtons = buttons }
Fire("QUEST_COMPLETE")
Advance(1)
assert(Called("GetQuestReward") == 1, "le pilote ne doit pas choisir quand l'option est coupée")
Fire("QUEST_FINISHED")
P.Config().reward = true
Fire("QUEST_COMPLETE")
Advance(1)
assert(Called("GetQuestReward") == 2 and Last("GetQuestReward")[2] == 2, "la récompense conseillée (le bouclier) n'est pas prise")
Fire("QUEST_FINISHED")
-- Journal plein : rien n'est pris.
function C_QuestLog.GetMaxNumQuestsCanAccept() return 1 end
Fire("QUEST_DETAIL")
assert(Called("AcceptQuest") == 1 and Printed("journal de quêtes plein"))
C_QuestLog.GetMaxNumQuestsCanAccept = nil

-- 3. Maître de vol : la bonne ligne du dialogue, puis le vol prévu par le trajet.
C_GossipInfo.GetAvailableQuests = function() return {} end
C_GossipInfo.GetOptions = function() return { { gossipOptionID = 41, icon = 132053 }, { gossipOptionID = 42, icon = 132057 } } end
Fire("GOSSIP_SHOW")
assert(Last("SelectOption") and Last("SelectOption")[2] == 42, "la ligne « vol » n'est pas choisie")
function GetTaxiMapID() return 1454 end
C_TaxiMap = { GetAllTaxiNodes = function() return {
	{ slotIndex = 1, name = "Ici", position = { x = 0.9, y = 0.9 }, state = 0 },
	{ slotIndex = 3, name = "Orgrimmar, Durotar", position = { x = 0.452, y = 0.641 }, state = 1 },
	{ slotIndex = 5, name = "Ailleurs", position = { x = 0.2, y = 0.2 }, state = 1 },
} end }
Enum = { FlightPathState = { Current = 0, Reachable = 1, Unreachable = 2 } }
Fire("TAXIMAP_OPENED")
Advance(0.5)
assert(Last("TakeTaxiNode") and Last("TakeTaxiNode")[2] == 3, "le vol prévu n'est pas pris")
assert(Printed("vol vers Orgrimmar"))
-- Destination trop loin de tout nœud connu : pas de vol pris au hasard.
JOURNEY_LEGS[2].to = { map = 1454, x = 0.7, y = 0.1 }
Fire("TAXIMAP_OPENED")
Advance(0.5)
assert(Called("TakeTaxiNode") == 1, "vol pris sans être sûr de la destination")
JOURNEY_LEGS[2].to = { map = 1454, x = 0.45, y = 0.64 }

-- 4. Cinématique passée.
Fire("CINEMATIC_START")
Advance(0.5)
assert(Called("CancelCinematic") == 1)

-- 5. Marchand : réparation puis objets gris vendus un par un ; rien si le marchand ferme.
function CanMerchantRepair() return true end
function GetRepairAllCost() return 500, true end
Fire("MERCHANT_SHOW")
Advance(1)
assert(Called("RepairAllItems") == 1 and Called("UseContainerItem") == 2, "réparer / vendre : " .. Called("RepairAllItems") .. " " .. Called("UseContainerItem"))
assert(BAGS[0][1] and BAGS[0][1].itemID == 9500, "l'objet de quête ne doit pas être vendu")
assert(Printed("2 objet%(s%) gris vendu%(s%) pour 33 pc"), "prix des objets gris")
Fire("MERCHANT_CLOSED")

-- 6. Maître de classe : tout ce qui est disponible, de la fin vers le début.
function IsTradeskillTrainer() return false end
SERVICES = { { "Fendoir", "available", 100 }, { "Charge", "unavailable", 50 }, { "Provocation", "available", 200 } }
function GetNumTrainerServices() return #SERVICES end
function GetTrainerServiceInfo(i) return SERVICES[i][1], "", SERVICES[i][2] end
function GetTrainerServiceCost(i) return SERVICES[i][3] end
Fire("TRAINER_SHOW")
Advance(2)
assert(Called("BuyTrainerService") == 2, "techniques apprises : " .. Called("BuyTrainerService"))
assert(CALLS[#CALLS][2] == 1 and Printed("appris Provocation, Fendoir"), "ordre ou message du maître")

-- 7. Bouton de l'objet de quête (cadre sécurisé : seulement hors combat).
ATTR = {}
ItineraireItemButton.SetAttribute = function(_, k, v) ATTR[k] = v end
COMBAT = true
Fire("BAG_UPDATE_DELAYED")
assert(ATTR.item == nil, "attribut changé en combat")
COMBAT = false
Fire("PLAYER_REGEN_ENABLED")
assert(ATTR.type == "item" and ATTR.item == "item:9500" and ItineraireItemButton:IsShown(), "bouton de l'objet de quête")

-- 8. Action bloquée par le jeu : la partie « vols » se coupe, le reste continue.
Fire("ADDON_ACTION_BLOCKED", "Itineraire", "TakeTaxiNode()")
assert(Printed("le jeu a bloqué"))
Fire("TAXIMAP_OPENED")
Advance(0.5)
assert(Called("TakeTaxiNode") == 1, "les vols devraient être coupés après un blocage")
assert(ns.ReportText():find("flights=BLOQUÉ"), "rapport sans le blocage")
assert(ns.ReportText():find("Pilote : ACTIF"))

-- 9. Arrêt : Questie retrouve ses réglages ; plus rien d'automatique.
P.SetOn(false)
assert(Questie.db.profile.autocomplete == true and Questie.db.profile.autoAccept.enabled == true, "Questie pas remis comme avant")
before = Called("AcceptQuest")
Fire("QUEST_DETAIL")
assert(Called("AcceptQuest") == before, "pilote arrêté : il ne doit plus rien prendre")
SlashCmdList.ITINERAIRE("pilote")
assert(P.Config().on == true, "/iti pilote ne le relance pas")
ns.Options.Toggle(true, "pilote")
ns.Options.Refresh()
print("OK pilote")
