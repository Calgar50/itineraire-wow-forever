dofile(TESTS .. "/scenario_setup.lua")
PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.544, 0.383
Questie.db = { char = {} }
local TU = {}
function TU:FocusQuest(id) Questie.db.char.TrackerFocus = id return true end
function TU:UnFocus() Questie.db.char.TrackerFocus = nil end
local orig = QuestieLoader.ImportModule
QuestieLoader.ImportModule = function(self, name) if name == "TrackerUtils" then return TU end return orig(self, name) end
local ns = LoadAddon(ADDON_DIR, { "Solver.lua", "Geo.lua", "Data.lua", "Planner.lua", "Guide.lua", "UI.lua", "Options.lua", "Group.lua", "Core.lua" })
Fire("ADDON_LOADED", "Itineraire"); Fire("PLAYER_LOGIN"); Advance(5)
local function head(label, n)
  local out = {}
  for k = 1, math.min(n or 4, #ns.plan.order) do local s = ns.plan.order[k]; out[#out + 1] = (s.focus and "»" or "") .. s.title end
  print(label .. " | " .. table.concat(out, "  ||  "))
end
local function checkFeasible()
  -- objectifs d'une quête toujours avant son rendu
  local seenObj, ok = {}, true
  local pos = {}
  for k, s in ipairs(ns.plan.order) do
    for _, t in ipairs(s.tasks) do
      if s.kind == "turnin" and t.after then
        -- tous ses objectifs routés doivent être avant
        for k2 = k + 1, #ns.plan.order do
          for _, t2 in ipairs(ns.plan.order[k2].tasks) do
            if t2.q.id == t.q.id and ns.plan.order[k2].kind ~= "turnin" then ok = false end
          end
        end
      end
    end
  end
  return ok
end
head("sans suivi")
-- menu Q
local qbtn; for _, f in ipairs(FRAMES) do if rawget(f, "text") == "Q" then qbtn = f end end
qbtn.scripts.OnClick(qbtn)
local menu = _G.ItineraireMenu
local n = 0; for _, b in ipairs(menu.buttons) do if b.shown then n = n + 1 end end
print("menu Q: " .. n .. " lignes ; 2e = " .. menu.buttons[2].text.text)
-- choisir « Les harpies pillardes »
for _, b in ipairs(menu.buttons) do if b.shown and b.text.text:find("harpies pillardes") then b.scripts.OnClick(b) end end
Advance(3)
head("suivi harpies"); print("faisable:", checkFeasible(), "Questie focus:", Questie.db.char.TrackerFocus, "statut:", (ns.StatusText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
-- quête trop dure forcée
ns.SetFocus(899, "ui"); Advance(3)
head("suivi Consumé par la haine (niv 20)")
-- rendu partagé chez Thork
ns.SetFocus(872, "ui"); Advance(3)
head("suivi La perturbation cesse", 5); print("faisable:", checkFeasible())
-- donjon
ns.SetFocus(5723, "ui"); Advance(3)
head("suivi Gouffre (donjon)", 3)
-- focus depuis Questie
Questie.db.char.TrackerFocus = 845; Advance(3)
print("focus via Questie ->", ns.session.focus); head("suivi zhévras")
Questie.db.char.TrackerFocus = nil; Advance(3)
print("défocus via Questie ->", tostring(ns.session.focus))
-- quête suivie rendue
ns.SetFocus(97249, "ui"); Advance(3)
head("suivi Son plat préféré", 2)
for i, e in ipairs(LOG) do if e.info.questID == 97249 then table.remove(LOG, i) break end end
Fire("QUEST_TURNED_IN", 97249); Advance(5)
print("après rendu ->", tostring(ns.session.focus)); head("retour normal", 2)
-- quête inconnue de Questie (97003)
ns.SetFocus(97003, "ui"); Advance(3)
print((ns.StatusText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
print("OK")
