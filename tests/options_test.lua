dofile(TESTS .. "/scenario_setup.lua")
PLAYER.map, PLAYER.x, PLAYER.y = 1413, 0.544, 0.383
Questie.db = { char = {} }
local ns = LoadAddon(ADDON_DIR, { "Solver.lua", "Geo.lua", "Data.lua", "Planner.lua", "Guide.lua", "UI.lua", "Options.lua", "Group.lua", "Core.lua" })
Fire("ADDON_LOADED", "Itineraire"); Fire("PLAYER_LOGIN"); Advance(5)
local ui = ns.db.ui
print("défauts:", ui.scale, ui.alpha, ui.width, ui.font, ui.theme, ui.rows, ui.compact)
SlashCmdList.ITINERAIRE("options")
local panel = _G.ItineraireOptions
assert(panel and panel.shown, "panneau non affiché")
-- cliquer toutes les cases et bouger tous les curseurs
local checks, sliders, choiceButtons = 0, 0, 0
local function walk(f)
  for _, c in ipairs(FRAMES) do end
end
for _, f in ipairs(FRAMES) do
  if f.kind == "CheckButton" and f.scripts.OnClick then
    f:SetChecked(not f:GetChecked()); f.scripts.OnClick(f); checks = checks + 1
  elseif f.kind == "Slider" and f.scripts.OnValueChanged then
    f.scripts.OnValueChanged(f, 0.7); f.scripts.OnValueChanged(f, 12); sliders = sliders + 1
  end
end
for _, f in ipairs(FRAMES) do
  if f.kind == "Button" and rawget(f, "key") and f.scripts.OnClick then f.scripts.OnClick(f); choiceButtons = choiceButtons + 1 end
end
print("cases:", checks, "curseurs:", sliders, "choix:", choiceButtons)
print("après:", ui.scale, ui.alpha, ui.width, ui.font, ui.theme, ui.rows, "compact", ui.compact, "icons", ui.icons, "locked", ui.locked, "fade", ui.fade)
-- mode compact + masquer en combat + en donjon
ui.compact = true; ui.hideCombat = true; ui.hideInstance = true; ns.UI.ApplySettings()
InCombatLockdown = function() return true end; Fire("PLAYER_REGEN_DISABLED")
print("en combat, fenêtre visible:", _G.ItineraireFrame.shown)
InCombatLockdown = function() return false end; Fire("PLAYER_REGEN_ENABLED")
print("après combat:", _G.ItineraireFrame.shown)
INSTANCE = true; Fire("PLAYER_ENTERING_WORLD"); print("en donjon:", _G.ItineraireFrame.shown)
INSTANCE = false; Fire("PLAYER_ENTERING_WORLD"); print("hors donjon:", _G.ItineraireFrame.shown)
-- réinitialiser
for _, f in ipairs(FRAMES) do if rawget(f, "text") == "Tout réinitialiser" then f.scripts.OnClick(f) end end
print("réinitialisé:", ui.scale, ui.width, ui.font, ui.theme, ui.compact, ui.hideCombat)
-- raccourcis et menu des addons
local before = ns.plan.order[1].title
Itineraire_SkipCurrent(); Advance(3)
print("raccourci passer:", before, "->", ns.plan.order[1].title)
Itineraire_Toggle(); print("toggle:", _G.ItineraireFrame.shown); Itineraire_Toggle(); print("toggle:", _G.ItineraireFrame.shown)
Itineraire_OnCompartmentClick("Itineraire", "RightButton"); print("compartiment clic droit -> options:", panel.shown)
Itineraire_Recalc(); Advance(3)
-- fondu
ui.fade = true
local fr = _G.ItineraireFrame
fr.scripts.OnUpdate(fr, 0.3); print("alpha estompé:", fr:GetAlpha())
-- poignée de largeur
for _, f in ipairs(FRAMES) do if f.scripts.OnMouseDown and f.scripts.OnMouseUp and f.kind == "Button" then fr:SetWidth(480); f.scripts.OnMouseDown(f); f.scripts.OnMouseUp(f) end end
print("largeur enregistrée:", ui.width)
print("OK")
