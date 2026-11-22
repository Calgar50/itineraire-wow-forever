-- Trier mon journal (3.1.0) : quêtes grises, échouées ou sans XP proposées à l'abandon (avec la raison), gardées
-- d'office quand elles servent encore ; abandon seulement après 2 clics ; vérification dans le journal ensuite.
dofile(TESTS .. "/wow_mock.lua")
NOW = 1800000000
time = function() return NOW end
date = function(fmt, t) return os.date(fmt, t or NOW) end
function UnitLevel() return 25 end
function UnitXPMax() return 34000 end
function UnitClass() return "Guerrier", "WARRIOR" end
C_QuestLog.GetMaxNumQuestsCanAccept = function() return 25 end

NPCS[9] = { id = 9, name = "Sergra", spawns = { [17] = { { 52.2, 31.0 } } }, friendly = true }
NPCS[106] = { id = 106, name = "Zhévra", spawns = { [17] = { { 55, 33 }, { 56, 34 } } }, friendly = true, maxLevel = 14 }
local function logQuest(id, title, level, opts)
	opts = opts or {}
	LOG[#LOG + 1] = { info = { questID = id, title = title, level = level, suggestedGroup = 0 },
		objectives = opts.done and {} or { { text = "Zhévra : 0/4", type = "monster", finished = false, numFulfilled = 0, numRequired = 4 } },
		complete = opts.done }
	QUESTS[id] = { Id = id, name = title, level = level, xp = opts.xp or level * 70, Finisher = { NPC = { 9 } },
		Objectives = { { spawnList = { { Id = 106, Name = "Zhévra", Spawns = NPCS[106].spawns, Hostile = true } } } },
		requiredClasses = opts.class, nextQuestInChain = opts.next, requiredSkill = opts.skill }
end
-- niveau 25 : grise jusqu'au niveau 18
logQuest(501, "Vieille grise", 14, { xp = 120 })
logQuest(502, "Grise terminée", 15, { done = true, xp = 150 })
logQuest(503, "Grise de classe", 12, { class = 1 })
logQuest(504, "Grise qui mène loin", 17, { next = 505 })
QUESTS[505] = { Id = 505, name = "La suite utile", level = 24 }
logQuest(506, "Grise de métier", 16, { skill = { 164, 50 } })
logQuest(507, "Sans XP", 24, { xp = 20 })
logQuest(508, "Bonne quête", 24, { xp = 2400 })
logQuest(509, "Verte encore utile", 20, { xp = 1700 })
logQuest(510, "Grise suivie", 13, { xp = 100 })
LOG[#LOG + 1] = { info = { questID = 511, title = "Échouée", level = 23, suggestedGroup = 0 }, objectives = {}, complete = false }
QUESTS[511] = { Id = 511, name = "Échouée", level = 23, xp = 2000, Finisher = { NPC = { 9 } } }
C_QuestLog.IsFailed = function(id) return id == 511 end

-- Abandon simulé : la quête choisie quitte le journal (sauf une que le « jeu » refuse).
SELECTED, ABANDONED, REFUSED = nil, {}, { [503] = true }
C_QuestLog.GetSelectedQuest = function() return SELECTED end
C_QuestLog.SetSelectedQuest = function(id) SELECTED = id end
C_QuestLog.SetAbandonQuest = function() end
C_QuestLog.AbandonQuest = function()
	if REFUSED[SELECTED] then return end
	for i, e in ipairs(LOG) do
		if e.info.questID == SELECTED then
			table.remove(LOG, i)
			ABANDONED[#ABANDONED + 1] = SELECTED
			return
		end
	end
end
C_QuestLog.GetLogIndexForQuestID = function(id)
	for i, e in ipairs(LOG) do
		if e.info.questID == id then return i end
	end
end

PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.52, 0.31
local ns = LoadAddon(ADDON_DIR, { "Solver.lua", "Geo.lua", "Data.lua", "Planner.lua", "Guide.lua", "UI.lua", "Options.lua",
	"Group.lua", "Gear.lua", "GearUI.lua", "Pilote.lua", "Autonomie.lua", "Montee.lua", "MonteeUI.lua", "Controle.lua",
	"Tri.lua", "Core.lua" })
Fire("ADDON_LOADED", "Itineraire")
Fire("PLAYER_LOGIN")
Advance(5)
-- récompense qui t'améliore pour « Verte… » et « Sans XP » ? Seulement pour 509 (verte, donc pas concernée) et 501 : non.
ns.Gear.PlanOptions = function() return { goals = {}, wanted = {}, quests = { [509] = { name = "Bottes", gain = "+8 %" } } } end
ns.session.focus = 510

-- 1. L'analyse
local offer, kept, info = ns.Tri.Analyse()
local function Find(list, id)
	for _, e in ipairs(list) do
		if e.id == id then return e end
	end
end
print("gris jusqu'au niveau", info.gray)
for _, e in ipairs(offer) do print("PROPOSÉE", e.id, e.checked, e.reason) end
for _, e in ipairs(kept) do print("GARDÉE", e.id, e.reason) end
assert(info.gray == 18, "gris : " .. info.gray)
assert(Find(offer, 501) and Find(offer, 501).checked, "grise non proposée")
assert(Find(offer, 502) and Find(offer, 502).checked == false, "grise terminée : proposée mais pas cochée")
assert(Find(offer, 507) and Find(offer, 507).checked, "sans XP non proposée")
assert(Find(offer, 511) and Find(offer, 511).checked, "échouée non proposée")
assert(Find(kept, 503) and Find(kept, 503).reason:find("classe"), "quête de classe pas gardée")
assert(Find(kept, 504) and Find(kept, 504).reason:find("suite utile"), "suite de ton niveau pas gardée")
assert(Find(kept, 506) and Find(kept, 506).reason:find("métier"), "quête de métier pas gardée")
assert(Find(kept, 510) and Find(kept, 510).reason:find("suivie"), "quête suivie pas gardée")
assert(not Find(offer, 508) and not Find(offer, 509) and not Find(kept, 508) and not Find(kept, 509), "bonnes quêtes touchées")
-- « À savoir » : le rappel
ns.UI.Refresh(ns.plan)
local hint = false
for _, f in ipairs(FONTS) do
	if tostring(f.text):find("/iti tri") then hint = true end
end
assert(hint, "pas de rappel des quêtes grises")

-- 2. La fenêtre : rien n'est abandonné sans deux clics
SlashCmdList.ITINERAIRE("tri")
assert(ns.Tri.Shown(), "/iti tri n'ouvre pas la fenêtre")
local go
for _, f in ipairs(FRAMES) do
	if f.kind == "Button" and tostring(rawget(f, "text") or ""):find("Abandonner les") then go = f end
end
assert(go, "bouton d'abandon introuvable")
assert(tostring(go.text):find("3 quête"), "3 cochées attendues : " .. tostring(go.text)) -- 501, 507, 511
go.scripts.OnClick(go)
assert(#ABANDONED == 0, "abandon dès le 1er clic")
assert(tostring(go.text):find("Sûr"), "pas de demande de confirmation")
go.scripts.OnClick(go)
Advance(3)
table.sort(ABANDONED)
assert(table.concat(ABANDONED, ",") == "501,507,511", "abandonnées : " .. table.concat(ABANDONED, ","))

-- 3. Une quête que le jeu refuse : signalée, pas perdue de vue
ns.Tri.Abandon({ { id = 503, title = "Grise de classe" } })
Advance(3)
local refused = false
for _, m in ipairs(PRINTED) do
	if tostring(m):find("refusé") and tostring(m):find("Grise de classe") then refused = true end
end
assert(refused, "refus du jeu non signalé")
-- la quête suivie n'est jamais abandonnée, même demandée
ns.Tri.Abandon({ { id = 510, title = "Grise suivie" } })
Advance(3)
assert(C_QuestLog.GetLogIndexForQuestID(510), "quête suivie abandonnée")
print("OK tri")
