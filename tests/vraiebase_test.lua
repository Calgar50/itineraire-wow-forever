-- Interroge la VRAIE base QuestieDB (Forever, baked) hors du jeu.
-- Lancer avec : <python> -I tests/run_lua_vraie.py tests/vraiebase_test.lua TESTS=tests ADDON_DIR=Itineraire [QUESTIEDB=...]
dofile(TESTS .. "/vraie_questiedb.lua")

-- Affichage compact et trié d'une valeur (tables tronquées après `max` éléments).
local function rendu(v, max, prof)
	max, prof = max or 12, prof or 0
	if type(v) == "string" then return string.format("%q", v) end
	if type(v) ~= "table" then return tostring(v) end
	if prof > 4 then return "{...}" end
	local cles = {}
	for k in pairs(v) do cles[#cles + 1] = k end
	table.sort(cles, function(a, b)
		if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then return a < b end
		return type(a) < type(b)
	end)
	local morceaux, seq = {}, #cles == #v
	for i, k in ipairs(cles) do
		if i > max then
			morceaux[#morceaux + 1] = "... (" .. #cles .. ")"
			break
		end
		local val = rendu(v[k], max, prof + 1)
		morceaux[#morceaux + 1] = seq and val or ("[" .. rendu(k) .. "]=" .. val)
	end
	return "{" .. table.concat(morceaux, ", ") .. "}"
end

local function cles(t)
	local r = {}
	for k in pairs(t or {}) do r[#r + 1] = tostring(k) end
	table.sort(r)
	return table.concat(r, " ")
end

local function compterPoints(spawns)
	local zones, points = 0, 0
	for _, liste in pairs(spawns or {}) do
		zones = zones + 1
		points = points + #liste
	end
	return points, zones
end

local t0 = os.clock()
local LQ = ChargerVraieQuestieDB(QUESTIEDB)
if not LQ then
	print("SKIP vraie base absente")
	return
end
print(string.format("chargement : %.2f s", os.clock() - t0))

-- Décodeur CBOR : vecteurs de la RFC 8949 (annexe A).
local function hex(h) return (h:gsub("%x%x", function(o) return string.char(tonumber(o, 16)) end)) end
local cbor = C_EncodingUtil.DeserializeCBOR
assert(cbor(hex("f93c00")) == 1.0 and cbor(hex("f9c400")) == -4.0 and cbor(hex("f97bff")) == 65504)
assert(cbor(hex("f90001")) == 2 ^ -24 and cbor(hex("fa47c35000")) == 100000)
assert(cbor(hex("fb3ff199999999999a")) == 1.1 and cbor(hex("fbc010666666666666")) == -4.1)
assert(cbor(hex("3903e7")) == -1000 and cbor(hex("1b000000e8d4a51000")) == 1000000000000)
assert(cbor(hex("f5")) == true and cbor(hex("f4")) == false and cbor(hex("f6")) == nil)
assert(rendu(cbor(hex("9f018202039f0405ffff"))) == "{1, {2, 3}, {4, 5}}")
assert(rendu(cbor(hex("bf61610161629f0203ffff"))) == '{["a"]=1, ["b"]={2, 3}}')
assert(rendu(cbor(hex("a201020304"))) == "{[1]=2, [3]=4}")
assert(cbor(hex("7f657374726561646d696e67ff")) == "streaming")
local trou = cbor(hex("8301f603"))
assert(trou[1] == 1 and trou[2] == nil and trou[3] == 3)

-- Contrat et mode
assert(LQ.RequireContract(4) == true, "contrat 4")
assert(LQ.readMode == "baked", "mode baked")
assert(LibQuestieDB == LQ, "global LibQuestieDB")
print("contrat", LQ.contractVersion, "min", LQ.minSupportedContract, "mode", LQ.readMode, "saveur", LQ.flavor.name)

-- Quête 843
local Q, N, I, O = LQ.Quest, LQ.Npc, LQ.Item, LQ.Object
assert(Q.Exists(843), "quête 843")
for _, champ in ipairs({ "name", "questLevel", "requiredLevel", "startedBy", "finishedBy", "objectives", "zoneOrSort" }) do
	print("quete 843 " .. champ .. " = " .. rendu(Q.Get(843, champ)))
end
local objectifs = Q.Get(843, "objectives")
local objetsQuete = objectifs and objectifs[3]
assert(objetsQuete and objetsQuete[1], "843 : objectif d'objet")
for _, o in ipairs(objetsQuete) do
	local butins = I.Get(o[1], "npcDrops") or {}
	print("objet " .. o[1] .. " = " .. rendu(I.Get(o[1], "name")) .. " npcDrops=" .. rendu(butins))
	for _, id in ipairs(butins) do print("  lache par " .. id .. " = " .. rendu(N.Get(id, "name"))) end
end
local finisseurs = Q.Get(843, "finishedBy")
local pnj = finisseurs[1][1]
assert(N.Exists(pnj), "PNJ de fin")
print("fin " .. pnj .. " = " .. rendu(N.Get(pnj, "name")) .. " npcFlags=" .. rendu(N.Get(pnj, "npcFlags"))
	.. " friendlyToFaction=" .. rendu(N.Get(pnj, "friendlyToFaction")))
print("fin spawns = " .. rendu(N.Get(pnj, "spawns")))
local debut = Q.Get(843, "startedBy")
if debut and debut[1] then
	for _, id in ipairs(debut[1]) do print("debut " .. id .. " = " .. rendu(N.Get(id, "name"))) end
end

-- Zones : areaIdToUiMapId est du code Lua « return {...} » à charger
local zoneDB = LQ.Support.Get("ZoneDB")
local codeZones = zoneDB.private.areaIdToUiMapId
assert(type(codeZones) == "string", "areaIdToUiMapId en texte")
local areaVersCarte = assert(loadstring(codeZones))()
assert(areaVersCarte[17] == 1413, "Tarides 17 -> 1413")
print("areaIdToUiMapId[17] = " .. areaVersCarte[17])

-- Filon d'étain
local points, zones = compterPoints(O.Get(1732, "spawns"))
assert(points > 0, "filon d'étain")
print("objet 1732 " .. rendu(O.Get(1732, "name")) .. " : " .. points .. " points dans " .. zones .. " zones")

-- Parcours complets
local ids = Q.GetAllIds()
assert(#ids > 1000, "liste des quêtes")
local t = os.clock()
local champs = { "questLevel", "requiredLevel", "zoneOrSort", "requiredRaces", "requiredClasses", "preQuestSingle", "exclusiveTo" }
local lus = 0
for _, id in ipairs(ids) do
	for _, champ in ipairs(champs) do
		if Q.Get(id, champ) ~= nil then lus = lus + 1 end
	end
end
print(string.format("quetes : %d ids, %d valeurs lues, %.2f s", #ids, lus, os.clock() - t))
local idsPnj = N.GetAllIds()
assert(#idsPnj > 1000, "liste des PNJ")
t = os.clock()
local avecDrapeaux = 0
for _, id in ipairs(idsPnj) do
	local f = N.Get(id, "npcFlags")
	if f and f ~= 0 then avecDrapeaux = avecDrapeaux + 1 end
end
print(string.format("pnj : %d ids, %d avec npcFlags, %.2f s", #idsPnj, avecDrapeaux, os.clock() - t))
print("objets : " .. #O.GetAllIds() .. " ids, items : " .. #I.GetAllIds() .. " ids")

-- Énumérations
print("raceMaskById = " .. rendu(LQ.Enum.raceMaskById, 40))
print("classKeys = " .. rendu(LQ.Enum.classKeys, 40))
print("npcFlags = " .. rendu(LQ.Enum.npcFlags, 40))

-- Données de support
print("Support : " .. cles(LQ.Support.GetAll()))
print("ZoneDB.private : " .. cles(zoneDB.private))
print("QuestXP : " .. cles(LQ.Support.Get("QuestXP")))
print("QuestieDB : " .. cles(LQ.Support.Get("QuestieDB")))
print("QuestXP.db[843] = " .. rendu(LQ.Support.Get("QuestXP").db[843]))

-- Schémas
print("questKeys = " .. rendu(LQ.Meta.QuestMeta.questKeys, 60))
print("npcKeys = " .. rendu(LQ.Meta.NpcMeta.npcKeys, 60))
print("objectKeys = " .. rendu(LQ.Meta.ObjectMeta.objectKeys, 60))
print("itemKeys = " .. rendu(LQ.Meta.ItemMeta.itemKeys, 60))
print("ObjectiveFirst : " .. cles(LQ.ObjectiveFirst))

print("OK vraie base")
