-- Barres rangées par posture (guerrier tank, niveau 25) : chaque touche garde son rôle dans chaque posture, les autres
-- sorts sur la barre fixe, objets et macros déplacés (jamais effacés), annulation exacte, entretien (sort d'attente
-- remplacé, objet « garé » qui repart, case changée par le joueur laissée, sort enlevé pas remis, rangs supérieurs
-- partout, rien en combat), refus si la barre principale ne suit pas les pages attendues.
dofile(TESTS .. "/wow_mock.lua")
time = function() return 1800000000 end
function UnitLevel() return 25 end
function UnitClass() return "Guerrier", "WARRIOR", 1 end
function UnitFactionGroup() return "Horde", "Horde" end
COMBAT = false
function InCombatLockdown() return COMBAT end
C_Item = { GetItemInfo = function() return nil end, GetItemInfoInstant = function() return nil end,
	GetItemStats = function() return nil end, RequestLoadItemDataByID = function() end }
function GetInventoryItemLink() return nil end
function GetItemCount() return 0 end

NAMES = {
	[6603] = "Attaque", [78] = "Frappe héroïque", [284] = "Frappe héroïque", [100] = "Charge", [772] = "Pourfendre",
	[6343] = "Coup de tonnerre", [1715] = "Brise-genou", [2687] = "Rage sanguinaire", [7386] = "Fracasser armure",
	[7405] = "Fracasser armure", [355] = "Provocation", [7384] = "Fulgurance", [72] = "Coup de bouclier",
	[1160] = "Cri démoralisant", [6572] = "Vengeance", [694] = "Coup railleur", [2565] = "Maîtrise du blocage",
	[676] = "Désarmement", [845] = "Enchaînement", [20230] = "Représailles", [1240193] = "Heurtoir",
	[402927] = "Sursaut de victoire", [5246] = "Cri d'intimidation", [5308] = "Exécution", [6673] = "Cri de guerre",
	[12975] = "Dernier rempart", [871] = "Mur protecteur", [2457] = "Posture de combat", [71] = "Posture défensive",
	[2458] = "Posture berserker", [1310317] = "Avant-garde", [23922] = "Heurt de bouclier", [12294] = "Frappe mortelle",
	[23881] = "Sanguinaire", [20252] = "Interception", [1680] = "Tourbillon", [6552] = "Volée de coups",
	[1719] = "Témérité", [18499] = "Rage berserker", [1161] = "Cri de défi", [12809] = "Coup traumatisant",
	[12292] = "Attaques circulaires", [1310222] = "Frappe perforante", [12323] = "Hurlement perçant",
	[12328] = "Souhait mortel", [1329555] = "Coups téméraires", [1310185] = "Maîtrise tactique",
}
RANKS = { [78] = "Rang 1", [284] = "Rang 2", [7386] = "Rang 1", [7405] = "Rang 2" }
local CLASS = { 78, 284, 100, 772, 6343, 1715, 2687, 7386, 355, 7384, 72, 1160, 6572, 694, 2565, 676, 845, 20230,
	1240193, 402927, 5246, 5308, 6673, 12975, 2457, 71 }
KNOWN = {}
BOOK = { { spellID = 6603, itemType = 1 } } -- onglet Général
for _, id in ipairs(CLASS) do
	BOOK[#BOOK + 1] = { spellID = id, itemType = 1 }
	KNOWN[id] = true
end
BOOK[#BOOK + 1] = { spellID = 1310185, itemType = 1, isPassive = true }
BOOK[#BOOK + 1] = { spellID = 871, itemType = 2 } -- Mur protecteur : pas encore appris
local function Learn(id)
	KNOWN[id] = true
	for _, e in ipairs(BOOK) do
		if e.spellID == id then
			e.itemType = 1
			return
		end
	end
	BOOK[#BOOK + 1] = { spellID = id, itemType = 1 }
end
function IsPlayerSpell(id) return KNOWN[id] == true end
Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1, FutureSpell = 2 } }
C_SpellBook = {
	GetNumSpellBookSkillLines = function() return 2 end,
	GetSpellBookSkillLineInfo = function(i)
		if i == 1 then return { name = "Général", itemIndexOffset = 0, numSpellBookItems = 1 } end
		return { name = "Guerrier", itemIndexOffset = 1, numSpellBookItems = #BOOK - 1 }
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
LOW = { [78] = true } -- rangs dépassés
C_ActionBar = { IsHighestSpellRank = function(id) return not LOW[id] end }
FORMS = { 2457, 71 }
function GetNumShapeshiftForms() return #FORMS end
function GetShapeshiftFormInfo(i) return "icon", i == 2, true, FORMS[i] end
BONUS = 2 -- en posture défensive : la barre principale montre les cases 85 à 96
function GetBonusBarOffset() return BONUS end

-- Les barres : principale (page de la posture), en bas à gauche (61-72) affichée, en bas à droite (49-60) cachée.
ACTIONS = {}
local function A(kind, id) return { kind, id } end
ACTIONS[1] = A("spell", 6603) -- page 1 (jamais vue en posture)
ACTIONS[49] = A("spell", 5308) -- barre cachée
ACTIONS[61], ACTIONS[62], ACTIONS[63] = A("spell", 2687), A("spell", 6673), A("item", 4540)
ACTIONS[64], ACTIONS[65], ACTIONS[66] = A("spell", 1160), A("spell", 845), A("spell", 402927)
ACTIONS[67], ACTIONS[68], ACTIONS[69] = A("spell", 5246), A("spell", 1240193), A("spell", 694)
ACTIONS[70], ACTIONS[71] = A("spell", 676), A("spell", 72)
-- Combat (73-84)
ACTIONS[73], ACTIONS[74], ACTIONS[75] = A("spell", 100), A("spell", 78), A("spell", 772)
ACTIONS[76], ACTIONS[77], ACTIONS[78] = A("item", 6948), A("macro", 1), A("spell", 7384)
ACTIONS[80], ACTIONS[84] = A("spell", 6343), A("item", 118)
-- Défensive (85-96)
ACTIONS[85], ACTIONS[86], ACTIONS[87] = A("spell", 355), A("spell", 7386), A("spell", 6572)
ACTIONS[88], ACTIONS[90] = A("companion", 5), A("spell", 2565)

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
for i = 1, 12 do
	_G["ActionButton" .. i] = Button(84 + i, true)
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
ns.char.gear = ns.char.gear or {}
ns.char.gear.role = "tank"
Fire("PLAYER_LOGIN")
Advance(10)

local function Copy()
	local out = {}
	for s, a in pairs(ACTIONS) do out[s] = { a[1], a[2] } end
	return out
end
local function Same(a, b)
	for s = 1, 180 do
		local x, y = a[s], b[s]
		if (x == nil) ~= (y == nil) or (x and (x[1] ~= y[1] or x[2] ~= y[2])) then
			return false, s
		end
	end
	return true
end
local function Is(slot, kind, id)
	local a = ACTIONS[slot]
	return a ~= nil and a[1] == kind and a[2] == id
end
local function Expect(slot, kind, id, what)
	local a = ACTIONS[slot]
	assert(Is(slot, kind, id), what .. " : case " .. slot .. " = " .. (a and (a[1] .. " " .. tostring(a[2])) or "vide")
		.. ", attendu " .. kind .. " " .. id)
end
local function Printed(pattern)
	for _, m in ipairs(PRINTED) do
		if m:find(pattern) then return m end
	end
end

-- 0. Avant réponse : remplissage 2.5.0 (cases vides seulement) et la question, une fois.
local q = ItineraireQuestion
assert(q and q:IsShown() and q.text:GetText():find("par posture"), "pas de question de rangement")
Expect(74, "spell", 284, "Frappe héroïque pas passée au rang 2")
Expect(72, "spell", 1715, "remplissage des cases vides (avant rangement)")
local before = Copy()

local function Answer(label)
	for _, b in ipairs(q.buttons) do
		if b:IsShown() and b:GetText() == label then
			b.scripts.OnClick(b)
			return
		end
	end
	error("pas de bouton « " .. label .. " »")
end

-- 1. « Ranger » : chaque touche à son rôle.
Answer("Ranger")
assert(CURSOR == nil, "curseur pas vidé")
local COMBAT_PAGE = { 100, 284, 7384, 402927, 7386, 6343, 772, 72, 694, 5308, 1715, 20230 }
local DEF_PAGE = { nil, 284, 6572, 402927, 7386, 6343, 2565, 72, 355, 1160, 676, 12975 }
for key = 1, 12 do
	Expect(72 + key, "spell", COMBAT_PAGE[key], "Combat, touche " .. key)
	if DEF_PAGE[key] then
		Expect(84 + key, "spell", DEF_PAGE[key], "Défensive, touche " .. key)
	end
end
-- barre fixe : les sorts qui manquent à une posture, dans l'ordre ; la nourriture reste à sa place
local FIXED = { [61] = 2687, [62] = 6673, [64] = 1160, [65] = 845, [66] = 772, [67] = 12975, [68] = 5246, [69] = 1240193 }
for slot, id in pairs(FIXED) do
	Expect(slot, "spell", id, "barre fixe")
end
Expect(63, "item", 4540, "objet de la barre fixe déplacé")
-- objets et macros des touches du rangement : sur la barre fixe, sinon garés sur une touche libre de leur page
Expect(70, "item", 6948, "pierre de foyer")
Expect(71, "macro", 1, "macro")
Expect(72, "item", 118, "potion")
Expect(85, "companion", 5, "compagnon (garé sur la touche libre de sa page)")
-- ce qui n'est pas affiché n'est pas touché ; aucun sort en double sur les barres affichées
Expect(1, "spell", 6603, "page 1")
Expect(49, "spell", 5308, "barre cachée")
local count = {}
for s = 61, 72 do
	local a = ACTIONS[s]
	if a and a[1] == "spell" then
		count[a[2]] = (count[a[2]] or 0) + 1
		assert(count[a[2]] == 1, "sort en double sur la barre fixe : " .. a[2])
	end
end
assert(not Is(61, "spell", 694) and not Is(70, "spell", 676), "anciens sorts restés")
assert(Printed("barres rangées par posture %(Combat, Défensive%)") and Printed("4 objet%(s%) ou macro%(s%) déplacé"),
	"message de rangement")

-- 2. Annuler : tout revient exactement ; puis on range de nouveau (même résultat).
ns.Auto.BarsCommand("annuler")
local ok, slot = Same(ACTIONS, before)
assert(ok, "annulation incomplète, case " .. tostring(slot))
assert(CURSOR == nil, "curseur pas vidé (annulation)")
assert(ns.char.actionbars.layout == "non", "entretien pas arrêté après annulation")
ns.Auto.BarsCommand("ranger")
Expect(76, "spell", 402927, "2e rangement")
Expect(85, "companion", 5, "2e rangement : compagnon")
assert(ns.char.actionbars.layout == 1, "rangement pas noté")
print(table.concat(ns.Auto.LayoutLines(), "\n"))

-- 3. Entretien : Avant-garde (Charge en Défensive) ; le compagnon garé repart vers la case libérée.
ACTIONS[72] = nil -- le joueur retire sa potion
Learn(1310317)
Fire("SPELLS_CHANGED")
Advance(3)
Expect(85, "spell", 100, "Charge en Défensive (Avant-garde)")
Expect(72, "companion", 5, "compagnon garé pas reparti")

-- 4. Mur protecteur remplace Dernier rempart (sort d'attente) ; Dernier rempart reste sur la barre fixe.
Learn(871)
Fire("SPELLS_CHANGED")
Advance(3)
Expect(96, "spell", 871, "Mur protecteur")
Expect(67, "spell", 12975, "Dernier rempart (barre fixe)")

-- 5. Ce que le joueur change reste à lui ; un sort enlevé n'est pas remis ailleurs.
ACTIONS[81] = nil -- Coup railleur enlevé
ACTIONS[95] = A("macro", 2) -- une macro à la place de Désarmement
Learn(7405) -- Fracasser armure rang 2
LOW[7386] = true
Fire("SPELLS_CHANGED")
Advance(3)
assert(ACTIONS[81] == nil, "Coup railleur remis")
Expect(95, "macro", 2, "macro du joueur remplacée")
for s = 1, 180 do
	assert(not Is(s, "spell", 694), "Coup railleur reposé en case " .. s)
	assert(not Is(s, "spell", 7386), "Fracasser armure rang 1 restée en case " .. s)
end
Expect(77, "spell", 7405, "rang 2 en Combat")
Expect(89, "spell", 7405, "rang 2 en Défensive")

-- 6. Heurt de bouclier (40) appris en combat : rien en combat ; ensuite il prend la touche 4 partout, et Sursaut de
--    victoire passe sur la barre fixe (case libérée par le joueur).
ACTIONS[70] = nil -- pierre de foyer retirée par le joueur
COMBAT = true
Learn(23922)
Fire("SPELLS_CHANGED")
Advance(3)
Expect(76, "spell", 402927, "touché en combat")
COMBAT = false
Fire("PLAYER_REGEN_ENABLED")
Advance(3)
Expect(76, "spell", 23922, "Heurt de bouclier en Combat")
Expect(88, "spell", 23922, "Heurt de bouclier en Défensive")
Expect(70, "spell", 402927, "Sursaut de victoire sur la barre fixe")

-- 7. La barre principale ne suit pas les pages attendues : on ne touche à rien.
ActionButton1.action = 1
local snap = Copy()
ns.Auto.BarsCommand("ranger")
assert(Same(ACTIONS, snap), "barres touchées malgré une page inattendue")
assert(Printed("rien rangé %(la barre principale montre la case 1 %(page 2, attendu 85%)"), "refus pas expliqué")
assert(ns.ReportText():find("rangement : 1"), "état absent du rapport")
print(ns.ReportText():match("Autonomie[^\n]*"))
print("OK barres par posture")
