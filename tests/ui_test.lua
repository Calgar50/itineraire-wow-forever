dofile(TESTS .. "/scenario_setup.lua")
PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.544, 0.383
Questie.db = { char = {} }
local ns = LoadAddon(ADDON_DIR, { "Solver.lua", "Geo.lua", "Data.lua", "Planner.lua", "Guide.lua", "UI.lua", "Options.lua", "Group.lua", "Core.lua" })
Fire("ADDON_LOADED", "Itineraire")
Fire("PLAYER_LOGIN")
Advance(5)
local function Rows() local r = {} for _, f in ipairs(FRAMES) do if type(rawget(f, "stop")) == "table" and rawget(f, "num") and f.shown then r[#r + 1] = f end end table.sort(r, function(a, b) return a.stop.number < b.stop.number end) return r end
local function Click(label)
  local menu = _G.ItineraireMenu
  for _, b in ipairs(menu.buttons) do if b.shown and b.text.text:find(label, 1, true) then b.scripts.OnClick(b) return true end end
  error("pas trouvé dans le menu : " .. label)
end
local rows = Rows()
print("lignes visibles:", #rows, "/ étapes:", #ns.plan.order)
for _, r in ipairs(rows) do print(r.num.text, r.title.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), "|", (r.sub.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end
-- bouton voir tout
local more; for _, f in ipairs(FRAMES) do if type(rawget(f, "text")) == "string" and f.text:find("^Voir plus") then more = f end end
print("bouton:", more and more.text)
more.scripts.OnClick(more)
print("après « voir tout » :", #Rows())
local fr = _G.ItineraireFrame; fr.scripts.OnMouseWheel(fr, -1); fr.scripts.OnMouseWheel(fr, -1); fr.scripts.OnMouseWheel(fr, -1); fr.scripts.OnMouseWheel(fr, -1)
print("après molette, bouton:", more.text)
for _, r in ipairs(Rows()) do if r.stop.number > 16 then print(r.num.text, (r.title.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")), "|", (r.sub.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end end
rows = Rows()
rows[1].scripts.OnClick(rows[1], "RightButton")
Click("Passer cette étape"); Advance(3)
print("après passer, 1re :", ns.plan.order[1].title)
rows = Rows(); rows[2].scripts.OnClick(rows[2], "RightButton")
Click("Suivre « "); Advance(3)
print("suivi:", ns.session.focus, ns.plan.order[1].title)
for _, f in ipairs(FRAMES) do if rawget(f, "text") == "..." then f.scripts.OnClick(f) end end
Click("Inclure les donjons"); Advance(3)
print("donjons:", ns.db.includeDungeons)
SlashCmdList.ITINERAIRE("reset"); Advance(3)
for _, l in ipairs(PRINTED) do print("chat:", l) end
print("OK")
