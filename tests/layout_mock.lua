-- Faux grimoire, formes et barres d'action pour les tests de rangement par forme (druide, voleur).
-- Avant dofile : CLASS_TOKEN, CLASS_NAME, LEVEL, NAMES, CLASS (sorts appris), FORMS (sorts des formes), PAGE_OF
-- (fonction : forme active, camouflé -> page de la barre principale).
dofile(TESTS .. "/wow_mock.lua")
time = function() return 1800000000 end
function UnitLevel() return LEVEL end
function UnitClass() return CLASS_NAME, CLASS_TOKEN, 1 end
function UnitFactionGroup() return "Horde", "Horde" end
COMBAT = false
function InCombatLockdown() return COMBAT end
WEAPONS = {} -- [emplacement] = { classID, subclassID }
C_Item = { GetItemInfo = function() return nil end, GetItemStats = function() return nil end,
	RequestLoadItemDataByID = function() end,
	GetItemInfoInstant = function(link)
		local w = WEAPONS[tonumber(tostring(link):match("arme(%d+)") or 0)]
		if w then return 1, "Arme", "Arme", "INVTYPE_WEAPON", 0, w[1], w[2] end
	end }
function GetInventoryItemLink(_, slot) if WEAPONS[slot] then return "arme" .. slot end end
function GetItemCount() return 0 end

KNOWN = {}
BOOK = { { spellID = 6603, itemType = 1 } } -- onglet Général : Attaque
NAMES[6603] = "Attaque"
for _, id in ipairs(CLASS) do
	BOOK[#BOOK + 1] = { spellID = id, itemType = 1 }
	KNOWN[id] = true
end
for _, id in ipairs(FORMS) do
	BOOK[#BOOK + 1] = { spellID = id, itemType = 1 }
	KNOWN[id] = true
end
function Learn(id)
	KNOWN[id] = true
	BOOK[#BOOK + 1] = { spellID = id, itemType = 1 }
end
function IsPlayerSpell(id) return KNOWN[id] == true end
Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1, FutureSpell = 2 } }
C_SpellBook = {
	GetNumSpellBookSkillLines = function() return 2 end,
	GetSpellBookSkillLineInfo = function(i)
		if i == 1 then return { name = "Général", itemIndexOffset = 0, numSpellBookItems = 1 } end
		return { name = CLASS_NAME, itemIndexOffset = 1, numSpellBookItems = #BOOK - 1 }
	end,
	GetSpellBookItemInfo = function(i)
		local e = BOOK[i]
		return e and { spellID = e.spellID, name = NAMES[e.spellID], itemType = e.itemType, isPassive = false }
	end,
}
C_Spell = {
	GetSpellName = function(id) return NAMES[id] end,
	GetSpellSubtext = function() return nil end,
	PickupSpell = function(id) CURSOR = { "spell", id } end,
}
C_ActionBar = { IsHighestSpellRank = function() return true end }

ACTIVE, STEALTHED = nil, false -- forme active (sort), camouflé
function GetNumShapeshiftForms() return #FORMS end
function GetShapeshiftFormInfo(i) return "icon", FORMS[i] == ACTIVE, true, FORMS[i] end
function IsStealthed() return STEALTHED end
function GetBonusBarOffset() return PAGE_OF(ACTIVE, STEALTHED) end

ACTIONS = {}
function GetActionInfo(slot) local a = ACTIONS[slot] if a then return a[1], a[2] end end
function HasAction(slot) return ACTIONS[slot] ~= nil end
function GetCursorInfo() if CURSOR then return CURSOR[1], CURSOR[2] end end
function ClearCursor() CURSOR = nil end
function PlaceAction(slot)
	assert(not COMBAT, "barre touchée en combat")
	local old = ACTIONS[slot]
	ACTIONS[slot] = CURSOR
	CURSOR = old
end
function PickupAction(slot)
	assert(not COMBAT, "barre touchée en combat")
	assert(CURSOR == nil, "PickupAction avec un curseur occupé")
	CURSOR = ACTIONS[slot]
	ACTIONS[slot] = nil
end
local function Button(action, visible)
	return { action = action, IsVisible = function() return visible end }
end
-- La barre principale suit la page de la forme ; en bas à gauche (61-72) et en bas à droite (49-60) affichées.
function SetForm(form, stealthed)
	ACTIVE, STEALTHED = form, stealthed or false
	local offset = PAGE_OF(ACTIVE, STEALTHED)
	for i = 1, 12 do
		_G["ActionButton" .. i] = Button(offset == 0 and i or (72 + (offset - 1) * 12 + i), true)
	end
end
for i = 1, 12 do
	_G["MultiBarBottomLeftButton" .. i] = Button(60 + i, true)
	_G["MultiBarBottomRightButton" .. i] = Button(48 + i, true)
end
SetForm(nil, false)

function A(kind, id) return { kind, id } end
function Is(slot, kind, id)
	local a = ACTIONS[slot]
	return a ~= nil and a[1] == kind and a[2] == id
end
function Expect(slot, kind, id, what)
	local a = ACTIONS[slot]
	assert(Is(slot, kind, id), what .. " : case " .. slot .. " = " .. (a and (a[1] .. " " .. tostring(a[2])) or "vide")
		.. ", attendu " .. kind .. " " .. tostring(id))
end
function ExpectPage(base, ids, what)
	for key = 1, 12 do
		if ids[key] then
			Expect(base + key, "spell", ids[key], what .. ", touche " .. key)
		else
			local a = ACTIONS[base + key]
			assert(not (a and a[1] == "spell" and NAMES[a[2]] and a[2] ~= 6603), what .. ", touche " .. key
				.. " devrait être libre : " .. tostring(a and a[2]))
		end
	end
end
function Printed(pattern)
	for _, m in ipairs(PRINTED) do
		if m:find(pattern) then return m end
	end
end
function Answer(label)
	local q = ItineraireQuestion
	assert(q and q:IsShown(), "pas de question")
	for _, b in ipairs(q.buttons) do
		if b:IsShown() and b:GetText() == label then
			b.scripts.OnClick(b)
			return
		end
	end
	error("pas de bouton « " .. label .. " » : " .. tostring(q.text:GetText()))
end
function Start()
	local files = { "Donnees/Butins.lua", "Donnees/Objets.lua", "Donnees/Entrees.lua", "Donnees/Recettes.lua",
		"Donnees/PNJ.lua", "Donnees/Marchandises.lua", "Solver.lua", "Geo.lua", "Data.lua", "DungeonJournal.lua",
		"Planner.lua", "Guide.lua", "UI.lua", "Options.lua", "Group.lua", "Gear.lua", "GearUI.lua", "Pilote.lua",
		"Autonomie.lua", "Core.lua" }
	PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.515, 0.303
	local ns = LoadAddon(ADDON_DIR, files)
	Fire("ADDON_LOADED", "Itineraire")
	ns.db.pilote = { talents = "non" }
	Fire("PLAYER_LOGIN")
	Advance(10)
	return ns
end
