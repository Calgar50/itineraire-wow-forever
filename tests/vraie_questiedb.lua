-- Charge la VRAIE base QuestieDB (Forever, mode baked) hors du jeu, pour les tests.
-- À lancer avec tests/run_lua_vraie.py (qui fournit l'hôte Python et bride le Lua).
-- Usage : dofile(TESTS .. "/vraie_questiedb.lua")
--         local LQ = ChargerVraieQuestieDB(QUESTIEDB)  -- nil, "absente" si l'addon manque

local hote = rawget(_G, "VRAIE_QDB_HOTE")
VRAIE_QDB_HOTE = nil -- le code de l'addon ne doit pas voir l'hôte

local byte, sub, ldexp, floor = string.byte, string.sub, math.ldexp, math.floor
local concat = table.concat
local chargerSource = loadstring -- version bridée (pas de bytecode) installée par run_lua_vraie.py

-- Décodeur CBOR (RFC 8949) : tableaux -> séquences 1..n, maps -> tables, null/undefined -> nil.
local FIN = {} -- marqueur « break » des longueurs indéfinies
local lireValeur

local function octets(s, pos, n)
	if pos + n - 1 > #s then error("CBOR tronqué", 0) end
	return byte(s, pos, pos + n - 1)
end

local function lireLongueur(s, pos, info)
	if info < 24 then return info, pos end
	if info == 24 then return octets(s, pos, 1), pos + 1 end
	if info == 25 then
		local a, b = octets(s, pos, 2)
		return a * 256 + b, pos + 2
	end
	if info == 26 then
		local a, b, c, d = octets(s, pos, 4)
		return ((a * 256 + b) * 256 + c) * 256 + d, pos + 4
	end
	if info == 27 then
		local a, b, c, d, e, f, g, h = octets(s, pos, 8)
		return ((((((a * 256 + b) * 256 + c) * 256 + d) * 256 + e) * 256 + f) * 256 + g) * 256 + h, pos + 8
	end
	if info == 31 then return nil, pos end -- longueur indéfinie
	error("CBOR : longueur invalide", 0)
end

local function flottant16(a, b)
	local signe = a >= 128 and -1 or 1
	local exp, mant = floor(a / 4) % 32, (a % 4) * 256 + b
	if exp == 0 then return signe * ldexp(mant, -24) end
	if exp == 31 then return mant == 0 and signe * math.huge or 0 / 0 end
	return signe * ldexp(mant + 1024, exp - 25)
end

local function flottant32(a, b, c, d)
	local signe = a >= 128 and -1 or 1
	local exp = (a % 128) * 2 + floor(b / 128)
	local mant = ((b % 128) * 256 + c) * 256 + d
	if exp == 0 then return signe * ldexp(mant, -149) end
	if exp == 255 then return mant == 0 and signe * math.huge or 0 / 0 end
	return signe * ldexp(mant + 8388608, exp - 150)
end

local function flottant64(a, b, c, d, e, f, g, h)
	local signe = a >= 128 and -1 or 1
	local exp = (a % 128) * 16 + floor(b / 16)
	local mant = (((((b % 16) * 256 + c) * 256 + d) * 256 + e) * 256 + f) * 256 + g
	mant = mant * 256 + h
	if exp == 0 then return signe * ldexp(mant, -1074) end
	if exp == 2047 then return mant == 0 and signe * math.huge or 0 / 0 end
	return signe * ldexp(mant + 4503599627370496, exp - 1075)
end

local function lireChaine(s, pos, info, majeur)
	local n
	n, pos = lireLongueur(s, pos, info)
	if n then
		if pos + n - 1 > #s then error("CBOR tronqué", 0) end
		return sub(s, pos, pos + n - 1), pos + n
	end
	local morceaux = {} -- chaîne indéfinie : morceaux du même type jusqu'au break
	while true do
		local ib = octets(s, pos, 1)
		if ib == 255 then return concat(morceaux), pos + 1 end
		if floor(ib / 32) ~= majeur then error("CBOR : morceau de chaîne invalide", 0) end
		morceaux[#morceaux + 1], pos = lireChaine(s, pos + 1, ib % 32, majeur)
	end
end

lireValeur = function(s, pos)
	local ib = octets(s, pos, 1)
	pos = pos + 1
	local majeur, info = floor(ib / 32), ib % 32
	if majeur == 0 then return lireLongueur(s, pos, info) end
	if majeur == 1 then
		local n
		n, pos = lireLongueur(s, pos, info)
		return -1 - n, pos
	end
	if majeur == 2 or majeur == 3 then return lireChaine(s, pos, info, majeur) end
	if majeur == 4 then
		local t, n, v = {}
		n, pos = lireLongueur(s, pos, info)
		if n then
			for i = 1, n do
				v, pos = lireValeur(s, pos)
				t[i] = v
			end
		else
			local i = 0
			while true do
				v, pos = lireValeur(s, pos)
				if v == FIN then break end
				i = i + 1
				t[i] = v
			end
		end
		return t, pos
	end
	if majeur == 5 then
		local t, n, k, v = {}
		n, pos = lireLongueur(s, pos, info)
		local i = 0
		while n == nil or i < n do
			k, pos = lireValeur(s, pos)
			if k == FIN and n == nil then break end
			v, pos = lireValeur(s, pos)
			if k ~= nil then t[k] = v end
			i = i + 1
		end
		return t, pos
	end
	if majeur == 6 then -- étiquette : ignorée, on garde la valeur
		local _
		_, pos = lireLongueur(s, pos, info)
		return lireValeur(s, pos)
	end
	-- majeur 7 : simples et flottants
	if info == 20 then return false, pos end
	if info == 21 then return true, pos end
	if info == 22 or info == 23 then return nil, pos end
	if info == 24 then return nil, pos + 1 end
	if info == 25 then return flottant16(octets(s, pos, 2)), pos + 2 end
	if info == 26 then return flottant32(octets(s, pos, 4)), pos + 4 end
	if info == 27 then return flottant64(octets(s, pos, 8)), pos + 8 end
	if info == 31 then return FIN, pos end
	if info < 20 then return nil, pos end
	error("CBOR : octet initial invalide " .. ib, 0)
end

local function DecoderCBOR(s)
	if type(s) ~= "string" then error("DeserializeCBOR : chaîne attendue", 2) end
	local v, pos = lireValeur(s, 1)
	if v == FIN then error("CBOR : break inattendu", 2) end
	return v, pos
end

-- Appelle une fonction de l'hôte : (nil, message) devient une erreur Lua.
local function appel(fn, ...)
	local v, msg = fn(...)
	if v == nil and msg ~= nil then error(tostring(msg), 3) end
	return v, msg
end

-- Stubs du client WoW nécessaires à QuestieDB ; un stub déjà défini par le test est gardé.
local function stub(nom, valeur)
	if rawget(_G, nom) == nil then _G[nom] = valeur end
end

local function installerClient(nomAddon)
	local nomMin = nomAddon:lower()
	local hoteMeta = hote.meta
	C_AddOns = rawget(_G, "C_AddOns") or {}
	local precedent = C_AddOns.GetAddOnMetadata or rawget(_G, "GetAddOnMetadata")
	local function GetAddOnMetadata(addon, cle)
		if type(addon) == "string" and addon:lower() == nomMin then return hoteMeta(addon, cle) end
		if precedent then return precedent(addon, cle) end
		return nil
	end
	C_AddOns.GetAddOnMetadata = GetAddOnMetadata
	_G.GetAddOnMetadata = GetAddOnMetadata

	C_EncodingUtil = rawget(_G, "C_EncodingUtil") or {}
	local b64, inflate = hote.base64, hote.decompresser
	C_EncodingUtil.DecodeBase64 = function(s, variante) return appel(b64, s, variante) end
	C_EncodingUtil.DecompressString = function(s, methode) return appel(inflate, s, methode) end
	C_EncodingUtil.DeserializeCBOR = function(s) return (DecoderCBOR(s)) end

	stub("GetLocale", function() return "frFR" end)
	stub("UnitFactionGroup", function() return "Horde", "Horde" end)
	stub("UnitRace", function() return "Tauren", "Tauren", 6 end)
	-- Classe du joueur : suit UnitClass si le test en a défini un, sinon guerrier.
	stub("UnitClassBase", function(unite)
		local f = rawget(_G, "UnitClass")
		if f then
			local _, jeton, id = f(unite)
			return jeton, id
		end
		return "WARRIOR", 1
	end)
end

-- Charge l'addon : fichiers .lua du TOC Forever dans l'ordre, avec ... = (nom, table privée).
function ChargerVraieQuestieDB(dossier)
	if not hote then error("ChargerVraieQuestieDB : lancer le test avec tests/run_lua_vraie.py", 2) end
	dossier = dossier or QUESTIEDB
	local nomAddon, liste = appel(hote.toc, dossier)
	if not nomAddon then return nil, "absente" end
	installerClient(nomAddon)
	local prive = {}
	for rel in liste:gmatch("[^\n]+") do
		if rel:match("%.lua$") then
			local src = appel(hote.lire, dossier .. "/" .. rel)
			local chunk, err = chargerSource(src, "@" .. nomAddon .. "/" .. rel)
			if not chunk then error(err, 0) end
			chunk(nomAddon, prive)
		end
	end
	-- api.lua publie aussi cette table en global LibQuestieDB.
	return prive
end
