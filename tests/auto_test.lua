-- Autonomie (pilote) : talents selon le plan (demander / automatique), équipement mis tout seul (lié quand équipé :
-- question), objet remis à la main laissé tranquille, sac dans un emplacement libre, action bloquée par le jeu.
dofile(TESTS .. "/wow_mock.lua")
time = function() return 1800000000 end

LEVEL = 22
function UnitLevel() return LEVEL end
function UnitClass() return "Guerrier", "WARRIOR", 1 end
function UnitFactionGroup() return "Horde", "Horde" end
COMBAT = false
function InCombatLockdown() return COMBAT end
function UnitIsDeadOrGhost() return false end

-- Arbres de talents factices (forme Classic de GetTalentInfo) : guerrier, onglets Armes / Fureur / Protection.
-- Noms en français pour les sorts connus du faux GetSpellInfo, sinon le nom anglais (le plan essaie les deux).
SPELLS = { [12298] = "Spécialisation Bouclier", [12797] = "Vengeance améliorée", [12297] = "Anticipation",
	[1310316] = "Maître de la défense", [12975] = "Dernier rempart", [12792] = "Défi" }
function GetSpellInfo(id) return SPELLS[id] end
local function T(name, tier, max) return { name = name, tier = tier, max = max, rank = 0 } end
TREES = {
	{ name = "Armes", talents = { T("Frappe héroïque améliorée", 1, 3), T("Déviation", 1, 5) } },
	{ name = "Fureur", talents = { T("Cruauté", 1, 5) } },
	{ name = "Protection", talents = {
		T("Spécialisation Bouclier", 1, 5), T("Iron Will", 1, 5), T("Vengeance améliorée", 2, 3), T("Anticipation", 2, 5),
		T("Maître de la défense", 3, 2), T("Dernier rempart", 3, 1), T("Défi", 3, 3),
		-- (pas de « Vanguard » : un talent introuvable est sauté)
	} },
}
local function Spent()
	local n = 0
	for _, tree in ipairs(TREES) do for _, t in ipairs(tree.talents) do n = n + t.rank end end
	return n
end
local function TreePts(tab)
	local n = 0
	for _, t in ipairs(TREES[tab].talents) do n = n + t.rank end
	return n
end
function GetNumTalentTabs() return #TREES end
function GetNumTalents(tab) return #TREES[tab].talents end
function GetTalentTabInfo(tab) return TREES[tab].name, "icon", TreePts(tab), "file" end
function GetTalentInfo(tab, i)
	local t = TREES[tab].talents[i]
	return t.name, "icon", t.tier, 1, t.rank, t.max, false, true
end
function UnitCharacterPoints() return math.max(0, LEVEL - 9 - Spent()) end
LEARNED = {}
function LearnTalent(tab, i)
	local t = TREES[tab].talents[i]
	assert(not COMBAT, "talent appris en combat")
	assert(UnitCharacterPoints() > 0, "plus de point")
	assert((t.tier - 1) * 5 <= TreePts(tab), "palier pas débloqué : " .. t.name)
	assert(t.rank < t.max, "rang max dépassé : " .. t.name)
	t.rank = t.rank + 1
	LEARNED[#LEARNED + 1] = t.name .. " " .. t.rank
	C_Timer.After(0.1, function() Fire("CHARACTER_POINTS_CHANGED", -1) end)
	return true
end

-- Objets
ITEMS = {}
local function item(id, name, equipLoc, classID, subclassID, req, stats, bindType)
	ITEMS[id] = { name = name, equipLoc = equipLoc, classID = classID, subclassID = subclassID, req = req or 10,
		stats = stats or {}, sell = 100, quality = 2, ilvl = (req or 10) + 5, bind = bindType or 1 }
end
local function link(id) return "|cff1eff00|Hitem:" .. id .. "::::::::|h[" .. ITEMS[id].name .. "]|h|r" end
local function idOf(x) return type(x) == "number" and x or tonumber(tostring(x):match("item:(%d+)")) end
C_Item = {
	GetItemInfo = function(x)
		local id = idOf(x)
		local it = ITEMS[id]
		if not it then return nil end
		return it.name, link(id), it.quality, it.ilvl, it.req, "", "", 1, it.equipLoc, "icon" .. id, it.sell, it.classID,
			it.subclassID, it.bind
	end,
	GetItemInfoInstant = function(x)
		local id = idOf(x)
		local it = ITEMS[id]
		if not it then return nil end
		return id, "", "", it.equipLoc, "icon" .. id, it.classID, it.subclassID
	end,
	GetItemStats = function(l) local it = ITEMS[idOf(l)] return it and it.stats end,
	RequestLoadItemDataByID = function() end,
	GetItemSpell = function(l) return idOf(l) == 7300 and "Utiliser" or nil end,
}
item(7100, "Vieux casque", "INVTYPE_HEAD", 4, 3, 10, { RESISTANCE0_NAME = 60, ITEM_MOD_STAMINA_SHORT = 1 })
item(7101, "Casque lié", "INVTYPE_HEAD", 4, 3, 18, { RESISTANCE0_NAME = 160, ITEM_MOD_STAMINA_SHORT = 6 })
item(7102, "Tunique de cuir", "INVTYPE_CHEST", 4, 2, 8, { RESISTANCE0_NAME = 60, ITEM_MOD_STAMINA_SHORT = 1 })
item(7103, "Cotte à vendre", "INVTYPE_CHEST", 4, 3, 18, { RESISTANCE0_NAME = 220, ITEM_MOD_STAMINA_SHORT = 7 }, 2)
item(7104, "Bottes à peine mieux", "INVTYPE_FEET", 4, 3, 18, { RESISTANCE0_NAME = 81, ITEM_MOD_STAMINA_SHORT = 2 })
item(7105, "Bottes portées", "INVTYPE_FEET", 4, 3, 18, { RESISTANCE0_NAME = 80, ITEM_MOD_STAMINA_SHORT = 2 })
item(7106, "Sac en lin", "", 1, 0, 0, {})
item(7300, "Bijou à effet", "INVTYPE_TRINKET", 4, 0, 10, { ITEM_MOD_STAMINA_SHORT = 1 })
item(7301, "Bijou meilleur", "INVTYPE_TRINKET", 4, 0, 18, { ITEM_MOD_STAMINA_SHORT = 8 })
EQUIPPED = { [1] = 7100, [5] = 7102, [8] = 7105, [13] = 7300, [14] = 7300 }
function GetInventoryItemLink(_, slot) return EQUIPPED[slot] and link(EQUIPPED[slot]) end
function GetInventoryItemID(_, slot) return EQUIPPED[slot] end
function GetItemCount() return 0 end

-- Sacs : sac 0 seulement (8 places) ; emplacements de sac 1 à 4 = inventaire 20 à 23.
BAGS = { [0] = {} }
local function put(slot, id, bound) BAGS[0][slot] = { hyperlink = link(id), itemID = id, isBound = bound } end
put(1, 7101, true) -- casque lié : à mettre tout seul
put(2, 7103, false) -- cotte lié quand équipé : question
put(3, 7104, true) -- bottes à peine mieux : non
put(4, 7106, false) -- sac
put(5, 7301, true) -- bijou meilleur mais les deux bijoux portés ont un effet « Utiliser » : non
C_Container = {
	GetContainerNumSlots = function(bag) return bag == 0 and 8 or 0 end,
	GetContainerItemInfo = function(bag, slot) return BAGS[bag] and BAGS[bag][slot] end,
	ContainerIDToInventoryID = function(bag) return 19 + bag end,
	PickupContainerItem = function(bag, slot) CURSOR = { bag = bag, slot = slot } end,
	GetContainerNumFreeSlots = function() return 4, 0 end,
	GetContainerItemQuestInfo = function() return {} end,
}
function PutItemInBag(inv)
	assert(CURSOR, "rien sur le curseur")
	local e = BAGS[CURSOR.bag][CURSOR.slot]
	EQUIPPED[inv] = e.itemID
	BAGS[CURSOR.bag][CURSOR.slot] = nil
	CURSOR = nil
	PUT_BAG = inv
end
function CursorHasItem() return CURSOR ~= nil end
function ClearCursor() CURSOR = nil end
EQUIP_CALLS = {}
local function EquipByName(l, slot)
	assert(not COMBAT, "équipé en combat")
	local id = idOf(l)
	for s, e in pairs(BAGS[0]) do
		if e.itemID == id then
			local old = EQUIPPED[slot]
			EQUIPPED[slot] = id
			BAGS[0][s] = old and { hyperlink = link(old), itemID = old, isBound = true } or nil
			EQUIP_CALLS[#EQUIP_CALLS + 1] = id .. "@" .. slot
			C_Timer.After(0.05, function() Fire("PLAYER_EQUIPMENT_CHANGED", slot, true) end)
			C_Timer.After(0.1, function() Fire("BAG_UPDATE_DELAYED") end)
			return
		end
	end
	error("objet pas dans les sacs : " .. tostring(id))
end
-- (comme sur Forever : prendre l'objet du sac puis le poser sur l'emplacement)
function EquipCursorItem(slot)
	assert(CURSOR, "rien sur le curseur")
	local e = BAGS[CURSOR.bag][CURSOR.slot]
	CURSOR = nil
	EquipByName(e.hyperlink, slot)
end

local files = { "Donnees/Butins.lua", "Donnees/Objets.lua", "Donnees/Entrees.lua", "Donnees/Recettes.lua", "Donnees/PNJ.lua",
	"Donnees/Marchandises.lua", "Solver.lua", "Geo.lua", "Data.lua", "DungeonJournal.lua", "Planner.lua", "Guide.lua", "UI.lua",
	"Options.lua", "Group.lua", "Gear.lua", "GearUI.lua", "Pilote.lua", "Autonomie.lua", "Core.lua" }
PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.515, 0.303
local ns = LoadAddon(ADDON_DIR, files)
Fire("ADDON_LOADED", "Itineraire")
-- (aucun point mis : le rôle deviné serait « mêlée » ; ce guerrier veut tanker)
ns.db.pilote = { talentPlan = "tank" }
Fire("PLAYER_LOGIN")
Advance(10)
local A, P = ns.Auto, ns.Pilote
local cfg = P.Config()
assert(cfg.talents == "demander" and cfg.equip == true and cfg.equipBoE == "demander" and cfg.talentPlan == "tank", "réglages")

-- 1. Équipement : le casque lié est mis tout seul ; la cotte (lié quand équipé) fait l'objet d'une question ;
--    les bottes à peine mieux et le bijou (effet « Utiliser » porté) restent dans les sacs ; le sac est mis.
assert(EQUIPPED[1] == 7101, "casque lié pas équipé : " .. table.concat(EQUIP_CALLS, ","))
assert(EQUIPPED[8] == 7105, "bottes à peine mieux équipées")
assert(EQUIPPED[13] == 7300 and EQUIPPED[14] == 7300, "bijou à effet remplacé")
assert(PUT_BAG == 20 and EQUIPPED[20] == 7106, "sac pas mis dans l'emplacement libre")
local q = ItineraireQuestion
assert(q and q:IsShown(), "pas de question")
print("question : " .. q.text:GetText():gsub("\n", " / "))

-- La question en cours est celle des talents (posée en premier) ou de la cotte : on répond dans l'ordre.
local function Answer(label)
	assert(q:IsShown(), "pas de question à répondre")
	for _, b in ipairs(q.buttons) do
		if b:IsShown() and b:GetText() == label then
			b.scripts.OnClick(b)
			return
		end
	end
	error("pas de bouton « " .. label .. " » dans : " .. tostring(q.text:GetText()))
end

-- 2. Talents en mode « demander » : une question par point, « Apprendre » met le point.
assert(q.text:GetText():find("Spécialisation Bouclier") and q.text:GetText():find("13 points libres"),
	"question de talent : " .. tostring(q.text:GetText()))
Answer("Apprendre")
Advance(2)
assert(LEARNED[1] == "Spécialisation Bouclier 1", "talent : " .. tostring(LEARNED[1]))
-- Les questions passent dans l'ordre : la cotte (posée pendant la 1re), puis le point suivant.
assert(q:IsShown() and q.text:GetText():find("Cotte à vendre"), "question de la cotte : " .. tostring(q.text:GetText()))
Answer("Équiper")
Advance(2)
assert(EQUIPPED[5] == 7103, "cotte pas équipée après « Équiper »")
-- « Plus tard » : plus de question de talent avant le niveau suivant
assert(q:IsShown() and q.text:GetText():find("Spécialisation Bouclier"), "2e question de talent : " .. tostring(q.text:GetText()))
Answer("Plus tard")
Advance(5)
assert(#LEARNED == 1, "talent appris malgré « Plus tard »")
assert(not q:IsShown(), "encore une question : " .. tostring(q.text:GetText()))

-- 3. Objet remis à la main : laissé tranquille.
Advance(5)
local headSlot = nil
for s, e in pairs(BAGS[0]) do if e.itemID == 7100 then headSlot = s end end
BAGS[0][headSlot] = { hyperlink = link(7101), itemID = 7101, isBound = true }
EQUIPPED[1] = 7100
Fire("PLAYER_EQUIPMENT_CHANGED", 1, true)
Fire("BAG_UPDATE_DELAYED")
Advance(3)
assert(EQUIPPED[1] == 7100, "le casque remis à la main a été remplacé de nouveau")

-- 4. Niveau suivant : « Toujours » passe en automatique et met tous les points, palier par palier, dans l'ordre du plan.
LEVEL = 23
Fire("PLAYER_LEVEL_UP", 23)
Advance(3)
assert(q:IsShown() and q.text:GetText():find("Spécialisation Bouclier"), "question au niveau suivant")
Answer("Toujours")
Advance(10)
assert(cfg.talents == "auto", "pas passé en automatique")
print("appris : " .. table.concat(LEARNED, ", "))
assert(#LEARNED == 14, "points mis : " .. #LEARNED)
local prot = TREES[3].talents
assert(prot[1].rank == 5 and prot[3].rank == 3 and prot[4].rank == 2 and prot[5].rank == 2 and prot[6].rank == 1
	and prot[7].rank == 1, "ordre du plan non suivi")
assert(UnitCharacterPoints() == 0, "points restants")

-- 5. En combat : rien ; à la sortie du combat : le point est mis.
LEVEL = 24
COMBAT = true
Fire("PLAYER_LEVEL_UP", 24)
Advance(3)
assert(#LEARNED == 14, "talent appris en combat")
COMBAT = false
Fire("PLAYER_REGEN_ENABLED")
Advance(3)
assert(#LEARNED == 15 and prot[7].rank == 2, "point pas mis après le combat : " .. LEARNED[#LEARNED])

-- 6. Le jeu bloque LearnTalent : la partie talents se coupe, le reste continue.
Fire("ADDON_ACTION_BLOCKED", "Itineraire", "LearnTalent()")
LEVEL = 25
Fire("PLAYER_LEVEL_UP", 25)
Advance(3)
assert(#LEARNED == 15, "talent appris alors que le jeu l'a bloqué")
local report = ns.ReportText()
assert(report:find("Autonomie : talents : plan « Protection"), "rapport : " .. tostring(report:match("Autonomie[^\n]*")))
assert(report:find("talents=BLOQU"), "blocage absent du rapport : " .. tostring(report:match("Pilote :[^\n]*")))
print(report:match("Autonomie[^\n]*"))
SlashCmdList.ITINERAIRE("talents")
print("OK autonomie")

-- 7. Plans de toutes les classes : un plan par rôle que la fenêtre Équipement peut deviner, 51 points chacun.
local ROLES = { WARRIOR = { "melee", "tank" }, PALADIN = { "healer", "tank", "melee" }, DRUID = { "caster", "tank", "healer", "melee" },
	SHAMAN = { "caster", "melee", "healer" }, PRIEST = { "healer", "caster" }, HUNTER = { "ranged" }, ROGUE = { "melee" },
	MAGE = { "caster" }, WARLOCK = { "caster" } }
local count = 0
for class, roles in pairs(ROLES) do
	local plans = A.PLANS[class]
	assert(plans, "pas de plans pour " .. class)
	for _, role in ipairs(roles) do
		assert(plans[role] and plans[role].role == role, class .. " : pas de plan « " .. role .. " »")
	end
	for key, plan in pairs(plans) do
		count = count + 1
		assert(#plan.steps == 51, class .. "/" .. key .. " : " .. #plan.steps .. " points")
		assert(ROLES[class] and plan.label ~= "", "libellé")
	end
end
print("plans : " .. count)
print("OK plans de toutes les classes")
