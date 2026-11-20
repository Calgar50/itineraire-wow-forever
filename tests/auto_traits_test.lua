-- Talents sur Forever : arbre C_Traits (une config, un arbre, trois onglets = groupes), points préparés
-- (PurchaseRank) puis appliqués en une incantation (CommitConfig) seulement quand le joueur ne bouge pas ;
-- incantation interrompue = annulée puis refaite ; changements du joueur en cours = on n'y touche pas ;
-- le rôle (fenêtre Équipement) se lit dans les points de chaque onglet. Pas d'API Classic ici (comme sur Forever).
dofile(TESTS .. "/wow_mock.lua")
time = function() return 1800000000 end

LEVEL = 22
function UnitLevel() return LEVEL end
function UnitClass() return "Guerrier", "WARRIOR", 1 end
function UnitFactionGroup() return "Horde", "Horde" end
function UnitIsDeadOrGhost() return false end
MOVING = true
function GetUnitSpeed() return MOVING and 7 or 0, 7, 7, 4.7 end
function IsFalling() return false end
GetTalentInfo, GetTalentTabInfo, GetNumTalentTabs, GetNumTalents, LearnTalent, UnitCharacterPoints = nil, nil, nil, nil, nil, nil

SPELLS = { [12298] = "Spécialisation Bouclier", [12797] = "Vengeance améliorée", [12297] = "Anticipation",
	[1310316] = "Maître de la défense", [12975] = "Dernier rempart", [12792] = "Défi", [12282] = "Frappe héroïque améliorée" }
C_Spell = { GetSpellName = function(id) return SPELLS[id] end }

-- Arbre 1117 : groupes Armes 11650, Fureur 11657, Protection 11670 (+ 11649, un groupe qui n'est pas un onglet).
local GROUPS = { { groupID = 11670, displayName = "Protection", orderIndex = 2 },
	{ groupID = 11650, displayName = "Armes", orderIndex = 0 }, { groupID = 11657, displayName = "Fureur", orderIndex = 1 } }
NODES = {}
local order = {}
local function N(id, spell, group, max, req)
	NODES[id] = { spell = spell, group = group, max = max, req = req, rank = 0 }
	order[#order + 1] = id
end
N(501, 12282, 11650, 3, 0)
N(601, 12298, 11670, 5, 0) N(602, 12797, 11670, 3, 5) N(603, 12297, 11670, 5, 5)
N(604, 1310316, 11670, 2, 10) N(605, 12975, 11670, 1, 10) N(606, 12792, 11670, 3, 10)
STAGED = {}
local function Rank(id) return NODES[id].rank + (STAGED[id] or 0) end
local function GroupSpent(g)
	local n = 0
	for id, node in pairs(NODES) do if node.group == g then n = n + Rank(id) end end
	return n
end
local function Free()
	local n = 0
	for id in pairs(NODES) do n = n + Rank(id) end
	return LEVEL - 9 - n
end
USER_EDITING = false
FAIL_NEXT = false
COMMITS = 0
C_ClassTalents = {
	GetActiveConfigID = function() return 77 end,
	CommitConfig = function()
		COMMITS = COMMITS + 1
		local fail = FAIL_NEXT or MOVING
		FAIL_NEXT = false
		C_Timer.After(0.5, function()
			if fail then
				Fire("CONFIG_COMMIT_FAILED", 77)
			else
				for id, n in pairs(STAGED) do NODES[id].rank = NODES[id].rank + n end
				STAGED = {}
				Fire("TRAIT_CONFIG_UPDATED", 77)
			end
		end)
		return true
	end,
}
C_Traits = {
	GetConfigInfo = function(id) return id == 77 and { treeIDs = { 1117 }, type = 4 } or nil end,
	GetGroupDisplayInfoByTreeID = function() return GROUPS end,
	GetTreeNodes = function() return order end,
	GetNodeInfo = function(_, id)
		local node = NODES[id]
		return { ID = id, currentRank = Rank(id), maxRanks = node.max, isVisible = true, groupIDs = { 11649, node.group },
			entryIDs = { id * 10 }, canPurchaseRank = Free() > 0 and Rank(id) < node.max and GroupSpent(node.group) >= node.req }
	end,
	GetEntryInfo = function(_, entryID) return { definitionID = entryID + 1 } end,
	GetDefinitionInfo = function(def) return { spellID = NODES[(def - 1) / 10].spell } end,
	GetGroupCurrencyInfo = function(_, ids)
		local out = {}
		for _, g in ipairs(ids) do
			local spent = GroupSpent(g)
			if spent > 0 then
				out[#out + 1] = { traitNodeGroupID = g, currencyInfos = { { traitCurrencyID = 3820, spent = spent } } }
			end
		end
		return out
	end,
	GetTreeCurrencyInfo = function() return { { traitCurrencyID = 3820, quantity = Free() } } end,
	PurchaseRank = function(_, id)
		assert(Free() > 0, "plus de point")
		assert(Rank(id) < NODES[id].max, "rang max")
		assert(GroupSpent(NODES[id].group) >= NODES[id].req, "palier fermé")
		STAGED[id] = (STAGED[id] or 0) + 1
		return true
	end,
	ConfigHasStagedChanges = function() return USER_EDITING end,
	RollbackConfig = function() STAGED = {} return true end,
	CommitConfig = function() error("ne doit pas servir quand C_ClassTalents.CommitConfig marche") end,
}

ITEMS = {}
C_Item = { GetItemInfo = function() return nil end, GetItemInfoInstant = function() return nil end,
	GetItemStats = function() return nil end, RequestLoadItemDataByID = function() end }
EQUIPPED = {}
function GetInventoryItemLink() return nil end
function GetItemCount() return 0 end

local files = { "Donnees/Butins.lua", "Donnees/Objets.lua", "Donnees/Entrees.lua", "Donnees/Recettes.lua", "Donnees/PNJ.lua",
	"Donnees/Marchandises.lua", "Solver.lua", "Geo.lua", "Data.lua", "DungeonJournal.lua", "Planner.lua", "Guide.lua", "UI.lua",
	"Options.lua", "Group.lua", "Gear.lua", "GearUI.lua", "Pilote.lua", "Autonomie.lua", "Core.lua" }
PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.515, 0.303
local ns = LoadAddon(ADDON_DIR, files)
Fire("ADDON_LOADED", "Itineraire")
ns.db.pilote = { talents = "auto", talentPlan = "tank" }
Fire("PLAYER_LOGIN")
Advance(10)
local A, G = ns.Auto, ns.Gear

-- 1. Lecture : onglets dans l'ordre du jeu, points libres.
local trees = A.Trees()
assert(trees.mode == "traits" and trees[1].name == "Armes" and trees[3].name == "Protection" and trees.free == 13, "lecture")
assert(G.Role() == "melee", "rôle sans point : " .. tostring(G.Role()))

-- 2. En mouvement : rien (l'incantation serait interrompue) ; immobile : tout est préparé puis appliqué en une fois.
assert(COMMITS == 0, "talents appliqués en courant")
MOVING = false
Advance(3)
assert(COMMITS == 1, "une seule incantation attendue : " .. COMMITS)
assert(NODES[601].rank == 5 and NODES[602].rank == 3 and NODES[603].rank == 2 and NODES[604].rank == 2 and NODES[605].rank == 1,
	"plan pas suivi")
assert(Free() == 0 and next(STAGED) == nil, "points restants ou préparés")
local role, why = G.Role()
assert(role == "tank" and why:find("Protection"), "rôle d'après les onglets : " .. tostring(role) .. " " .. tostring(why))

-- 3. Incantation interrompue : annulée, puis refaite quand le joueur ne bouge plus.
LEVEL = 23
FAIL_NEXT = true
Fire("PLAYER_LEVEL_UP", 23)
Advance(6)
assert(table.concat(A.log, " | "):find("incantation interrompue"), "échec non vu : " .. table.concat(A.log, " | "))
assert(COMMITS == 3 and NODES[606].rank == 1 and next(STAGED) == nil, "pas refait après l'échec (commits " .. COMMITS .. ")")

-- 4. Le joueur prépare ses talents lui-même dans la fenêtre : on n'y touche pas.
LEVEL = 24
USER_EDITING = true
Fire("PLAYER_LEVEL_UP", 24)
Advance(4)
assert(COMMITS == 3 and next(STAGED) == nil, "talents touchés pendant que le joueur les préparait")
USER_EDITING = false
SlashCmdList.ITINERAIRE("talents")
Advance(3)
assert(COMMITS == 4 and NODES[606].rank == 2, "pas repris après")
print(ns.ReportText():match("Autonomie[^\n]*"))
print("OK talents Forever")
