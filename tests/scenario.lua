dofile(TESTS .. "/wow_mock.lua")
dofile(TESTS .. "/export.lua")
local E = GuidePersoExport
for _, q in ipairs(E.quests) do
  local objs = {}
  for i, o in ipairs(q.objectives) do
    objs[i] = { text = o.text, type = o.type, finished = o.finished, numFulfilled = o.have, numRequired = o.need }
  end
  LOG[#LOG + 1] = { info = { questID = q.id, title = q.title, level = q.level, suggestedGroup = q.group }, objectives = objs, complete = q.complete }
end
local function npc(id, name, area, pts, level) NPCS[id] = { id = id, name = name, spawns = { [area] = pts }, friendly = true, maxLevel = level } return id end
local function quest(id, finisherNpc, objectives, extra)
  local q = { Id = id, Finisher = { NPC = { finisherNpc } }, Objectives = {}, ObjectiveData = {}, level = 15, xp = 900 }
  for i, o in ipairs(objectives or {}) do
    local spawnList = {}
    for k, src in ipairs(o) do spawnList[k] = { Id = src.id, Name = NPCS[src.id] and NPCS[src.id].name or "?", Spawns = NPCS[src.id] and NPCS[src.id].spawns or src.spawns, Hostile = src.hostile } end
    q.Objectives[i] = { spawnList = spawnList, Coordinates = objectives[i].coords }
  end
  for k, v in pairs(extra or {}) do q[k] = v end
  QUESTS[id] = q
end
-- donneurs / receveurs
npc(1, "Rahauro", 1638, {{70.4, 29.6}}); npc(2, "Varimathras", 1497, {{56, 92}}); npc(3, "Thrall", 1637, {{31.7, 37.8}})
npc(4, "Migi", 1637, {{50, 60}}); npc(5, "Maître brasseur Drohn", 17, {{62.5, 36.9}}); npc(6, "Dizzywig", 17, {{63.5, 38.2}})
npc(7, "Uzzek", 17, {{61.4, 21.1}}); npc(8, "Thork", 17, {{51.5, 30.3}}); npc(9, "Sergra Darkthorn", 17, {{52.2, 31.0}})
npc(10, "Apothicaire Helbrim", 17, {{51.4, 30.1}}); npc(11, "Darsok", 17, {{51.6, 30.9}}); npc(12, "Tonga", 17, {{52.3, 31.9}})
npc(13, "Gazrog", 17, {{51.7, 29.9}}); npc(14, "Mankrik", 17, {{52.3, 31.6}}); npc(15, "Mangletooth", 17, {{44.6, 59.2}})
npc(16, "Eyahn Eagletalon", 1638, {{37.8, 59.4}}); npc(17, "Makaba Flathoof", 17, {{35.2, 27.8}}); npc(18, "Seereth Stonebreak", 17, {{35.3, 27.9}})
npc(19, "Morbin", 1497, {{60, 50}})
-- monstres / objets
npc(101, "Chaman Ragefeu", 2437, {{-1, -1}}, 15); npc(102, "Culte de la Lame ardente", 2437, {{-1, -1}}, 16)
npc(103, "Lame ardente", 14, {{52, 9}, {53, 10}, {51, 11}}, 12)
npc(104, "Forban du Totem sinistre", 406, {{73, 86}, {74, 87}, {72, 88}}, 20)
npc(105, "Déboiseur", 406, {{58, 62}, {59, 63}}, 19)
npc(106, "Zhévra", 17, {{55, 33}, {56, 34}, {57, 32}, {48, 38}, {49, 39}}, 12)
npc(107, "Géomancienne Tranchecrin", 17, {{57, 24}, {58, 25}, {57.5, 24.5}}, 14)
npc(108, "Défenseur Tranchecrin", 17, {{57.2, 24.2}, {58.1, 25.3}}, 15)
npc(109, "Kreenig Grondegroin", 17, {{59.5, 24.8}}, 16)
npc(110, "Caisse de la Croisée", 17, {{58.5, 26}, {59, 27}, {41, 40}})
npc(111, "Harpie Ensorçaile", 17, {{39, 13}, {40, 14}, {39.5, 12.5}}, 14)
npc(112, "Champignon chargé", 17, {{45.5, 22.5}, {44.8, 21.9}, {46, 23}})
npc(113, "Tranchecrin voleur", 17, {{55, 40}, {56, 41}}, 17)
npc(114, "Dos-hirsute", 17, {{44, 58}, {45, 60}, {46, 61}, {43, 59}}, 19)
npc(115, "Harpie des Vents", 215, {{31.7, 28.2}, {30.2, 19.5}}, 10)
npc(116, "Membre", 9999, {{-1, -1}}, 22)
quest(5723, 1, { {}, { { id = 101, hostile = true } } })
quest(5725, 2, { { { id = 102 } }, { { id = 102 } } })
quest(5724, 1)
quest(8368, 2)
quest(6548, 17, { { { id = 104, hostile = true } }, { { id = 104, hostile = true } } })
quest(1062, 18, { { { id = 105, hostile = true } } })
quest(1492, 6)
quest(870, 12, { { coords = { [17] = { { 45, 22 } } } } })
QUESTS[870].Objectives[1] = { spawnList = {}, Coordinates = { [17] = { { 45, 22 } } } }
quest(845, 9, { { { id = 106 } } })
quest(5041, 8, { { { id = 110 } } })
quest(872, 8, { { { id = 107, hostile = true } }, { { id = 108, hostile = true } }, { { id = 109 } } })
quest(867, 11, { { { id = 111 } } })
quest(848, 10, { { { id = 112 } } })
quest(819, 5)
quest(3281, 13, { { { id = 113 } } })
quest(899, 15, { { { id = 114 } } })
quest(4921, 14, { { coords = nil } })
QUESTS[4921].Objectives[1] = { spawnList = {}, Coordinates = { [17] = { { 49.3, 60.4 } } } }
-- 97003 inconnue de Questie (pas d'entrée)
quest(5726, 3, { { { id = 103 } } })
quest(97249, 4)
quest(92421, 19, { { { id = 116 } } })
quest(744, 16, { { { id = 115 } }, { { id = 115 } } }, { xp = 300 })
quest(1505, 7)
-- quêtes disponibles
QUESTS[881] = { Id = 881, name = "Echeyakee", level = 16, Starts = { NPC = { 9 } }, Finisher = { NPC = { 9 } } }
QUESTS[882] = { Id = 882, name = "Loin d'ici", level = 16, Starts = { NPC = { 15 } } }
AVAILABLE[881] = true; AVAILABLE[882] = true

PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.544, 0.383
local ns = LoadAddon(ADDON_DIR, { "Solver.lua", "Geo.lua", "Data.lua", "Planner.lua", "Guide.lua", "UI.lua", "Options.lua", "Group.lua", "Core.lua" })
Fire("ADDON_LOADED", "Itineraire")
Fire("PLAYER_LOGIN")
Advance(5)
print("resumes:", RESUMES)
local function Show(plan, label)
  print("==== " .. label .. " : " .. #plan.order .. " étapes, trajet " .. math.floor(plan.travel or 0) .. " s, travail " .. math.floor(plan.workTime or 0) .. " s, XP " .. (plan.xp or 0) .. ", estimations " .. tostring(plan.estimates))
  for k, s in ipairs(plan.order) do
    print(string.format("%2d. [%s] %s  |  %s  (trajet %d s)", k, s.kind, s.title, s.subtitle, math.floor(s.leg)))
  end
  for name, list in pairs(plan.side) do
    for key, v in pairs(list) do
      local q = v.q or v
      print("   side." .. name .. ": " .. tostring(q.title or v.name) .. (v.why and (" / " .. v.why) or "") .. (v.what and (" / " .. v.what) or ""))
    end
  end
  for _, a in ipairs(plan.abandon or {}) do print("   abandon: " .. a.text) end
end
assert(ns.plan, "aucun plan calculé")
Show(ns.plan, "départ (Pitons-du-Tonnerre)")
print("routes envoyées à SP : " .. #SP_ROUTES .. ", 1re étape SP : " .. tostring(SP_ROUTES[#SP_ROUTES][1].title))
-- rendu de la sacoche
for i, e in ipairs(LOG) do if e.info.questID == 5724 then table.remove(LOG, i) break end end
Fire("QUEST_TURNED_IN", 5724)
Advance(3)
Show(ns.plan, "après rendu sacoche")
-- inclure les donjons
ns.db.includeDungeons = true
ns.RequestPlan("t", 0)
Advance(3)
Show(ns.plan, "avec donjons")
-- déplacement joueur à la Croisée
PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.515, 0.303
Advance(20)
Show(ns.plan, "à la Croisée")
SlashCmdList.ITINERAIRE("debug")
print("debug stops: " .. #ns.char.debug.stops)
print("UI summary: " .. tostring(_G.ItineraireFrame and "ok"))
-- texte de la fenêtre
for _, f in ipairs(FRAMES) do end
local function texts(frame) end
print("---- fenêtre ----")
for _, f in ipairs(FONTS) do
  local t = tostring(f.text) if #t > 3 then print("UI> " .. t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
end
-- détails d'une étape avec prise au passage
for _, s in ipairs(ns.plan.order) do if #s.pickups > 0 then print("pickup sur: " .. s.title .. " -> " .. s.pickups[1].name) end end
