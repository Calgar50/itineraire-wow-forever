-- Faux environnement WoW minimal pour exécuter Itinéraire hors du jeu.
local clock = 1000
local msClock = 0
function GetTime() return clock end
function debugprofilestop() msClock = msClock + 0.05 return msClock end
function date(fmt) return os.date(fmt) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
function InCombatLockdown() return false end
function UnitLevel() return 16 end
function UnitName() return "Testeur" end
DISABLED = {}

function IsMounted() return false end
function GetUnitSpeed() return 0, 7, 7, 4.7 end
function GetCursorPosition() return 500, 500 end
function GetRealmName() return "Test" end
UISpecialFrames = {}
SlashCmdList = {}
PRINTED = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) PRINTED[#PRINTED + 1] = m print("[chat] " .. m) end }
geterrorhandler = function() return print end

-- Stubs d'interface
local Stub = {}
Stub.__index = function(t, k)
	local v = rawget(Stub, k)
	if v ~= nil then return v end
	return function(self, ...) return self end
end
local function NewStub() return setmetatable({ scripts = {}, shown = true, text = "" }, Stub) end
Stub.SetScript = function(self, name, fn) self.scripts[name] = fn end
Stub.GetScript = function(self, name) return self.scripts[name] end
Stub.SetText = function(self, t) self.text = t end
Stub.GetText = function(self) return self.text end
Stub.GetStringHeight = function() return 12 end
Stub.GetStringWidth = function() return 100 end
Stub.IsShown = function(self) return self.shown end
Stub.Show = function(self) self.shown = true end
Stub.Hide = function(self) self.shown = false end
Stub.SetShown = function(self, s) self.shown = s end
Stub.GetPoint = function() return "RIGHT", nil, "RIGHT", -80, 80 end
Stub.CreateTexture = function() return NewStub() end
FONTS = {}
Stub.CreateFontString = function() local f = NewStub() FONTS[#FONTS + 1] = f return f end
Stub.GetEffectiveScale = function() return 1 end
Stub.SetHeight = function(self, h) rawset(self, "_h", h) end
Stub.GetHeight = function(self) return rawget(self, "_h") or 32 end
Stub.SetWidth = function(self, w) rawset(self, "_w", w) end
Stub.GetWidth = function(self) return rawget(self, "_w") or 360 end
Stub.SetSize = function(self, w, h) rawset(self, "_w", w) rawset(self, "_h", h) end
Stub.SetAlpha = function(self, a) rawset(self, "_a", a) end
Stub.GetAlpha = function(self) return rawget(self, "_a") or 1 end
Stub.SetChecked = function(self, c) rawset(self, "_c", c) end
Stub.GetChecked = function(self) return rawget(self, "_c") end
Stub.SetValue = function(self, v) rawset(self, "_v", v) if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end end
Stub.GetValue = function(self) return rawget(self, "_v") end
Stub.SetScale = function(self, s) rawset(self, "_s", s) end
function MouseIsOver() return false end
function IsInInstance() return INSTANCE or false end
Stub.GetFrameLevel = function() return 1 end
FRAMES = {}
function CreateFrame(kind, name)
	local f = NewStub()
	f.kind = kind
	f.frameName = name
	FRAMES[#FRAMES + 1] = f
	if name then _G[name] = f end
	return f
end
UIParent = NewStub()
GameTooltip = NewStub()

-- Minuteurs simulés
TIMERS = {}
C_Timer = {}
function C_Timer.After(d, fn) TIMERS[#TIMERS + 1] = { at = clock + d, fn = fn } end
function C_Timer.NewTimer(d, fn)
	local t = { at = clock + d, fn = fn }
	t.Cancel = function() t.cancelled = true end
	TIMERS[#TIMERS + 1] = t
	return t
end
function C_Timer.NewTicker(d, fn)
	local t = { at = clock + d, fn = fn, every = d }
	t.Cancel = function() t.cancelled = true end
	TIMERS[#TIMERS + 1] = t
	return t
end
function Advance(seconds)
	local target = clock + seconds
	while true do
		local nextT
		for _, t in ipairs(TIMERS) do
			if not t.cancelled and not t.done and t.at <= target and (not nextT or t.at < nextT.at) then nextT = t end
		end
		if not nextT then break end
		clock = nextT.at
		if nextT.every then nextT.at = clock + nextT.every else nextT.done = true end
		nextT.fn(nextT)
		-- faire tourner les OnUpdate
		RESUMES = 0
		for _ = 1, 200000 do RESUMES = RESUMES + 1
			local any = false
			-- (les cadres nommés — fenêtre, bandeau — ont un OnUpdate permanent : on ne tourne que tant
			--  qu'un cadre anonyme, comme le calcul en tâche de fond, travaille)
			for _, f in ipairs(FRAMES) do
				if f.shown and f.scripts.OnUpdate then
					if not rawget(f, "frameName") then any = true end
					f.scripts.OnUpdate(f, 0.016)
				end
			end
			if not any then break end
		end
	end
	clock = target
end

-- Cartes : décalages monde (yards) par carte, continent 1 = Kalimdor, 0 = Royaumes de l'Est
MAPS = {
	[1413] = { name = "Les Tarides", ox = 0, oy = 0, s = 10000, inst = 1 },
	[1411] = { name = "Durotar", ox = 9000, oy = -3000, s = 5000, inst = 1 },
	[1412] = { name = "Mulgore", ox = -6000, oy = 3000, s = 5000, inst = 1 },
	[1456] = { name = "Les Pitons-du-Tonnerre", ox = -5000, oy = 3500, s = 1200, inst = 1 },
	[1454] = { name = "Orgrimmar", ox = 10000, oy = -6000, s = 1500, inst = 1 },
	[1442] = { name = "Les Serres-Rocheuses", ox = -7000, oy = -4000, s = 7000, inst = 1 },
	[1458] = { name = "Fossoyeuse", ox = 0, oy = 0, s = 1000, inst = 0 },
}
AREA_TO_MAP = { [17] = 1413, [14] = 1411, [215] = 1412, [1638] = 1456, [1637] = 1454, [406] = 1442, [1497] = 1458 }

local HBD = {}
function HBD:GetWorldCoordinatesFromZone(x, y, map)
	local m = MAPS[map]
	if not m then return nil end
	return m.ox + x * m.s, m.oy + y * m.s, m.inst
end
PLAYER = { map = 1456, x = 0.375, y = 0.58 }
function HBD:GetPlayerWorldPosition()
	return HBD:GetWorldCoordinatesFromZone(PLAYER.x, PLAYER.y, PLAYER.map)
end

C_Map = {
	GetBestMapForUnit = function() return PLAYER.map end,
	GetPlayerMapPosition = function() return { GetXY = function() return PLAYER.x, PLAYER.y end } end,
	GetMapInfo = function(map) return MAPS[map] and { name = MAPS[map].name } end,
	CanSetUserWaypointOnMap = function() return true end,
	SetUserWaypoint = function() end,
}
UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m, x, y } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
C_AddOns = { IsAddOnLoaded = function(n) return n == "RXPGuides" or n == "QuestieTrace" end, DisableAddOn = function(n, who) DISABLED[#DISABLED + 1] = n .. "@" .. tostring(who) end }

-- Journal (rempli par le test)
LOG = {}
C_QuestLog = {
	GetNumQuestLogEntries = function() return #LOG end,
	GetInfo = function(i) return LOG[i] and LOG[i].info end,
	GetQuestObjectives = function(id) for _, e in ipairs(LOG) do if e.info.questID == id then return e.objectives end end end,
	IsComplete = function(id) for _, e in ipairs(LOG) do if e.info.questID == id then return e.complete end end end,
	ReadyForTurnIn = function() return false end,
	IsFailed = function() return false end,
}

-- Questie simulé
NPCS, OBJECTS, QUESTS, AVAILABLE = {}, {}, {}, {}
local QuestieDB = {}
function QuestieDB.GetQuest(id) return QUESTS[id] end
function QuestieDB:GetNPC(id) return NPCS[id] end
function QuestieDB:GetObject(id) return OBJECTS[id] end
function QuestieDB:GetItem() return nil end
function QuestieDB.IsPvPQuest(id) return id == 8368 end
function QuestieDB.IsGroupQuest() return false end
function QuestieDB.IsDungeonQuest(id) return QUESTS[id] and QUESTS[id].dungeon end
function QuestieDB.IsRaidQuest() return false end
local ZoneDB = {}
local DUNGEONS = { [2437] = { "Gouffre de Ragefeu", nil, 1637, { { 1637, 52.6, 49 } } } }
function ZoneDB:GetDungeons() return DUNGEONS end
function ZoneDB:GetUiMapIdByAreaId(a) return AREA_TO_MAP[a] end
function ZoneDB:GetDungeonLocation(a) return DUNGEONS[a] and DUNGEONS[a][4] end
function ZoneDB:GetLocalizedDungeonName(a) return DUNGEONS[a] and DUNGEONS[a][1] end
local QuestXP = {}
function QuestXP:GetQuestLogRewardXP(id) return QUESTS[id] and QUESTS[id].xp or 800 end
local Avail = { __availableQuests = AVAILABLE }
local modules = { QuestieDB = QuestieDB, ZoneDB = ZoneDB, QuestXP = QuestXP, AvailableQuests = Avail, HBD = HBD }
QuestieLoader = { ImportModule = function(_, name) return modules[name] end }
Questie = { started = true }

-- Shortest Path simulé
SP_ROUTES = {}
ShortestPathForever = { API = { version = 2, minor = 0 } }
local API = ShortestPathForever.API
local journeyOwner
function API.Estimate(fm, fx, fy, tm, tx, ty)
	local ax, ay, ai = HBD:GetWorldCoordinatesFromZone(fx, fy, fm)
	local bx, by, bi = HBD:GetWorldCoordinatesFromZone(tx, ty, tm)
	if not ax or not bx then return nil, "invalid" end
	if ai ~= bi then return 600 end
	local d = math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
	return math.min(d / 7 * 1.25, 90 + d / 25) -- un vol pour les longs trajets
end
function API.NavigateRoute(owner, stops)
	assert(type(owner) == "string")
	assert(#stops >= 1 and #stops <= 64, "stops count")
	for i, s in ipairs(stops) do
		assert(type(s.map) == "number" and type(s.x) == "number" and type(s.y) == "number", "stop " .. i .. " position")
		assert(s.x >= 0 and s.x <= 1 and s.y >= 0 and s.y <= 1, "stop " .. i .. " coords range")
		assert(s.title == nil or type(s.title) == "string")
		assert(s.tooltip == nil or type(s.tooltip) == "string")
		assert(s.hold == nil or type(s.hold) == "boolean")
		if s.questIDs then assert(#s.questIDs >= 1) end
		if s.handins then assert(#s.handins >= 1) end
		if s.npc then assert(type(s.npc) == "number") end
	end
	SP_ROUTES[#SP_ROUTES + 1] = stops
	journeyOwner = owner
	return true
end
function API.Journey() return journeyOwner and { owner = journeyOwner } or nil end
function API.Ended() return nil end
function API.RenameStop() return true end
function API.Cancel() journeyOwner = nil return true end

function LoadAddon(dir, files)
	local ns = {}
	for _, f in ipairs(files) do
		local chunk = assert(loadfile(dir .. "/" .. f))
		chunk("Itineraire", ns)
	end
	return ns
end
function Fire(event, ...)
	for _, f in ipairs(FRAMES) do
		if f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
	end
end
