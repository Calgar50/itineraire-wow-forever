-- Barres d'action (pilote) : les sorts de la classe qui manquent vont dans les cases vides des barres affichées (pas
-- la barre principale quand elle change avec la posture), un sort passe à son rang supérieur à la même place, rien en
-- combat, un sort enlevé à la main ne revient pas, ni formes / postures, ni passifs, ni sorts pas encore appris.
dofile(TESTS .. "/wow_mock.lua")
time = function() return 1800000000 end
function UnitLevel() return 22 end
function UnitClass() return "Guerrier", "WARRIOR", 1 end
function UnitFactionGroup() return "Horde", "Horde" end
COMBAT = false
function InCombatLockdown() return COMBAT end
C_Item = { GetItemInfo = function() return nil end, GetItemInfoInstant = function() return nil end,
	GetItemStats = function() return nil end, RequestLoadItemDataByID = function() end }
function GetInventoryItemLink() return nil end
function GetItemCount() return 0 end

-- Grimoire (API de Forever : C_SpellBook)
NAMES = { [101] = "Frappe héroïque", [102] = "Frappe héroïque", [200] = "Charge", [300] = "Posture de combat",
	[400] = "Parade", [500] = "Coup de tonnerre", [600] = "Cri de guerre", [700] = "Fendoir", [800] = "Exécution",
	[900] = "Pierre de foyer" }
RANKS = { [101] = "Rang 1", [102] = "Rang 2" }
BOOK = {
	{ spellID = 900, itemType = 1 }, -- onglet Général
	{ spellID = 101, itemType = 1 }, { spellID = 102, itemType = 1 }, { spellID = 200, itemType = 1 },
	{ spellID = 300, itemType = 1 }, { spellID = 400, itemType = 1, isPassive = true }, { spellID = 500, itemType = 1 },
	{ spellID = 600, itemType = 1 }, { spellID = 700, itemType = 2 }, -- (2 = pas encore appris)
}
CLASS_COUNT = 8
Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1, FutureSpell = 2 } }
C_SpellBook = {
	GetNumSpellBookSkillLines = function() return 2 end,
	GetSpellBookSkillLineInfo = function(i)
		if i == 1 then return { name = "Général", itemIndexOffset = 0, numSpellBookItems = 1 } end
		return { name = "Guerrier", itemIndexOffset = 1, numSpellBookItems = CLASS_COUNT }
	end,
	GetSpellBookItemInfo = function(i)
		local e = BOOK[i]
		return e and { spellID = e.spellID, name = NAMES[e.spellID], itemType = e.itemType, isPassive = e.isPassive or false }
	end,
}
C_Spell = {
	GetSpellName = function(id) return NAMES[id] end,
	GetSpellSubtext = function(id) return RANKS[id] end,
	PickupSpell = function(id) CURSOR = { "spell", id } end,
}
C_ActionBar = { IsHighestSpellRank = function(id) return id ~= 101 end }
function GetNumShapeshiftForms() return 1 end
function GetShapeshiftFormInfo() return "icon", true, true, 300 end
BONUS = 1 -- en posture : la barre principale change, on n'y touche pas
function GetBonusBarOffset() return BONUS end

-- Barres : principale (1-12), en bas à gauche (61-72) affichée, en bas à droite (49-60) cachée.
ACTIONS = {}
for s = 1, 12 do ACTIONS[s] = { "macro", s } end
ACTIONS[1] = { "spell", 101 }
ACTIONS[61] = { "spell", 200 }
PLACED = {}
function GetActionInfo(slot) local a = ACTIONS[slot] if a then return a[1], a[2] end end
function HasAction(slot) return ACTIONS[slot] ~= nil end
function GetCursorInfo() if CURSOR then return CURSOR[1], CURSOR[2] end end
function ClearCursor() CURSOR = nil end
function PlaceAction(slot)
	assert(not COMBAT, "barre touchée en combat")
	local old = ACTIONS[slot]
	ACTIONS[slot] = CURSOR
	CURSOR = old
	PLACED[#PLACED + 1] = slot
end
local function Button(action, visible)
	return { action = action, IsVisible = function() return visible end }
end
for i = 1, 12 do
	_G["ActionButton" .. i] = Button(i, true)
	_G["MultiBarBottomLeftButton" .. i] = Button(60 + i, true)
	_G["MultiBarBottomRightButton" .. i] = Button(48 + i, false)
end

local files = { "Donnees/Butins.lua", "Donnees/Objets.lua", "Donnees/Entrees.lua", "Donnees/Recettes.lua", "Donnees/PNJ.lua",
	"Donnees/Marchandises.lua", "Solver.lua", "Geo.lua", "Data.lua", "DungeonJournal.lua", "Planner.lua", "Guide.lua", "UI.lua",
	"Options.lua", "Group.lua", "Gear.lua", "GearUI.lua", "Pilote.lua", "Autonomie.lua", "Core.lua" }
PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.515, 0.303
local ns = LoadAddon(ADDON_DIR, files)
Fire("ADDON_LOADED", "Itineraire")
ns.db.pilote = { talents = "non" }
Fire("PLAYER_LOGIN")
Advance(10)

-- 1. Rang supérieur à la même place ; sorts qui manquent dans les cases vides de la barre affichée.
local function On(id) for s, a in pairs(ACTIONS) do if a[1] == "spell" and a[2] == id then return s end end end
assert(On(102) == 1 and not On(101), "Frappe héroïque pas passée au rang 2")
assert(On(500) == 62 and On(600) == 63, "sorts manquants pas posés : " .. tostring(On(500)) .. " " .. tostring(On(600)))
assert(not On(300) and not On(400) and not On(700) and not On(900), "posture, passif, sort pas appris ou général posé")
assert(On(200) == 61, "Charge déplacée")
assert(CURSOR == nil, "curseur pas vidé")
for _, s in ipairs(PLACED) do assert(s == 1 or (s >= 61 and s <= 72), "case hors des barres affichées : " .. s) end

-- 2. Un sort enlevé à la main ne revient pas.
ACTIONS[62] = nil
Fire("SPELLS_CHANGED")
Advance(3)
assert(not On(500), "Coup de tonnerre remis alors que le joueur l'a enlevé")

-- 3. Nouveau sort appris en combat : posé après le combat.
BOOK[#BOOK + 1] = { spellID = 800, itemType = 1 }
CLASS_COUNT = CLASS_COUNT + 1
COMBAT = true
Fire("SPELLS_CHANGED")
Advance(3)
assert(not On(800), "posé en combat")
COMBAT = false
Fire("PLAYER_REGEN_ENABLED")
Advance(3)
assert(On(800) == 62, "Exécution pas posée après le combat : " .. tostring(On(800)))

-- 4. Hors posture, la barre principale sert aussi (une fois l'autre barre pleine).
BONUS = 0
ACTIONS[2] = nil
for s = 61, 72 do ACTIONS[s] = ACTIONS[s] or { "macro", s } end
BOOK[#BOOK + 1] = { spellID = 700, itemType = 1 } -- Fendoir appris
CLASS_COUNT = CLASS_COUNT + 1
Fire("SPELLS_CHANGED")
Advance(3)
assert(On(700) == 2, "Fendoir pas posé sur la barre principale : " .. tostring(On(700)))

-- 5. Le jeu bloque PlaceAction : la partie se coupe.
Fire("ADDON_ACTION_BLOCKED", "Itineraire", "PlaceAction()")
local n = #PLACED
BOOK[#BOOK + 1] = { spellID = 900, itemType = 1 }
CLASS_COUNT = CLASS_COUNT + 1
ACTIONS[3] = nil
Fire("SPELLS_CHANGED")
Advance(3)
assert(#PLACED == n, "barres touchées alors que le jeu a bloqué")
assert(ns.ReportText():find("actionbars=BLOQU"), "blocage absent du rapport")
print(ns.ReportText():match("Autonomie[^\n]*"))
print("OK barres d'action")
