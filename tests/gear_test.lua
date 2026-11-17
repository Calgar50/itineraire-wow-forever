-- Équipement : note des objets selon le rôle, récompense conseillée au rendu, recherche des améliorations
-- dans la base (récompenses, vendeurs, butins), objectifs « Y aller » dans le trajet, versions et nouveautés.
dofile(TESTS .. "/wow_mock.lua")
time = function() return 1800000000 end

-- Guerrier, talents en Protection -> rôle tank.
function UnitClass() return "Guerrier", "WARRIOR", 1 end
TALENTS = { { "Armes", 0 }, { "Fureur", 0 }, { "Protection", 5 } }
function GetTalentTabInfo(tab) local t = TALENTS[tab] return t[1], "icon", t[2], "file" end

-- Objets du jeu : infos + caractéristiques (GetItemInfo / GetItemStats).
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
	GetItemStats = function(l) local it = ITEMS[idOf(l)] return it and it.stats end,
	RequestLoadItemDataByID = function() end,
}
-- Porté : un bouclier faible, une épée faible, un torse en cuir ; tête vide.
item(7100, "Vieux bouclier", "INVTYPE_SHIELD", 4, 6, 8, { RESISTANCE0_NAME = 50, ITEM_MOD_STAMINA_SHORT = 1 })
item(7101, "Épée émoussée", "INVTYPE_WEAPON", 2, 7, 8, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 5 })
item(7102, "Tunique de cuir", "INVTYPE_CHEST", 4, 2, 8, { RESISTANCE0_NAME = 60, ITEM_MOD_STAMINA_SHORT = 2 })
EQUIPPED = { [17] = 7100, [16] = 7101, [5] = 7102 }
function GetInventoryItemLink(_, slot) return EQUIPPED[slot] and link(EQUIPPED[slot]) end
BAGS = {}
function GetItemCount(id) return BAGS[id] or 0 end

-- Pistes :
item(7001, "Bouclier du gardien", "INVTYPE_SHIELD", 4, 6, 14, { RESISTANCE0_NAME = 120, ITEM_MOD_STAMINA_SHORT = 4, ITEM_MOD_BLOCK_VALUE_SHORT = 5 }, 500)
item(7002, "Haubert de mailles", "INVTYPE_CHEST", 4, 3, 15, { RESISTANCE0_NAME = 150, ITEM_MOD_STAMINA_SHORT = 5 }, 800)
item(7003, "Heaume du voleur", "INVTYPE_HEAD", 4, 3, 14, { RESISTANCE0_NAME = 80, ITEM_MOD_STAMINA_SHORT = 3 }, 300)
item(7004, "Baguette de l'apprenti", "INVTYPE_RANGEDRIGHT", 2, 19, 12, { ITEM_MOD_INTELLECT_SHORT = 6 }, 900)
item(7005, "Cuirasse de plaques", "INVTYPE_CHEST", 4, 4, 15, { RESISTANCE0_NAME = 300, ITEM_MOD_STAMINA_SHORT = 8 })
item(7006, "Grande hache", "INVTYPE_2HWEAPON", 2, 1, 15, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 20, ITEM_MOD_STRENGTH_SHORT = 10 })
item(7007, "Heaume trop haut", "INVTYPE_HEAD", 4, 3, 30, { RESISTANCE0_NAME = 200, ITEM_MOD_STAMINA_SHORT = 15 })
item(7008, "Bottes du monde", "INVTYPE_FEET", 4, 3, 14, { RESISTANCE0_NAME = 70, ITEM_MOD_STAMINA_SHORT = 3 })
item(7009, "Gants de plus tard", "INVTYPE_HAND", 4, 3, 15, { RESISTANCE0_NAME = 60, ITEM_MOD_STAMINA_SHORT = 3 })
item(7010, "Anneau du mage", "INVTYPE_FINGER", 4, 0, 15, { ITEM_MOD_STAMINA_SHORT = 5 })
item(7011, "Gants d'étoffe", "INVTYPE_HAND", 4, 1, 12, { RESISTANCE0_NAME = 10, ITEM_MOD_INTELLECT_SHORT = 4 }, 50)
item(7012, "Robe d'étoffe", "INVTYPE_CHEST", 4, 1, 12, { RESISTANCE0_NAME = 20, ITEM_MOD_INTELLECT_SHORT = 5 }, 400)
item(7013, "Cape de la quête", "INVTYPE_CLOAK", 4, 1, 14, { RESISTANCE0_NAME = 20, ITEM_MOD_STAMINA_SHORT = 4 }, 200)

-- La carte : la Croisée (Tarides).
local function npc(id, name, area, pts, level, friendly)
	NPCS[id] = { id = id, name = name, spawns = { [area] = pts }, friendly = friendly, maxLevel = level }
end
npc(9, "Sergra Darkthorn", 17, { { 52.2, 31.0 } }, nil, true)
npc(13, "Gazrog", 17, { { 51.7, 29.9 } }, nil, true)
npc(601, "Marchand d'armures", 17, { { 52.6, 29.6 } }, nil, true)
npc(106, "Zhévra", 17, { { 55, 33 }, { 56, 34 }, { 57, 32 } }, 12, false)
npc(113, "Tranchecrin voleur", 17, { { 45, 60 }, { 46, 61 } }, 15, false)
for i = 1, 10 do npc(800 + i, "Monstre " .. i, 17, { { 30 + i, 70 } }, 15, false) end

-- Journal : une quête dont la récompense est le bouclier.
LOG[1] = { info = { questID = 1001, title = "Les zhévras", level = 15, suggestedGroup = 0 },
	objectives = { { text = "Zhévra tué : 0/6", type = "monster", finished = false, numFulfilled = 0, numRequired = 6 } } }
QUESTS[1001] = { Id = 1001, name = "Les zhévras", level = 15, xp = 900, Finisher = { NPC = { 9 } },
	Objectives = { { spawnList = { { Id = 106, Name = "Zhévra", Spawns = NPCS[106].spawns, Hostile = true } } } } }
-- Quête à prendre (chez Gazrog) qui donne la cape.
QUESTS[2001] = { Id = 2001, name = "Une cape pour toi", level = 15, requiredLevel = 10, xp = 400,
	Starts = { NPC = { 13 } }, Finisher = { NPC = { 13 } }, ObjectiveData = { { Type = "monster", Id = 113 } } }
AVAILABLE[2001] = true
-- Quête pas encore disponible, et quête de mage.
QUESTS[2999] = { Id = 2999, name = "Plus tard", level = 16, xp = 500, Starts = { NPC = { 13 } }, Finisher = { NPC = { 13 } } }
QUESTS[2004] = { Id = 2004, name = "Pour les mages", level = 15, xp = 500, requiredClasses = 128,
	Starts = { NPC = { 13 } }, Finisher = { NPC = { 13 } } }

-- Base d'objets de Questie.
DBITEMS = {
	[7001] = { class = 4, subClass = 6, requiredLevel = 14, questRewards = { 1001 } },
	[7002] = { class = 4, subClass = 3, requiredLevel = 15, vendors = { 601 } },
	[7003] = { class = 4, subClass = 3, requiredLevel = 14, npcDrops = { 113 } },
	[7004] = { class = 2, subClass = 19, requiredLevel = 12, vendors = { 601 } },
	[7005] = { class = 4, subClass = 4, requiredLevel = 15, vendors = { 601 } },
	[7006] = { class = 2, subClass = 1, requiredLevel = 15, vendors = { 601 } },
	[7007] = { class = 4, subClass = 3, requiredLevel = 30, vendors = { 601 } },
	[7008] = { class = 4, subClass = 3, requiredLevel = 14, npcDrops = { 801, 802, 803, 804, 805, 806, 807, 808, 809, 810 } },
	[7009] = { class = 4, subClass = 3, requiredLevel = 15, questRewards = { 2999 } },
	[7010] = { class = 4, subClass = 0, requiredLevel = 15, questRewards = { 2004 } },
	[7013] = { class = 4, subClass = 1, requiredLevel = 14, questRewards = { 2001 } },
	[9001] = { class = 0, requiredLevel = 1 }, -- une potion : ignorée
}
local DB = QuestieLoader:ImportModule("QuestieDB")
DB.ItemPointers = {}
for id in pairs(DBITEMS) do DB.ItemPointers[id] = true end
function DB.QueryItemSingle(id, key) return DBITEMS[id] and DBITEMS[id][key] end

-- Versions : venant de la 1.8.1, Questie mis à jour ; installateur plus ancien que celui attendu.
VERSIONS = { Itineraire = "2.0.0", Questie = "12.10.0", QuestieDB = "1.1.1", ShortestPathForever = "1.39.0", ForeverCore = "1.12.1" }
C_AddOns.GetAddOnMetadata = function(name, field) return field == "Version" and VERSIONS[name] or nil end
ItineraireDB = { wizardDone = true, versions = { Itineraire = "1.8.1", Questie = "12.9.0", QuestieDB = "1.1.1" } }
ItineraireInstallateur = { version = 1, auto = true, verifie = "2026-11-17 10:00" }

PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.515, 0.303
local ns = LoadAddon(ADDON_DIR, { "Solver.lua", "Geo.lua", "Data.lua", "Planner.lua", "Guide.lua", "UI.lua", "Options.lua", "Group.lua", "Gear.lua", "GearUI.lua", "Core.lua" })
Fire("ADDON_LOADED", "Itineraire")
Fire("PLAYER_LOGIN")
Advance(5)
local G = ns.Gear

local function Printed(pattern)
	for _, m in ipairs(PRINTED) do
		if m:find(pattern) then return m end
	end
end

-- 1. Versions, nouveautés, installateur.
assert(Printed("Questie 12%.9%.0 %-> 12%.10%.0"), "mise à jour de Questie non signalée")
assert(Printed("Itinéraire 1%.8%.1 %-> 2%.0%.0"), "mise à jour d'Itinéraire non signalée")
assert(Printed("nouveautés de la version 1%.9%.0") and Printed("nouveautés de la version 2%.0%.0"), "nouveautés sautées non affichées")
assert(Printed("nouvel installateur"), "installateur trop ancien non signalé")
assert(ns.db.newsSeen == "2.0.0" and ns.db.versions.Questie == "12.10.0")

-- 2. Rôle et notes.
local role, why = G.Role()
assert(role == "tank" and why:find("Protection"), "rôle : " .. tostring(role) .. " " .. tostring(why))
local e = G.Evaluate(7001)
assert(e and e.slot == 17 and e.gain > 10, "bouclier : gain " .. tostring(e and e.gain))
assert(not G.Evaluate(7004), "une baguette pour un guerrier")
assert(not G.Evaluate(7005), "des plaques avant le niveau 40")
local _, why6 = G.Evaluate(7006)
assert(why6 and why6:find("deux mains"), "tank : pas d'arme à deux mains (" .. tostring(why6) .. ")")
local head = G.Evaluate(7003)
assert(head and head.empty and G.GainText(head) == "emplacement vide")

-- 3. Récompense conseillée au rendu : un cadre par-dessus le bon bouton « choix », et RIEN d'appelé chez Blizzard.
local buttons = {}
-- (le jeu range aussi les récompenses fixes dans RewardButtons : un bouton « reward » en tête)
local fixed = CreateFrame("Button")
fixed.type = "reward"
fixed.GetID = function() return 1 end
for i = 1, 3 do
	buttons[i] = CreateFrame("Button")
	buttons[i].type = "choice"
	buttons[i].GetID = function() return i end
end
QuestInfoRewardsFrame = { RewardButtons = { fixed, buttons[1], buttons[2], buttons[3] } }
CALLED = nil
function QuestInfoItem_OnClick() CALLED = true end
CHOICES = { 7011, 7001, 7004 }
function GetNumQuestChoices() return #CHOICES end
function GetQuestItemLink(_, i) return link(CHOICES[i]) end
function GetQuestItemInfo(_, i) return ITEMS[CHOICES[i]].name, "icon", 1, 2, true end
Fire("QUEST_COMPLETE")
Advance(0.2)
assert(ItineraireRewardMark and ItineraireRewardMark.button == buttons[2], "le cadre n'est pas sur le bouclier")
assert(ItineraireRewardMark:IsShown())
assert(not CALLED, "Itinéraire ne doit rien appeler dans la fenêtre de quête (contamination)")
assert(Printed("récompense conseillée : .*Bouclier du gardien"), "message de récompense absent")
-- Aucune amélioration : la plus chère à revendre.
CHOICES = { 7012, 7004 }
Fire("QUEST_COMPLETE")
Advance(0.2)
assert(ItineraireRewardMark.button == buttons[2] and Printed("aucune récompense ne t'améliore : prends .*Baguette"),
	"repli sur le prix de revente")
-- Objets pas encore chargés : on attend leurs données, puis on conseille.
CHOICES = { 7013, 7002 }
LOADED_LATER = { [7002] = true }
local realInfo = C_Item.GetItemInfo
C_Item.GetItemInfo = function(x) if LOADED_LATER[tonumber(tostring(x):match("item:(%d+)") or x)] then return nil end return realInfo(x) end
PRINTED = {}
Fire("QUEST_COMPLETE")
Advance(0.2)
assert(not Printed("récompense conseillée"), "conseil donné avant d'avoir les objets")
LOADED_LATER = {}
Fire("ITEM_DATA_LOAD_RESULT", 7002, true)
Advance(0.5)
assert(Printed("récompense conseillée : .*Haubert"), "pas de conseil une fois l'objet chargé")
C_Item.GetItemInfo = realInfo
Fire("QUEST_FINISHED")
assert(not ItineraireRewardMark:IsShown(), "cadre encore là après la fermeture")

-- 4. Recherche des améliorations dans la base.
assert(G.Rescan(), "la recherche ne démarre pas")
Advance(2)
assert(G.state.phase == "fini", "recherche pas finie : " .. tostring(G.state.phase) .. " " .. tostring(G.state.error))
local found = {}
for _, x in ipairs(G.results.list) do
	found[x.id] = x
	print(string.format("  %s %s · %s · %s", x.name, G.GainText(x), x.slotName, x.best.text))
end
assert(found[7001] and found[7001].best.kind == "journal", "bouclier : récompense de la quête du journal")
assert(found[7002] and found[7002].best.kind == "vendor", "haubert : vendeur")
assert(found[7003] and found[7003].best.kind == "drop", "heaume : butin")
assert(found[7013] and found[7013].best.kind == "quest", "cape : quête à prendre")
assert(found[7009] and found[7009].best.kind == "later", "gants : quête pas encore disponible")
for _, id in ipairs({ 7004, 7005, 7006, 7007, 7008, 7010 }) do
	assert(not found[id], "objet " .. id .. " ne devrait pas être proposé")
end
assert(G.results.byQuest[1001] and G.results.byQuest[1001].id == 7001)

-- 5. Le rendu de la quête du journal annonce la récompense.
ns.RequestPlan("test", 0)
Advance(5)
local turnin
for _, s in ipairs(ns.plan.order) do
	if s.kind == "turnin" and s.questSet[1001] then turnin = s end
end
assert(turnin and turnin.reward and turnin.subtitle:find("récompense pour toi"), "rendu sans la récompense conseillée")

-- 6. « Y aller » : le vendeur devient une étape, puis disparaît une fois l'objet acheté.
G.SetGoal(7002, true)
Advance(5)
local function GoalStop(id)
	for _, s in ipairs(ns.plan.order) do
		if s.kind == "service" and s.service.kind == "gear" and s.service.item == id then return s end
	end
end
local stop = GoalStop(7002)
assert(stop and stop.title:find("Acheter Haubert de mailles chez Marchand d'armures"), "pas d'étape pour le vendeur")
assert(SP_ROUTES[#SP_ROUTES][1] and true)
for _, s in ipairs(SP_ROUTES[#SP_ROUTES]) do
	assert(s.kind ~= "vendor", "« vendor » fait planter Shortest Path")
end
BAGS[7002] = 1
Fire("BAG_UPDATE_DELAYED")
Advance(5)
assert(not GoalStop(7002), "l'étape reste après l'achat")
assert(not G.IsGoal(7002) and Printed("objectif d'équipement atteint"))

-- 7. « Y aller » sur une récompense de quête à prendre : la quête est proposée (prise chez Gazrog).
G.SetGoal(7013, true)
Advance(5)
local picked = false
for _, q in ipairs(ns.plan.candidates or {}) do
	if q.id == 2001 then picked = true end
end
assert(picked, "la quête qui donne la cape n'est pas proposée")

-- 8. Rôle mêlée : la hache à deux mains devient une amélioration.
G.Config().role = "melee"
G.ResetWorn()
assert(G.Rescan())
Advance(2)
local axe
for _, x in ipairs(G.results.list) do if x.id == 7006 then axe = x end end
assert(axe and axe.slot == 16, "mêlée : la hache à deux mains devrait être proposée")
assert(ns.ReportText():find("Équipement : rôle mêlée %(réglage%)"), "rapport sans la ligne Équipement")
assert(ns.ReportText():find("installateur v1"), "rapport sans l'état des mises à jour")

-- 9. Ignorer un objet.
G.Ignore(7006)
for _, x in ipairs(G.results.list) do assert(x.id ~= 7006) end

-- 10. Fenêtre Équipement : s'ouvre et se remplit sans erreur.
ns.GearUI.Toggle(true)
assert(ItineraireGear and ItineraireGear:IsShown())
ns.GearUI.Refresh()
-- 11. Réglages : onglet Équipement (rôle, récompenses) et état des mises à jour.
ns.Options.Toggle(true, "equipement")
ns.Options.Refresh()
ns.Options.Toggle(true, "addons")
ns.Options.Refresh()
print("OK équipement")
