dofile(TESTS .. "/scenario_setup.lua")
local ns = LoadAddon(ADDON_DIR, { "Solver.lua", "Geo.lua", "Data.lua", "Planner.lua", "Guide.lua", "UI.lua", "Options.lua", "Group.lua", "Core.lua" })
Fire("ADDON_LOADED", "Itineraire"); Fire("PLAYER_LOGIN"); Advance(20)
local p1 = ns.plan
Fire("QUEST_LOG_UPDATE"); Advance(3)
print("same plan object after no-op QUEST_LOG_UPDATE:", ns.plan == p1)
LOG[1].objectives[1].numFulfilled = (LOG[1].objectives[1].numFulfilled or 0) + 1
Fire("QUEST_LOG_UPDATE"); Advance(3)
print("new plan after progress:", ns.plan ~= p1)
