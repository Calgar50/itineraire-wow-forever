-- Itinéraire : ce que le pilote fait aussi pour toi, hors des PNJ (réglages : /iti reglages > Pilote).
--   - TALENTS : suit un plan de talents (selon ta classe et ton rôle) et met tes points, en te demandant d'abord
--     (par défaut : un clic) ou tout seul. Un point de talent ne se reprend que contre de l'or chez le maître de
--     classe : d'où la question par défaut.
--   - ÉQUIPEMENT : met l'objet de tes sacs qui t'améliore (note de la fenêtre Équipement), hors combat, dès que tu
--     peux le porter. Un objet « lié quand équipé » pas encore lié : il te demande d'abord. Tu remets ton ancien
--     objet : il n'y touche plus (pour la session).
--   - SACS : un sac de tes sacs va dans un emplacement de sac libre.
--   - BARRES D'ACTION : les sorts de ta classe qui n'y sont pas vont dans les cases vides, et un sort passe à son rang
--     supérieur dès que tu l'apprends (à la même place). Guerrier : barres RANGÉES PAR POSTURE (même rôle sur la même
--     touche dans chaque posture), druide (par forme), voleur (camouflage) ; proposé une fois, puis entretenu ;
--     /iti barres.
-- Tout passe par le pilote (marche / arrêt, une case par partie) ; si le jeu bloque une action, la partie se coupe.
--
-- Les plans de talents sont écrits pour WoW Forever 1.60.1 (arbres du client, build 70959 : talents nouveaux ou
-- changés par rapport à Classic compris). Un talent est reconnu par son sort (identifiant), puis par le nom de ce sort
-- dans la langue du jeu, puis par son nom anglais : un plan reste bon si Blizzard déplace un talent dans l'arbre. C'est
-- le jeu qui dit si un point est possible (paliers, prérequis) : un pas impossible attend, le suivant passe.
local _, ns = ...
local Auto = {}
ns.Auto = Auto

local function Call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n = pcall(fn, ...)
	if ok then
		return a, b, c, d, e, f, g, h, i, j, k, l, m, n
	end
	return nil
end

local function Num(v)
	if type(v) ~= "number" then
		return nil
	end
	-- Forever : une valeur « secrète » (combat, instance) a le type number mais refuse tout calcul
	local ok, secret = pcall(function()
		return (issecretvalue and issecretvalue(v)) or (canaccessvalue and not canaccessvalue(v)) or false
	end)
	if not ok or secret then
		return nil
	end
	return v
end

local function Level()
	return Num(Call(UnitLevel, "player")) or 1
end

local function InCombat()
	return (InCombatLockdown and Call(InCombatLockdown)) or (UnitAffectingCombat and Call(UnitAffectingCombat, "player"))
		or false
end

local function Cfg()
	return ns.Pilote.Config()
end

-- La partie `key` du pilote est-elle permise ? (pilote en marche, case cochée, pas bloquée par le jeu)
local function Allowed(key)
	return ns.Pilote.Active and ns.Pilote.Active(key, true) or false
end

Auto.log = {}
local function Note(text)
	local log = Auto.log
	log[#log + 1] = date("%H:%M:%S") .. " " .. text
	while #log > 12 do
		table.remove(log, 1)
	end
end

-------------------------------------------------------------------------------
-- Fenêtre de question (la sienne : pas les fenêtres du jeu, pour ne rien contaminer)
-------------------------------------------------------------------------------
local ask, queue = nil, {}

local function ShowNext()
	if not ask or ask:IsShown() or #queue == 0 or InCombat() then
		return
	end
	local q = table.remove(queue, 1)
	ask.current = q
	ask.text:SetText(q.text)
	for i, b in ipairs(ask.buttons) do
		local choice = q.buttons[i]
		b:SetShown(choice ~= nil)
		if choice then
			b:SetText(choice.label)
		end
	end
	ask:SetHeight(math.max(96, (ask.text:GetStringHeight() or 30) + 74))
	ns.UI.Skin.Panel(ask, 0.97)
	ns.UI.Skin.HeaderColors(ask)
	ask:Show()
end

local function Build()
	ask = CreateFrame("Frame", "ItineraireQuestion", UIParent, "BackdropTemplate")
	ask:SetSize(340, 110)
	ask:SetPoint("TOP", UIParent, "TOP", 0, -160)
	ask:SetFrameStrata("DIALOG")
	ask:SetClampedToScreen(true)
	ask:SetMovable(true)
	ask:EnableMouse(true)
	ask:RegisterForDrag("LeftButton")
	ask:SetScript("OnDragStart", ask.StartMoving)
	ask:SetScript("OnDragStop", ask.StopMovingOrSizing)
	ask:Hide()
	ns.UI.Skin.Header(ask, "Itinéraire — pilote", "Interface\\Icons\\Ability_Hunter_Pathfinding", 24)
	ask.text = ask:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	ask.text:SetPoint("TOPLEFT", 14, -34)
	ask.text:SetPoint("RIGHT", -14, 0)
	ask.text:SetJustifyH("LEFT")
	ask.buttons = {}
	for i = 1, 3 do
		local b = ns.UI.Skin.Button(ask, "", 100, 22, function()
			local q = rawget(ask, "current")
			ask:Hide()
			ask.current = nil
			local choice = q and q.buttons[i]
			if choice and choice.func then
				local ok, err = pcall(choice.func)
				if not ok and ns.OnError then
					ns.OnError("pilote (question) : " .. tostring(err))
				end
			end
			ShowNext()
		end)
		b:SetPoint("BOTTOMLEFT", 12 + (i - 1) * 106, 10)
		ask.buttons[i] = b
	end
end

-- Pose une question (une à la fois, jamais en combat). `key` : une seule question de ce genre en attente.
-- buttons = { { label, func }, … } (3 au plus).
function Auto.Ask(key, text, buttons)
	if not ask then
		Build()
	end
	local current = rawget(ask, "current")
	if current and current.key == key then
		return
	end
	for i, q in ipairs(queue) do
		if q.key == key then
			queue[i] = { key = key, text = text, buttons = buttons }
			return
		end
	end
	queue[#queue + 1] = { key = key, text = text, buttons = buttons }
	ShowNext()
end

function Auto.Asking(key)
	local current = ask and rawget(ask, "current")
	if current and current.key == key then
		return true
	end
	for _, q in ipairs(queue) do
		if q.key == key then
			return true
		end
	end
	return false
end

-------------------------------------------------------------------------------
-- Plans de talents
-------------------------------------------------------------------------------
-- S(onglet, sort de rang 1, nom anglais, du rang, au rang) : une suite de points dans un talent.
-- Plan(rôle, libellé, { { onglet, sort de rang 1, nom anglais, du rang, au rang }, … }) : chaque ligne = des points
-- d'affilée dans un talent, dans l'ordre des niveaux (10, 11, …, 60). Rôles : tank, melee, ranged, caster, healer
-- (ceux de la fenêtre Équipement) ; le plan dont la clé est le rôle est celui par défaut pour ce rôle.
local function Plan(role, label, parts)
	local steps = {}
	for _, p in ipairs(parts) do
		for rank = p[4], p[5] do
			steps[#steps + 1] = { tab = p[1], spell = p[2], en = p[3], rank = rank }
		end
	end
	return { role = role, label = label, steps = steps }
end
local ROLE_ORDER = { tank = 1, melee = 2, ranged = 3, caster = 4, healer = 5 }

local function SortedKeys(plans)
	local keys = {}
	for key in pairs(plans) do
		keys[#keys + 1] = key
	end
	table.sort(keys, function(a, b)
		local ra, rb = ROLE_ORDER[plans[a].role] or 9, ROLE_ORDER[plans[b].role] or 9
		if ra ~= rb then
			return ra < rb
		end
		if (a == plans[a].role) ~= (b == plans[b].role) then
			return a == plans[a].role -- (le plan par défaut du rôle d'abord)
		end
		return a < b
	end)
	return keys
end

-- Plans des 9 classes (Forever 1.60.1, arbres de ForeverDB build 70959 ; écrits pour Itinéraire et vérifiés hors jeu :
-- 51 points, paliers de 5 points par arbre, rangs max, noms et sorts). Un point par niveau de 10 à 60. Les flèches de
-- prérequis ne sont pas dans les données : chaque plan met d'abord le talent probablement requis ; de toute façon c'est
-- le jeu qui dit si un point est possible (sinon le pas attend et le suivant passe).
local PLANS = {
	WARRIOR = {
		tank = Plan("tank", "Protection (tank, avec bouclier)", {
			{ 3, 12298, "Shield Specialization", 1, 5 }, -- 10-14 : blocage, rage au blocage
			{ 3, 12797, "Improved Revenge", 1, 3 }, -- 15-17
			{ 3, 12297, "Anticipation", 1, 2 }, -- 18-19
			{ 3, 1310316, "Master of Defense", 1, 2 }, -- 20-21 : rage sur esquive / parade
			{ 3, 12975, "Last Stand", 1, 1 }, -- 22
			{ 3, 12792, "Defiance", 1, 2 }, -- 23-24 : menace
			{ 3, 1310317, "Vanguard", 1, 1 }, -- 25 : Charge en posture défensive
			{ 3, 12792, "Defiance", 3, 3 }, -- 26
			{ 3, 12297, "Anticipation", 3, 5 }, -- 27-29
			{ 3, 12809, "Concussion Blow", 1, 1 }, -- 30
			{ 3, 29787, "Focused Rage", 1, 3 }, -- 31-33
			{ 3, 12301, "Improved Bloodrage", 1, 1 }, -- 34
			{ 3, 16538, "Bastion", 1, 5 }, -- 35-39
			{ 3, 23922, "Shield Slam", 1, 1 }, -- 40
			{ 3, 12287, "Improved Thunder Clap", 1, 3 }, -- 41-43
			{ 3, 12308, "Improved Sunder Armor", 1, 3 }, -- 44-46
			{ 3, 12312, "Improved Shield Wall", 1, 2 }, -- 47-48
			{ 3, 12301, "Improved Bloodrage", 2, 2 }, -- 49
			{ 3, 12311, "Improved Shield Bash", 1, 2 }, -- 50-51
			{ 3, 12962, "Iron Will", 1, 5 }, -- 52-56
			{ 3, 12313, "Improved Disarm", 1, 3 }, -- 57-59
			{ 1, 12282, "Improved Heroic Strike", 1, 1 }, -- 60
		}),
		melee = Plan("melee", "Armes (arme à deux mains)", {
			{ 1, 12282, "Improved Heroic Strike", 1, 3 }, -- 10-12
			{ 1, 16462, "Deflection", 1, 2 }, -- 13-14
			{ 1, 12285, "Improved Charge", 1, 2 }, -- 15-16
			{ 1, 12290, "Improved Overpower", 1, 2 }, -- 17-18
			{ 1, 12295, "Improved Tactical Mastery", 1, 1 }, -- 19
			{ 1, 12296, "Anger Management", 1, 1 }, -- 20
			{ 1, 12834, "Deep Wounds", 1, 3 }, -- 21-23
			{ 1, 12295, "Improved Tactical Mastery", 2, 2 }, -- 24
			{ 1, 12163, "Two-Handed Weapon Specialization", 1, 3 }, -- 25-27
			{ 1, 16493, "Impale", 1, 2 }, -- 28-29
			{ 1, 12292, "Sweeping Strikes", 1, 1 }, -- 30
			{ 1, 1290261, "Weaponmaster", 1, 5 }, -- 31-35
			{ 1, 12862, "Improved Slam", 1, 2 }, -- 36-37
			{ 1, 1310222, "Spearing Strike", 1, 1 }, -- 38
			{ 1, 1289682, "Bloodthrill", 1, 1 }, -- 39
			{ 1, 12294, "Mortal Strike", 1, 1 }, -- 40
			{ 1, 1289682, "Bloodthrill", 2, 2 }, -- 41
			{ 1, 16462, "Deflection", 3, 5 }, -- 42-44
			{ 1, 12295, "Improved Tactical Mastery", 3, 3 }, -- 45
			{ 2, 12320, "Cruelty", 1, 5 }, -- 46-50
			{ 2, 12322, "Unbridled Wrath", 1, 5 }, -- 51-55
			{ 2, 16487, "Blood Craze", 1, 3 }, -- 56-58
			{ 2, 12323, "Piercing Howl", 1, 1 }, -- 59
			{ 1, 12286, "Improved Rend", 1, 1 }, -- 60
		}),
		melee_fureur = Plan("melee", "Fureur (deux armes)", {
			{ 2, 12320, "Cruelty", 1, 5 }, -- 10-14 : +5 % de critique
			{ 2, 12322, "Unbridled Wrath", 1, 5 }, -- 15-19 : rage sur chaque coup
			{ 2, 12317, "Enrage", 1, 5 }, -- 20-24 : +10 % de dégâts, prérequis de Rafale
			{ 2, 1329555, "Reckless Swings", 1, 1 }, -- 25 : +20 rage à la demande
			{ 2, 23584, "Dual Wield Specialization", 1, 5 }, -- 26-30 : main gauche, dégâts et rage
			{ 2, 12328, "Death Wish", 1, 1 }, -- 31 : +20 % de dégâts physiques
			{ 2, 1323963, "Furious Precision", 1, 3 }, -- 32-34 : toucher main gauche
			{ 2, 12319, "Flurry", 1, 3 }, -- 35-37 : vitesse après un critique
			{ 2, 1323967, "Gore Drinker", 1, 2 }, -- 38-39 : soins en combat, moins de pauses
			{ 2, 23881, "Bloodthirst", 1, 1 }, -- 40
			{ 2, 1310315, "Improved Whirlwind", 1, 2 }, -- 41-42 : Tourbillon plus fréquent
			{ 2, 20500, "Improved Berserker Rage", 1, 2 }, -- 43-44 : +10 rage
			{ 2, 20502, "Improved Execute", 1, 2 }, -- 45-46 : Exécution moins chère
			{ 1, 12282, "Improved Heroic Strike", 1, 3 }, -- 47-49 : surplus de rage
			{ 1, 16462, "Deflection", 1, 2 }, -- 50-51 : parade, ouvre le palier 2
			{ 1, 12285, "Improved Charge", 1, 2 }, -- 52-53 : rage à l'ouverture
			{ 1, 12295, "Improved Tactical Mastery", 1, 3 }, -- 54-56 : garder la rage en changeant de posture
			{ 1, 12296, "Anger Management", 1, 1 }, -- 57 : rage passive
			{ 1, 12834, "Deep Wounds", 1, 3 }, -- 58-60 : saignement sur critique
		}),
	},
	PALADIN = {
		healer = Plan("healer", "Sacré (soins)", {
			{ 1, 20205, "Spiritual Focus", 1, 5 }, -- 10-14 : soins sans recul quand on est frappé
			{ 1, 1310899, "Reverence", 1, 2 }, -- 15-16 : mana en combat
			{ 1, 20237, "Healing Light", 1, 3 }, -- 17-19 : +12 % de soins
			{ 1, 1237268, "Holy Conduit", 1, 2 }, -- 20-21 : Consécration et Exorcisme moins chers
			{ 1, 429144, "Purifying Power", 1, 2 }, -- 22-23 : Exorcisme plus souvent, Épuration moins chère
			{ 1, 20216, "Divine Favor", 1, 1 }, -- 24 : avant Horion sacré (prérequis probable)
			{ 1, 1310904, "Divine Precision", 1, 2 }, -- 25-26 : toucher des sorts du Sacré
			{ 1, 426065, "Infusion of Light", 1, 2 }, -- 27-28 : Lumière sacrée plus rapide après un critique
			{ 1, 1328548, "Oath of Light", 1, 1 }, -- 29 : serment sur le tank
			{ 1, 1311606, "Holy Shock", 1, 1 }, -- 30
			{ 1, 20210, "Illumination", 1, 4 }, -- 31-34 : mana rendu sur soin critique
			{ 1, 5923, "Holy Power", 1, 5 }, -- 35-39 : soins critiques plus forts
			{ 1, 1310911, "Light's Vigil", 1, 1 }, -- 40
			{ 1, 20210, "Illumination", 5, 5 }, -- 41
			{ 1, 1328550, "Boundless Light", 1, 2 }, -- 42-43 : critique d'Horion sacré
			{ 3, 20101, "Benediction", 1, 5 }, -- 44-48 : sorts instantanés moins chers
			{ 3, 20117, "Conviction", 1, 3 }, -- 49-51 : +6 % de critique, soins compris
			{ 2, 20257, "Divine Intellect", 1, 5 }, -- 52-56 : +10 % d'Intelligence
			{ 2, 1224697, "Sacred Duty", 1, 2 }, -- 57-58 : Bouclier divin plus souvent
			{ 2, 20174, "Guardian's Favor", 1, 2 }, -- 59-60 : Bénédiction de protection plus souvent
		}),
		tank = Plan("tank", "Protection (tank)", {
			{ 2, 20127, "Redoubt", 1, 5 }, -- 10-14 : blocage (prérequis probable de Spécialisation bouclier)
			{ 2, 20189, "Precision", 1, 3 }, -- 15-17 : +3 % de toucher
			{ 2, 1224697, "Sacred Duty", 1, 2 }, -- 18-19 : bulles plus souvent
			{ 2, 20150, "Shield Specialization", 1, 2 }, -- 20-21 : mana rendu au blocage
			{ 2, 1311015, "Templar's Bulwark", 1, 1 }, -- 22 : bouclier de 100 % des PV
			{ 2, 20143, "Toughness", 1, 2 }, -- 23-24 : armure
			{ 2, 20468, "Improved Righteous Fury", 1, 3 }, -- 25-27 : -9 % de dégâts subis
			{ 2, 1310994, "Swift Judgement", 1, 1 }, -- 28 : second Jugement
			{ 2, 20096, "Anticipation", 1, 1 }, -- 29
			{ 2, 20925, "Holy Shield", 1, 1 }, -- 30
			{ 2, 20177, "Reckoning", 1, 4 }, -- 31-34 : attaques en plus après un blocage
			{ 2, 1311034, "Iron Creed", 1, 3 }, -- 35-37 : menace de Frappe sacrée
			{ 2, 20177, "Reckoning", 5, 5 }, -- 38
			{ 2, 20143, "Toughness", 3, 3 }, -- 39
			{ 2, 1328544, "Shieldsworn", 1, 1 }, -- 40
			{ 2, 20096, "Anticipation", 2, 5 }, -- 41-44 : défense
			{ 2, 20143, "Toughness", 4, 5 }, -- 45-46
			{ 2, 20257, "Divine Intellect", 1, 5 }, -- 47-51 : réserve de mana
			{ 2, 20487, "Improved Hammer of Justice", 1, 3 }, -- 52-54 : étourdissement plus souvent
			{ 2, 1328546, "Stoicism", 1, 2 }, -- 55-56
			{ 2, 20174, "Guardian's Favor", 1, 2 }, -- 57-58
			{ 3, 20060, "Deflection", 1, 2 }, -- 59-60 : parade
		}),
		melee = Plan("melee", "Vindicte (arme à deux mains)", {
			{ 3, 20101, "Benediction", 1, 5 }, -- 10-14 : sorts instantanés moins chers
			{ 3, 25956, "Improved Judgement", 1, 2 }, -- 15-16 : Jugement plus souvent
			{ 3, 20117, "Conviction", 1, 3 }, -- 17-19 : +6 % de critique (prérequis probable de Vengeance)
			{ 3, 20375, "Seal of Command", 1, 1 }, -- 20
			{ 3, 26022, "Pursuit of Justice", 1, 2 }, -- 21-22 : +15 % de vitesse, monture comprise
			{ 3, 1311074, "Sanctified Judgement", 1, 2 }, -- 23-24 : mana rendu au Jugement
			{ 3, 20111, "Two-Handed Weapon Specialization", 1, 3 }, -- 25-27 : +6 % de dégâts
			{ 3, 1311087, "Sacred Arbiter", 1, 1 }, -- 28 : Frappe sacrée +20 %
			{ 3, 1311074, "Sanctified Judgement", 3, 3 }, -- 29
			{ 3, 20049, "Vengeance", 1, 3 }, -- 30-32
			{ 3, 9452, "Vindication", 1, 2 }, -- 33-34 : la cible frappe moins fort
			{ 3, 1311084, "Champion of the Light", 1, 5 }, -- 35-39 : puissance des sorts selon l'Intelligence
			{ 3, 1310735, "Unsealed Wrath", 1, 1 }, -- 40
			{ 1, 20262, "Divine Strength", 1, 5 }, -- 41-45 : +10 % de Force
			{ 1, 20224, "Improved Seals", 1, 5 }, -- 46-50 : sceaux et Jugements +15 %
			{ 1, 1237268, "Holy Conduit", 1, 2 }, -- 51-52 : mana
			{ 1, 429144, "Purifying Power", 1, 2 }, -- 53-54 : Exorcisme et Colère divine plus souvent
			{ 1, 1310899, "Reverence", 1, 2 }, -- 55-56 : mana en combat
			{ 1, 1310904, "Divine Precision", 1, 2 }, -- 57-58 : +8 % de toucher des sorts du Sacré
			{ 3, 9452, "Vindication", 3, 3 }, -- 59
			{ 3, 20066, "Repentance", 1, 1 }, -- 60 : contrôle d'un humanoïde
		}),
	},
	HUNTER = {
		ranged = Plan("ranged", "Maîtrise des bêtes (montée de niveau)", {
			{ 1, 19552, "Deadly Aspects", 1, 5 }, -- 10-14 : Aspect du faucon, hâte à distance
			{ 1, 1223755, "Focused Fire", 1, 2 }, -- 15-16 : +2 % dégâts (vous et familier)
			{ 1, 19583, "Endurance Training", 1, 3 }, -- 17-19 : vie et armure du familier
			{ 1, 19616, "Unleashed Fury", 1, 5 }, -- 20-24 : dégâts du familier et des faucons
			{ 1, 1293241, "Summon Hawk", 1, 1 }, -- 25 : faucons (temps de recharge d'Arcane)
			{ 1, 19598, "Ferocity", 1, 5 }, -- 26-30 : critique familier / faucons, prérequis de Frénésie
			{ 1, 19577, "Intimidation", 1, 1 }, -- 31 : étourdissement, prérequis du Courroux
			{ 1, 19590, "Bestial Discipline", 1, 2 }, -- 32-33 : focalisation + régén. de mana en combat
			{ 1, 19578, "Spirit Bond", 1, 1 }, -- 34 : régénération de vie
			{ 1, 19621, "Frenzy", 1, 5 }, -- 35-39 : hâte du familier après critique
			{ 1, 19574, "Bestial Wrath", 1, 1 }, -- 40 : courroux bestial
			{ 2, 19426, "Lethal Attacks", 1, 5 }, -- 41-45 : +5 % critique
			{ 2, 1223984, "Careful Aim", 1, 5 }, -- 46-50 : puissance d'attaque = 100 % Intelligence
			{ 2, 415405, "Rapid Killing", 1, 2 }, -- 51-52 : Tir rapide plus fréquent, bonus après un kill
			{ 2, 19416, "Efficiency", 1, 3 }, -- 53-55 : coût en mana des tirs
			{ 2, 19485, "Mortal Shots", 1, 5 }, -- 56-60 : dégâts des critiques
		}),
		ranged_precision = Plan("ranged", "Précision", {
			{ 2, 19426, "Lethal Attacks", 1, 5 }, -- 10-14 : +5 % critique
			{ 2, 1223984, "Careful Aim", 1, 5 }, -- 15-19 : puissance d'attaque = 100 % Intelligence
			{ 2, 415405, "Rapid Killing", 1, 2 }, -- 20-21 : Tir rapide plus fréquent, bonus après un kill
			{ 2, 19454, "Improved Arcane Shot", 1, 3 }, -- 22-24 : Tir des arcanes plus fréquent
			{ 2, 19485, "Mortal Shots", 1, 5 }, -- 25-29 : dégâts des critiques
			{ 2, 1223987, "Rapid Recuperation", 1, 2 }, -- 30-31 : régén. de mana après Morsure de serpent
			{ 2, 19461, "Barrage", 1, 3 }, -- 32-34 : Flèches multiples, Visée, Salve
			{ 2, 19507, "Ranged Weapon Specialization", 1, 5 }, -- 35-39 : +5 % dégâts à distance
			{ 2, 1310687, "Sniper Shot", 1, 1 }, -- 40 : tir de précision longue portée
			{ 1, 19552, "Deadly Aspects", 1, 5 }, -- 41-45 : Aspect du faucon, hâte à distance
			{ 3, 24293, "Improved Tracking", 1, 5 }, -- 46-50 : +5 % dégâts sur le type pisté
			{ 3, 19255, "Survivalist", 1, 5 }, -- 51-55 : +10 % vie
			{ 3, 19290, "Surefooted", 1, 3 }, -- 56-58 : +3 % toucher
			{ 2, 1299346, "Trueshot Aura", 1, 1 }, -- 59 : aura de groupe
			{ 2, 415370, "Lone Wolf", 1, 1 }, -- 60 : +20 % dégâts sans familier (raid)
		}),
		ranged_survie = Plan("ranged", "Survie", {
			{ 3, 24293, "Improved Tracking", 1, 5 }, -- 10-14 : +5 % dégâts sur le type pisté
			{ 3, 19255, "Survivalist", 1, 5 }, -- 15-19 : +10 % vie
			{ 3, 19290, "Surefooted", 1, 3 }, -- 20-22 : +3 % toucher, ralentissements réduits
			{ 3, 19263, "Deterrence", 1, 1 }, -- 23 : dissuasion, prérequis de Contre-attaque
			{ 3, 19295, "Deflection", 1, 1 }, -- 24 : parade
			{ 3, 19306, "Counterattack", 1, 1 }, -- 25 : riposte et immobilisation
			{ 3, 19376, "Survival Tactics", 1, 2 }, -- 26-27 : pièges et Feindre la mort fiables
			{ 3, 19295, "Deflection", 2, 3 }, -- 28-29 : parade
			{ 3, 440529, "Resourcefulness", 1, 2 }, -- 30-31 : régén. de mana sur critique
			{ 3, 1310532, "Expose Prey", 1, 2 }, -- 32-33 : Morsure de la mangouste sur cible marquée
			{ 3, 1317257, "Strider Kick", 1, 1 }, -- 34 : coup de pied + vitesse pour reprendre la distance
			{ 3, 19168, "Lightning Reflexes", 1, 5 }, -- 35-39 : +15 % Agilité
			{ 3, 1310533, "Lacerating Strikes", 1, 1 }, -- 40 : saignement de la Morsure de la mangouste
			{ 2, 19426, "Lethal Attacks", 1, 5 }, -- 41-45 : +5 % critique
			{ 2, 1223984, "Careful Aim", 1, 5 }, -- 46-50 : puissance d'attaque = 100 % Intelligence
			{ 2, 415405, "Rapid Killing", 1, 2 }, -- 51-52 : Tir rapide plus fréquent, bonus après un kill
			{ 2, 19454, "Improved Arcane Shot", 1, 3 }, -- 53-55 : Tir des arcanes plus fréquent
			{ 2, 19485, "Mortal Shots", 1, 5 }, -- 56-60 : dégâts des critiques
		}),
	},
	ROGUE = {
		melee = Plan("melee", "Combat (épées / masses, montée de niveau)", {
			{ 2, 13732, "Efficient Strikes", 1, 2 }, -- 10-11 : Attaque pernicieuse moins chère
			{ 2, 14162, "Coup de Grace", 1, 3 }, -- 12-14 : Éviscération +20 %
			{ 2, 13705, "Precision", 1, 3 }, -- 15-17 : toucher +3 %
			{ 2, 13713, "Deflection", 1, 2 }, -- 18-19 : parade
			{ 2, 13742, "Endurance", 1, 2 }, -- 20-21 : Sprint et Évasion -60 % de recharge
			{ 2, 13713, "Deflection", 3, 3 }, -- 22 : maxée avant Riposte
			{ 2, 14251, "Riposte", 1, 1 }, -- 23 : frappe et désarme après une parade
			{ 2, 1329265, "Composure", 1, 1 }, -- 24 : Poised plus économe
			{ 2, 1310711, "Flawless Execution", 1, 1 }, -- 25 : Éviscération -15 énergie
			{ 2, 18427, "Aggression", 1, 3 }, -- 26-28 : Attaque pernicieuse et Éviscération +15 %
			{ 2, 30919, "Weapon Expertise", 1, 1 }, -- 29 : moins d'esquives et de parades
			{ 2, 13715, "Dual Wield Specialization", 1, 2 }, -- 30-31 : main gauche +50 % (Précision maxée avant)
			{ 2, 13877, "Blade Flurry", 1, 1 }, -- 32 : vitesse et multi-cibles
			{ 2, 13960, "Hack and Slash", 1, 2 }, -- 33-34 : épée = attaque bonus, masse = ignore l'armure
			{ 2, 1329284, "Flash of Steel", 1, 5 }, -- 35-39 : Shank +15 énergie, recharge -2 s
			{ 2, 13750, "Adrenaline Rush", 1, 1 }, -- 40 : capstone, régénération d'énergie x2
			{ 2, 13960, "Hack and Slash", 3, 5 }, -- 41-43
			{ 2, 30919, "Weapon Expertise", 2, 2 }, -- 44
			{ 2, 1329265, "Composure", 2, 2 }, -- 45
			{ 1, 14138, "Malice", 1, 5 }, -- 46-50 : critique +5 %
			{ 1, 14165, "Improved Slice and Dice", 1, 3 }, -- 51-53 : Débiter +45 %
			{ 1, 14156, "Ruthlessness", 1, 2 }, -- 54-55 : point de combo offert
			{ 1, 14128, "Lethality", 1, 2 }, -- 56-57 : dégâts critiques (Malice maxée avant)
			{ 1, 14983, "Vigor", 1, 2 }, -- 58-59 : énergie max +10
			{ 1, 14156, "Ruthlessness", 3, 3 }, -- 60
		}),
		melee_assassinat = Plan("melee", "Assassinat (dagues)", {
			{ 1, 14138, "Malice", 1, 5 }, -- 10-14 : critique +5 %
			{ 1, 14156, "Ruthlessness", 1, 3 }, -- 15-17 : point de combo offert
			{ 1, 14165, "Improved Slice and Dice", 1, 2 }, -- 18-19 : Débiter plus long
			{ 1, 14128, "Lethality", 1, 2 }, -- 20-21 : dégâts critiques (Malice maxée avant)
			{ 1, 14983, "Vigor", 1, 2 }, -- 22-23 : énergie max +10
			{ 1, 14165, "Improved Slice and Dice", 3, 3 }, -- 24
			{ 1, 14177, "Cold Blood", 1, 1 }, -- 25 : critique garanti
			{ 1, 16513, "Vile Poisons", 1, 4 }, -- 26-29 : poisons +dégâts
			{ 1, 14179, "Relentless Strikes", 1, 5 }, -- 30-34 : énergie rendue par les coups de grâce
			{ 1, 14186, "Seal Fate", 1, 3 }, -- 35-37 : critique = combo bonus (Sang-froid avant)
			{ 1, 16513, "Vile Poisons", 5, 5 }, -- 38
			{ 1, 14113, "Improved Poisons", 1, 1 }, -- 39 : poisons plus fréquents
			{ 1, 399956, "Mutilate", 1, 1 }, -- 40 : capstone, deux armes, 2 combos
			{ 1, 14113, "Improved Poisons", 2, 5 }, -- 41-44
			{ 1, 1329328, "Venom", 1, 1 }, -- 45 : Shank renforce les poisons
			{ 2, 14162, "Coup de Grace", 1, 3 }, -- 46-48 : Éviscération +20 %
			{ 2, 13712, "Lightning Reflexes", 1, 2 }, -- 49-50 : esquive, ouvre le palier 2
			{ 2, 1224716, "Puncturing Wounds", 1, 3 }, -- 51-53 : Mutilation +15 % de critique
			{ 2, 13705, "Precision", 1, 3 }, -- 54-56 : toucher +3 %
			{ 2, 1329265, "Composure", 1, 2 }, -- 57-58 : Poised plus économe
			{ 2, 13742, "Endurance", 1, 2 }, -- 59-60 : Sprint et Évasion plus souvent
		}),
		melee_finesse = Plan("melee", "Finesse", {
			{ 3, 14057, "Opportunity", 1, 5 }, -- 10-14 : Attaque sournoise, Embuscade, Garrot +20 %
			{ 3, 14082, "Dirty Deeds", 1, 2 }, -- 15-16 : ouvertures moins chères, Garrot de face
			{ 3, 14079, "Improved Ambush", 1, 3 }, -- 17-19 : Embuscade +45 % de critique
			{ 3, 14183, "Premeditation", 1, 1 }, -- 20 : +2 points de combo
			{ 3, 13976, "Initiative", 1, 3 }, -- 21-23 : +1 combo sur les ouvertures
			{ 3, 14171, "Serrated Blades", 1, 1 }, -- 24 : ignore l'armure, Rupture +30 %
			{ 3, 14278, "Ghostly Strike", 1, 1 }, -- 25 : frappe et esquive +15 %
			{ 3, 14171, "Serrated Blades", 2, 3 }, -- 26-27 : maxées avant Hémorragie
			{ 3, 13981, "Elusiveness", 1, 2 }, -- 28-29 : Disparition et Cécité -90 s
			{ 3, 16511, "Hemorrhage", 1, 1 }, -- 30 : générateur sans placement
			{ 3, 14185, "Preparation", 1, 1 }, -- 31 : remet les recharges à zéro
			{ 3, 30894, "Heightened Senses", 1, 2 }, -- 32-33 : moins touché par sorts et tirs
			{ 3, 13983, "Setup", 1, 1 }, -- 34 : combo sur esquive, ouvre le palier 6
			{ 3, 1329286, "Boot Knife", 1, 5 }, -- 35-39 : Shank +2 points de combo
			{ 3, 1316709, "Death Mark", 1, 1 }, -- 40 : capstone, coup de grâce à dégâts stockés
			{ 2, 14162, "Coup de Grace", 1, 3 }, -- 41-43 : Death Mark et Éviscération +20 %
			{ 2, 13732, "Efficient Strikes", 1, 2 }, -- 44-45 : Hémorragie moins chère
			{ 2, 13705, "Precision", 1, 3 }, -- 46-48 : toucher +3 %
			{ 2, 1224716, "Puncturing Wounds", 1, 3 }, -- 49-51 : Attaque sournoise +30 % de critique
			{ 1, 14138, "Malice", 1, 5 }, -- 52-56 : critique +5 %
			{ 1, 14165, "Improved Slice and Dice", 1, 3 }, -- 57-59 : Débiter +45 %
			{ 1, 14156, "Ruthlessness", 1, 1 }, -- 60 : point de combo offert
		}),
	},
	PRIEST = {
		caster = Plan("caster", "Ombre (montée de niveau, dégâts)", {
			{ 3, 15270, "Spirit Tap", 1, 5 }, -- 10-14 : Esprit doublé et régén après chaque victime
			{ 3, 15275, "Improved Shadow Word: Pain", 1, 2 }, -- 15-16 : Douleur +6 s
			{ 3, 15273, "Improved Mind Blast", 1, 3 }, -- 17-19 : Attaque mentale plus fréquente
			{ 3, 15407, "Mind Flay", 1, 1 }, -- 20 : Fouet mental, ralentit
			{ 3, 1225139, "Improved Mind Flay", 1, 2 }, -- 21-22 : Fouet mental croissant
			{ 3, 15273, "Improved Mind Blast", 4, 5 }, -- 23-24
			{ 3, 15286, "Vampiric Embrace", 1, 1 }, -- 25 : auto-soin, prérequis probable de Forme d'Ombre
			{ 3, 15257, "Shadow Weaving", 1, 3 }, -- 26-28 : jusqu'à +10 % dégâts d'ombre
			{ 3, 15260, "Shadow Focus", 1, 1 }, -- 29 : toucher
			{ 3, 15487, "Silence", 1, 1 }, -- 30 : interruption
			{ 3, 15260, "Shadow Focus", 2, 5 }, -- 31-34 : +5 % toucher
			{ 3, 15259, "Darkness", 1, 5 }, -- 35-39 : +10 % dégâts d'ombre
			{ 3, 15473, "Shadowform", 1, 1 }, -- 40 : Forme d'Ombre, mana des sorts d'ombre -50 %
			{ 1, 14524, "Wand Specialization", 1, 2 }, -- 41-42 : baguette +25 %
			{ 1, 1225132, "Twin Disciplines", 1, 5 }, -- 43-47 : Douleur et instantanés +5 %
			{ 1, 14523, "Silent Resolve", 1, 3 }, -- 48-50 : menace -30 %
			{ 1, 14521, "Meditation", 1, 3 }, -- 51-53 : 50 % de régén en incantant
			{ 3, 1326159, "Dark Inspiration", 1, 5 }, -- 54-58 : Esprit +15 % pour le groupe
			{ 3, 17322, "Shadow Reach", 1, 2 }, -- 59-60 : portée +20 %
		}),
		healer = Plan("healer", "Sacré (soins)", {
			{ 1, 14524, "Wand Specialization", 1, 2 }, -- 10-11 : baguette +25 % (montée)
			{ 2, 14889, "Holy Specialization", 1, 5 }, -- 12-16 : critique sacré +5 %
			{ 2, 18530, "Divine Fury", 1, 5 }, -- 17-21 : Châtiment et Soins -0,5 s
			{ 2, 15237, "Holy Nova", 1, 1 }, -- 22 : Nova sacrée (zone)
			{ 2, 14913, "Twilight Focus", 1, 3 }, -- 23-25 : incantation non repoussée
			{ 2, 14908, "Improved Renew", 1, 1 }, -- 26
			{ 2, 14909, "Searing Light", 1, 2 }, -- 27-28 : dégâts sacrés +5 % (montée)
			{ 2, 14912, "Improved Healing", 1, 3 }, -- 29-31 : soins -15 % mana
			{ 2, 14901, "Spiritual Guidance", 1, 5 }, -- 32-36 : soins selon l'Esprit
			{ 2, 14898, "Spiritual Healing", 1, 3 }, -- 37-39 : soins +10 %
			{ 2, 20711, "Spirit of Redemption", 1, 1 }, -- 40 : prérequis probable de Prière de guérison
			{ 2, 1317006, "Litany of Light", 1, 1 }, -- 41 : mana en alternant les soins
			{ 2, 401859, "Prayer of Mending", 1, 1 }, -- 42 : Prière de guérison (rebonds)
			{ 2, 1317006, "Litany of Light", 2, 2 }, -- 43
			{ 2, 1328569, "Holy Binding", 1, 1 }, -- 44 : Soins rapides vous soignent aussi
			{ 1, 1225132, "Twin Disciplines", 1, 5 }, -- 45-49 : Rénovation et instantanés +5 %
			{ 1, 18551, "Mental Strength", 1, 3 }, -- 50-52 : Intelligence +6 %
			{ 1, 14521, "Meditation", 1, 3 }, -- 53-55 : 50 % de régén en incantant
			{ 2, 14892, "Inspiration", 1, 3 }, -- 56-58 : armure du tank sur soin critique
			{ 2, 14908, "Improved Renew", 2, 3 }, -- 59-60 : Rénovation +15 %
		}),
		healer_discipline = Plan("healer", "Discipline (soins, boucliers)", {
			{ 1, 14524, "Wand Specialization", 1, 2 }, -- 10-11 : baguette +25 % (montée)
			{ 1, 1309969, "Power in Light", 1, 5 }, -- 12-16 : Châtiment +10 % sous Douleur (montée)
			{ 1, 18551, "Mental Strength", 1, 3 }, -- 17-19 : Intelligence
			{ 1, 14520, "Mental Agility", 1, 3 }, -- 20-22 : Châtiment et instantanés -10 % mana
			{ 1, 14751, "Inner Focus", 1, 1 }, -- 23 : prérequis probable de Pénitence
			{ 1, 18551, "Mental Strength", 4, 5 }, -- 24-25 : prérequis possible d'Infusion de puissance
			{ 1, 402000, "Soul Warding", 1, 1 }, -- 26 : Bouclier -4 s de recharge, -15 % mana
			{ 1, 14521, "Meditation", 1, 3 }, -- 27-29 : 50 % de régén en incantant
			{ 1, 402174, "Penance", 1, 1 }, -- 30 : Pénitence (dégâts ou soins)
			{ 1, 425280, "Renewed Hope", 1, 5 }, -- 31-35 : critique sur cible sous Âme affaiblie
			{ 1, 431622, "Divine Aegis", 1, 3 }, -- 36-38 : bouclier sur soin critique
			{ 1, 14748, "Improved Power Word: Shield", 1, 1 }, -- 39
			{ 1, 10060, "Power Infusion", 1, 1 }, -- 40 : Infusion de puissance
			{ 1, 14748, "Improved Power Word: Shield", 2, 3 }, -- 41-42 : Bouclier +20 %
			{ 1, 1225132, "Twin Disciplines", 1, 5 }, -- 43-47 : instantanés +5 %
			{ 2, 14889, "Holy Specialization", 1, 5 }, -- 48-52 : critique des soins (Égide)
			{ 2, 18530, "Divine Fury", 1, 5 }, -- 53-57 : Soins et Soins supérieurs -0,5 s
			{ 2, 14913, "Twilight Focus", 1, 3 }, -- 58-60 : incantation non repoussée
		}),
	},
	SHAMAN = {
		melee = Plan("melee", "Amélioration (mêlée, montée de niveau)", {
			{ 2, 16255, "Thundering Strikes", 1, 5 }, -- 10-14 : critique +5 % (attaques et sorts)
			{ 2, 415140, "Mental Dexterity", 1, 3 }, -- 15-17 : PA = 100 % de l'Intelligence
			{ 2, 17485, "Ancestral Knowledge", 1, 2 }, -- 18-19 : Intelligence
			{ 2, 1223030, "Shamanistic Focus", 1, 1 }, -- 20 : horions et Bouclier de foudre -45 % de mana
			{ 2, 16266, "Elemental Weapons", 1, 3 }, -- 21-23 : enchantements d'arme renforcés
			{ 2, 17485, "Ancestral Knowledge", 3, 3 }, -- 24
			{ 2, 17364, "Stormstrike", 1, 1 }, -- 25 : Frappe-tempête
			{ 2, 16256, "Flurry", 1, 5 }, -- 26-30 : vitesse d'attaque après un critique
			{ 2, 30812, "Mental Quickness", 1, 2 }, -- 31-32 : puissance des sorts = 30 % de l'Intelligence
			{ 2, 16262, "Improved Ghost Wolf", 1, 2 }, -- 33-34 : Loup fantôme instantané, aussi en intérieur
			{ 2, 408498, "Maelstrom Weapon", 1, 5 }, -- 35-39 : Éclair instantané et gratuit à 5 charges
			{ 2, 425336, "Rage of the Farseer", 1, 1 }, -- 40 : vitesse d'attaque +30 % (25 s)
			{ 2, 1223031, "Improved Stormstrike", 1, 2 }, -- 41-42 : mana en incantant, Frappe-tempête relancée sur esquive/parade
			{ 3, 16179, "Tidal Focus", 1, 5 }, -- 43-47 : toucher +5 %
			{ 2, 17485, "Ancestral Knowledge", 4, 5 }, -- 48-49
			{ 2, 16268, "Spirit Weapons", 1, 1 }, -- 50 : parade, menace -30 % hors Croque-roc
			{ 1, 16035, "Concussion", 1, 5 }, -- 51-55 : Éclair et Horion de terre +5 %
			{ 1, 30160, "Elemental Devastation", 1, 3 }, -- 56-58 : critique en mêlée +9 % après un critique de sort
			{ 1, 16038, "Call of Flame", 1, 2 }, -- 59-60 : Horion de flammes, Nova de feu, totems de feu
		}),
		caster = Plan("caster", "Élémentaire (sorts)", {
			{ 1, 16039, "Convection", 1, 5 }, -- 10-14 : sorts de dégâts -10 % de mana
			{ 1, 16578, "Elemental Alacrity", 1, 3 }, -- 15-17 : Éclair et Chaîne d'éclairs -0,5 s
			{ 1, 16035, "Concussion", 1, 2 }, -- 18-19 : dégâts +2 %
			{ 1, 16164, "Elemental Focus", 1, 1 }, -- 20 : sort gratuit (Idées claires)
			{ 1, 16035, "Concussion", 3, 5 }, -- 21-23 : dégâts +5 % au total
			{ 1, 16038, "Call of Flame", 1, 1 }, -- 24 : Horion de flammes et totems de feu
			{ 1, 29062, "Eye of the Storm", 1, 3 }, -- 25-27 : pas de recul d'incantation (70 %)
			{ 1, 16038, "Call of Flame", 2, 3 }, -- 28-29
			{ 1, 16120, "Call of Thunder", 1, 1 }, -- 30 : critique de l'Éclair +5 %
			{ 1, 408438, "Lightning Overload", 1, 3 }, -- 31-33 : Éclair doublé (30 %)
			{ 1, 1222988, "Earthbound", 1, 1 }, -- 34 : Totem de lien terrestre immobilise 5 s
			{ 1, 16089, "Elemental Fury", 1, 5 }, -- 35-39 : dégâts critiques +100 %
			{ 1, 16166, "Lightning Mastery", 1, 1 }, -- 40 : Éclair plus rapide, Chaîne d'éclairs sans recharge
			{ 3, 16179, "Tidal Focus", 1, 5 }, -- 41-45 : toucher +5 %
			{ 3, 1223033, "Mindfulness", 1, 3 }, -- 46-48 : 50 % de la régénération de mana en incantant
			{ 2, 16255, "Thundering Strikes", 1, 5 }, -- 49-53 : critique +5 %
			{ 3, 29187, "Natural Grace", 1, 2 }, -- 54-55 : menace réduite
			{ 3, 408510, "Water Shield", 1, 1 }, -- 56 : Bouclier d'eau, mana sur les critiques
			{ 3, 29187, "Natural Grace", 3, 3 }, -- 57 : menace -15 %
			{ 1, 28999, "Elemental Reach", 1, 2 }, -- 58-59 : portée +6 m
			{ 2, 17485, "Ancestral Knowledge", 1, 1 }, -- 60 : Intelligence +2 %
		}),
		healer = Plan("healer", "Restauration (soins)", {
			{ 3, 16179, "Tidal Focus", 1, 5 }, -- 10-14 : soins -5 % de mana, toucher +5 %
			{ 3, 1223033, "Mindfulness", 1, 3 }, -- 15-17 : 50 % de la régénération de mana en incantant
			{ 3, 16182, "Improved Healing Wave", 1, 2 }, -- 18-19
			{ 3, 408510, "Water Shield", 1, 1 }, -- 20 : Bouclier d'eau, mana quand on est frappé
			{ 3, 16182, "Improved Healing Wave", 3, 5 }, -- 21-23 : Vague de soins -0,5 s
			{ 3, 16173, "Totemic Focus", 1, 1 }, -- 24 : totems moins chers
			{ 3, 16187, "Restorative Totems", 1, 5 }, -- 25-29 : Fontaine de mana et Totem guérisseur renforcés
			{ 3, 16188, "Nature's Swiftness", 1, 1 }, -- 30 : sort instantané d'urgence
			{ 3, 29206, "Healing Way", 1, 3 }, -- 31-33 : Vague de soins +25 %
			{ 3, 16190, "Mana Tide Totem", 1, 1 }, -- 34 : mana pour le groupe
			{ 3, 16178, "Purification", 1, 5 }, -- 35-39 : soins +10 %
			{ 3, 408521, "Riptide", 1, 1 }, -- 40 : Remous, soin sur la durée
			{ 3, 16194, "Tidal Mastery", 1, 5 }, -- 41-45 : critique des soins +5 %
			{ 3, 16173, "Totemic Focus", 2, 5 }, -- 46-49 : totems -25 % de mana
			{ 3, 16181, "Healing Focus", 1, 3 }, -- 50-52 : pas de recul d'incantation (70 %)
			{ 3, 16176, "Ancestral Healing", 1, 3 }, -- 53-55 : armure de la cible +25 % après un critique
			{ 2, 17485, "Ancestral Knowledge", 1, 5 }, -- 56-60 : Intelligence +10 %
		}),
	},
	MAGE = {
		caster = Plan("caster", "Givre (montée de niveau)", {
			{ 3, 11070, "Improved Frostbolt", 1, 5 }, -- 10-14 : Éclair de givre plus rapide
			{ 3, 11071, "Frostbite", 1, 3 }, -- 15-17 : gel aléatoire, contrôle en solo
			{ 3, 11165, "Improved Frost Nova", 1, 2 }, -- 18-19 : Nova de givre plus souvent
			{ 3, 1312002, "Ice Lance", 1, 1 }, -- 20 : Javelot de glace, x4 sur cible gelée
			{ 3, 11160, "Frost Channeling", 1, 3 }, -- 21-23 : -15 % de mana, moins de menace
			{ 3, 11207, "Ice Shards", 1, 1 }, -- 24 : critiques de givre plus forts
			{ 3, 11170, "Shatter", 1, 3 }, -- 25-27 : +50 % de critique sur cible gelée
			{ 3, 11207, "Ice Shards", 2, 3 }, -- 28-29 : suite
			{ 3, 400647, "Fingers of Frost", 1, 2 }, -- 30-31 : 2 sorts comme sur cible gelée
			{ 3, 11207, "Ice Shards", 4, 5 }, -- 32-33 : fin
			{ 3, 11958, "Ice Block", 1, 1 }, -- 34 : Bloc de glace, survie
			{ 3, 11190, "Improved Cone of Cold", 1, 3 }, -- 35-37 : Cône de froid +35 %
			{ 3, 12472, "Cold Snap", 1, 1 }, -- 38 : remet les sorts de givre à zéro
			{ 3, 29438, "Precision", 1, 1 }, -- 39 : toucher
			{ 3, 11426, "Ice Barrier", 1, 1 }, -- 40 : Barrière de glace, bouclier et +15 % givre
			{ 3, 11185, "Improved Blizzard", 1, 3 }, -- 41-43 : Blizzard ralentit, AoE
			{ 3, 29438, "Precision", 2, 3 }, -- 44-45 : +6 % de toucher au total
			{ 3, 11180, "Winter's Chill", 1, 5 }, -- 46-50 : les Éclairs de givre chargent le Cône de froid
			{ 1, 11237, "Improved Channeling", 1, 5 }, -- 51-55 : Projectiles des arcanes non repoussés
			{ 1, 400588, "Missile Barrage", 1, 2 }, -- 56-57 : Projectiles gratuits sur Éclair de givre
			{ 1, 11213, "Arcane Concentration", 1, 3 }, -- 58-60 : Idées claires, sort gratuit
		}),
		caster_feu = Plan("caster", "Feu", {
			{ 2, 11069, "Accelerant", 1, 5 }, -- 10-14 : Boule de feu plus rapide
			{ 2, 11119, "Ignite", 1, 5 }, -- 15-19 : brûlure sur critique de feu
			{ 2, 11366, "Pyroblast", 1, 1 }, -- 20 : Explosion pyrotechnique en ouverture
			{ 2, 11078, "Improved Fire Blast", 1, 2 }, -- 21-22 : Trait de feu plus souvent
			{ 2, 11083, "Burning Soul", 1, 2 }, -- 23-24 : incantation moins repoussée
			{ 2, 400624, "Heating Up", 1, 1 }, -- 25 : Trait de feu accélère le Pyro
			{ 2, 29074, "Master of Elements", 1, 3 }, -- 26-28 : mana rendu sur critique
			{ 2, 11083, "Burning Soul", 3, 3 }, -- 29 : fin
			{ 2, 11113, "Blast Wave", 1, 1 }, -- 30 : Vague explosive, AoE et hébétement
			{ 2, 11115, "Critical Mass", 1, 3 }, -- 31-33 : +6 % de critique de feu
			{ 2, 11103, "Impact", 1, 1 }, -- 34 : étourdissement aléatoire en solo
			{ 2, 11124, "Fire Power", 1, 3 }, -- 35-37 : +3 % par effet de feu, 12 % max
			{ 2, 11103, "Impact", 2, 3 }, -- 38-39 : fin
			{ 2, 11129, "Combustion", 1, 1 }, -- 40 : Combustion
			{ 2, 11095, "Improved Scorch", 1, 3 }, -- 41-43 : Brûlure, jusqu'à +15 % de dégâts de feu
			{ 2, 18459, "Incineration", 1, 4 }, -- 44-47 : critique de Trait de feu et Brûlure
			{ 3, 29438, "Precision", 1, 3 }, -- 48-50 : +6 % de toucher
			{ 1, 11237, "Improved Channeling", 1, 5 }, -- 51-55 : palier 1 des Arcanes
			{ 1, 400588, "Missile Barrage", 1, 2 }, -- 56-57 : Projectiles gratuits sur Boule de feu
			{ 1, 11213, "Arcane Concentration", 1, 3 }, -- 58-60 : Idées claires, sort gratuit
		}),
		caster_arcanes = Plan("caster", "Arcanes", {
			{ 1, 11237, "Improved Channeling", 1, 5 }, -- 10-14 : Projectiles des arcanes non repoussés
			{ 1, 400588, "Missile Barrage", 1, 2 }, -- 15-16 : Projectiles gratuits et rapides
			{ 1, 11213, "Arcane Concentration", 1, 3 }, -- 17-19 : Idées claires, sort gratuit
			{ 1, 400574, "Arcane Blast", 1, 1 }, -- 20 : Déflagration des arcanes
			{ 1, 11213, "Arcane Concentration", 4, 5 }, -- 21-22 : fin
			{ 1, 11242, "Arcane Impact", 1, 2 }, -- 23-24 : critique des arcanes
			{ 1, 1326079, "Arcane Wrath", 1, 1 }, -- 25 : gros sort, profite du mana max
			{ 1, 18462, "Arcane Meditation", 1, 3 }, -- 26-28 : 50 % de régén. en incantant
			{ 1, 11242, "Arcane Impact", 3, 3 }, -- 29 : fin
			{ 1, 12043, "Presence of Mind", 1, 1 }, -- 30 : Présence spirituelle
			{ 1, 11232, "Arcane Mind", 1, 5 }, -- 31-35 : +10 % d'Intelligence, critiques plus forts
			{ 1, 15058, "Arcane Instability", 1, 3 }, -- 36-38 : +3 % de dégâts et de critique
			{ 1, 11210, "Arcane Subtlety", 1, 1 }, -- 39 : résistances et menace réduites
			{ 1, 12042, "Arcane Power", 1, 1 }, -- 40 : Pouvoir des arcanes
			{ 2, 18459, "Incineration", 1, 5 }, -- 41-45 : +10 % de critique de Déflagration
			{ 3, 29438, "Precision", 1, 3 }, -- 46-48 : +6 % de toucher
			{ 2, 11069, "Accelerant", 1, 5 }, -- 49-53 : Arcane Wrath plus rapide
			{ 1, 11210, "Arcane Subtlety", 2, 2 }, -- 54 : fin
			{ 1, 28574, "Arcane Resilience", 1, 3 }, -- 55-57 : armure selon l'Intelligence
			{ 1, 11247, "Arcane Geometry", 1, 2 }, -- 58-59 : portée des arcanes
			{ 1, 29441, "Magic Absorption", 1, 1 }, -- 60 : résistances
		}),
	},
	WARLOCK = {
		caster = Plan("caster", "Affliction (montée de niveau)", {
			{ 1, 17810, "Improved Corruption", 1, 5 }, -- 10-14 : Corruption instantanée, +10 % dégâts
			{ 1, 403511, "Improved Drains", 1, 3 }, -- 15-17 : Drain de vie +20 %
			{ 1, 18182, "Improved Life Tap", 1, 2 }, -- 18-19 : Connexion +20 % mana
			{ 1, 17783, "Fel Concentration", 1, 3 }, -- 20-22 : drains non interrompus par les coups
			{ 1, 18827, "Improved Bane of Agony", 1, 2 }, -- 23-24
			{ 1, 18094, "Nightfall", 1, 2 }, -- 25-26 : Trait de l'ombre instantané (proc)
			{ 1, 1310949, "Malevolence", 1, 3 }, -- 27-29 : critique Ombre
			{ 1, 18265, "Siphon Life", 1, 1 }, -- 30 : 3e DoT, soin
			{ 1, 17804, "Soul Siphon", 1, 3 }, -- 31-33 : drains +12 % par DoT
			{ 1, 1310949, "Malevolence", 4, 4 }, -- 34
			{ 1, 18271, "Shadow Mastery", 1, 5 }, -- 35-39 : +10 % Ombre
			{ 1, 1316697, "Wrack", 1, 1 }, -- 40 : canalisation, DoT 2x plus rapides
			{ 1, 1310949, "Malevolence", 5, 5 }, -- 41
			{ 1, 427712, "Pandemic", 1, 3 }, -- 42-44 : critiques des DoT doublés
			{ 2, 18697, "Demonic Embrace", 1, 5 }, -- 45-49 : +15 % Endurance
			{ 2, 18731, "Fel Vitality", 1, 3 }, -- 50-52 : +15 % mana, démon plus solide
			{ 2, 1225214, "Demonic Energies", 1, 2 }, -- 53-54 : soigne le démon
			{ 2, 18788, "Demonic Sacrifice", 1, 1 }, -- 55 : diablotin sacrifié = +15 % Ombre (raid)
			{ 1, 18174, "Suppression", 1, 5 }, -- 56-60 : +5 % toucher, -20 % menace
		}),
		caster_demonologie = Plan("caster", "Démonologie", {
			{ 2, 18697, "Demonic Embrace", 1, 5 }, -- 10-14 : +15 % Endurance
			{ 2, 18731, "Fel Vitality", 1, 3 }, -- 15-17 : +15 % mana, démon plus solide
			{ 2, 1225214, "Demonic Energies", 1, 2 }, -- 18-19 : soigne le démon, mana partagé
			{ 2, 18709, "Master Summoner", 1, 2 }, -- 20-21 : invocation rapide et moins chère
			{ 2, 18769, "Unholy Power", 1, 3 }, -- 22-24 : dégâts du démon
			{ 2, 1293695, "Demonic Brand", 1, 3 }, -- 25-27 : Douleur brûlante = attaques du démon renforcées
			{ 2, 18769, "Unholy Power", 4, 5 }, -- 28-29
			{ 2, 18788, "Demonic Sacrifice", 1, 1 }, -- 30 : requis pour Lien spirituel et Pacte
			{ 2, 19028, "Soul Link", 1, 1 }, -- 31 : 30 % des dégâts au démon, +3 % dégâts
			{ 2, 412732, "Demonic Knowledge", 1, 3 }, -- 32-34 : puissance des sorts = niveau
			{ 2, 23785, "Master Demonologist", 1, 5 }, -- 35-39 : bonus selon le démon
			{ 2, 425464, "Demonic Pact", 1, 1 }, -- 40 : sacrifice gardé avec un autre démon
			{ 3, 17788, "Bane", 1, 5 }, -- 41-45 : Trait de l'ombre plus rapide
			{ 3, 17793, "Improved Shadow Bolt", 1, 5 }, -- 46-50 : critique = +20 % Ombre subie
			{ 2, 440870, "Decimation", 1, 2 }, -- 51-52 : Feu de l'âme en exécution
			{ 3, 17959, "Ruin", 1, 5 }, -- 53-57 : critiques Destruction renforcés
			{ 3, 17927, "Agonizing Flames", 1, 3 }, -- 58-60 : +10 % dégâts Destruction
		}),
		caster_destruction = Plan("caster", "Destruction", {
			{ 3, 17788, "Bane", 1, 5 }, -- 10-14 : Trait de l'ombre et Immolation plus rapides
			{ 3, 18119, "Aftermath", 1, 5 }, -- 15-19 : Immolation +50 % (avant Conflagration)
			{ 3, 17877, "Shadowburn", 1, 1 }, -- 20 : instantané, rend un fragment
			{ 3, 1225220, "Molten Skin", 1, 4 }, -- 21-24 : -10 % dégâts subis au max
			{ 3, 1293817, "Conflagrate", 1, 1 }, -- 25 : explosion sur Immolation
			{ 3, 17927, "Agonizing Flames", 1, 3 }, -- 26-28 : +10 % dégâts Destruction
			{ 3, 1225220, "Molten Skin", 5, 5 }, -- 29
			{ 3, 412751, "Fire and Brimstone", 1, 3 }, -- 30-32 : critique de Conflagration
			{ 3, 17778, "Cataclysm", 1, 2 }, -- 33-34 : coût en mana
			{ 3, 426316, "Shadow and Flame", 1, 5 }, -- 35-39 : +20 % Ombre/Feu, Immolation conservée
			{ 3, 412758, "Incinerate", 1, 1 }, -- 40 : sort principal Feu
			{ 3, 17778, "Cataclysm", 3, 3 }, -- 41
			{ 3, 17959, "Ruin", 1, 5 }, -- 42-46 : critiques Destruction renforcés
			{ 3, 17793, "Improved Shadow Bolt", 1, 5 }, -- 47-51 : critique = +20 % Ombre subie
			{ 3, 18135, "Intensity", 1, 3 }, -- 52-54 : sorts non interrompus par les coups
			{ 3, 1225228, "Bane of Havoc", 1, 1 }, -- 55 : dégâts partagés sur 2 cibles
			{ 1, 18174, "Suppression", 1, 5 }, -- 56-60 : +5 % toucher, -20 % menace
		}),
	},
	DRUID = {
		caster = Plan("caster", "Équilibre (sorts)", {
			{ 1, 16814, "Improved Wrath", 1, 5 }, -- 10-14 : Colère plus rapide, moitié prix
			{ 1, 16821, "Improved Moonfire", 1, 2 }, -- 15-16 : Éclat lunaire
			{ 1, 16845, "Moonglow", 1, 3 }, -- 17-19 : mana des sorts offensifs
			{ 1, 1223083, "Nature's Splendor", 1, 1 }, -- 20 : DoT et HoT plus longs
			{ 1, 1223082, "Nature's Majesty", 1, 2 }, -- 21-22 : +4 % critique
			{ 1, 1223081, "Genesis", 1, 2 }, -- 23-24 : effets périodiques
			{ 1, 5570, "Insect Swarm", 1, 1 }, -- 25 : 2e DoT
			{ 1, 16909, "Vengeance", 1, 5 }, -- 26-30 : critiques plus forts
			{ 1, 16880, "Nature's Grace", 1, 1 }, -- 31 : hâte après un critique
			{ 1, 16850, "Improved Starfire", 1, 3 }, -- 32-34
			{ 1, 16896, "Moonfury", 1, 5 }, -- 35-39 : +10 % dégâts
			{ 1, 24858, "Moonkin Form", 1, 1 }, -- 40 : forme de sélénien
			{ 1, 16850, "Improved Starfire", 4, 5 }, -- 41-42
			{ 1, 408248, "Eclipse", 1, 3 }, -- 43-45 : Colère accélère Feu stellaire
			{ 1, 16819, "Nature's Reach", 1, 2 }, -- 46-47 : +4 % toucher, portée
			{ 3, 17003, "Heart of the Wild", 1, 5 }, -- 48-52 : +10 % Intelligence
			{ 3, 17069, "Naturalist", 1, 5 }, -- 53-57 : +10 % dégâts
			{ 1, 1223081, "Genesis", 3, 5 }, -- 58-60
		}),
		tank = Plan("tank", "Combat farouche (ours, tank)", {
			{ 2, 16934, "Ferocity", 1, 5 }, -- 10-14 : Mutiler et Balayage moins chers
			{ 2, 17056, "Furor", 1, 5 }, -- 15-19 : 10 rage à l'entrée en ours
			{ 2, 16942, "Sharpened Claws", 1, 2 }, -- 20-21 : +6 % critique
			{ 2, 16998, "Savage Fury", 1, 2 }, -- 22-23 : +10 % dégâts des techniques
			{ 2, 1238122, "Feral Charge", 1, 1 }, -- 24 : charge, interruption
			{ 2, 1328617, "Lacerate", 1, 1 }, -- 25 : saignement, grosse menace
			{ 2, 16972, "Predatory Strikes", 1, 3 }, -- 26-28 : puissance d'attaque
			{ 2, 16947, "Feral Instinct", 1, 1 }, -- 29 : Balayage
			{ 2, 17007, "Leader of the Pack", 1, 1 }, -- 30 : +3 % critique au groupe
			{ 2, 16958, "Blood Frenzy", 1, 2 }, -- 31-32 : rage sur critique
			{ 2, 1223242, "Natural Instinct", 1, 2 }, -- 33-34 : critiques plus forts
			{ 2, 1223246, "Rend and Tear", 1, 5 }, -- 35-39 : +15 % sur cible qui saigne
			{ 2, 417051, "Natural Reaction", 1, 5 }, -- 40-44 : +5 % esquive, rage
			{ 2, 407995, "Primal Bite", 1, 1 }, -- 45 : morsure à forte menace
			{ 3, 17003, "Heart of the Wild", 1, 5 }, -- 46-50 : +20 % Endurance en ours
			{ 2, 16947, "Feral Instinct", 2, 3 }, -- 51-52 : menace de zone
			{ 3, 17069, "Naturalist", 1, 5 }, -- 53-57 : +10 % dégâts
			{ 2, 16929, "Thick Hide", 1, 3 }, -- 58-60 : armure
		}),
		melee = Plan("melee", "Combat farouche (félin, montée de niveau)", {
			{ 2, 16934, "Ferocity", 1, 5 }, -- 10-14 : Griffe et Griffure moins chères
			{ 2, 17056, "Furor", 1, 5 }, -- 15-19 : rage en ours, énergie gardée en félin
			{ 2, 17002, "Feral Swiftness", 1, 2 }, -- 20-21 : vitesse en félin, esquive
			{ 2, 16942, "Sharpened Claws", 1, 2 }, -- 22-23 : +6 % critique
			{ 2, 16998, "Savage Fury", 1, 2 }, -- 24-25 : +10 % dégâts des techniques
			{ 2, 16972, "Predatory Strikes", 1, 3 }, -- 26-28 : puissance d'attaque
			{ 2, 1328613, "Predatory Discipline", 1, 1 }, -- 29 : Morsure féroce économe
			{ 2, 17007, "Leader of the Pack", 1, 1 }, -- 30 : +3 % critique au groupe
			{ 2, 16958, "Blood Frenzy", 1, 2 }, -- 31-32 : point de combo en plus sur critique
			{ 2, 1223242, "Natural Instinct", 1, 2 }, -- 33-34 : critiques plus forts
			{ 2, 1223246, "Rend and Tear", 1, 5 }, -- 35-39 : +15 % sur cible qui saigne
			{ 2, 417051, "Natural Reaction", 1, 5 }, -- 40-44 : +5 % esquive
			{ 2, 1322605, "Shifting Power", 1, 1 }, -- 45 : mana converti en énergie
			{ 3, 17003, "Heart of the Wild", 1, 5 }, -- 46-50 : +10 % Force en félin
			{ 3, 17069, "Naturalist", 1, 5 }, -- 51-55 : +10 % dégâts
			{ 2, 16966, "Shredding Attacks", 1, 3 }, -- 56-58 : Lambeau moins cher
			{ 2, 1238122, "Feral Charge", 1, 1 }, -- 59 : bond derrière la cible
			{ 2, 407995, "Primal Bite", 1, 1 }, -- 60 : pour tanker en ours au besoin
		}),
		healer = Plan("healer", "Restauration (soins)", {
			{ 3, 17003, "Heart of the Wild", 1, 5 }, -- 10-14 : +10 % Intelligence
			{ 3, 17069, "Naturalist", 1, 5 }, -- 15-19 : +10 % dégâts, Toucher guérisseur plus rapide
			{ 3, 1328621, "Bloom", 1, 1 }, -- 20 : soin à la fin des HoT
			{ 3, 17106, "Reflection", 1, 3 }, -- 21-23 : mana pendant l'incantation
			{ 3, 17104, "Gift of Nature", 1, 5 }, -- 24-28 : +10 % soins
			{ 3, 17111, "Improved Rejuvenation", 1, 3 }, -- 29-31
			{ 3, 18562, "Swiftmend", 1, 1 }, -- 32 : soin instantané
			{ 3, 17116, "Nature's Swiftness", 1, 1 }, -- 33 : sort instantané
			{ 3, 1309631, "Living Spirit", 1, 1 }, -- 34
			{ 3, 17074, "Improved Regrowth", 1, 5 }, -- 35-39 : critiques de Rétablissement
			{ 3, 408120, "Wild Growth", 1, 1 }, -- 40 : soin de groupe
			{ 1, 1223081, "Genesis", 1, 5 }, -- 41-45 : +10 % soins périodiques
			{ 1, 1223082, "Nature's Majesty", 1, 2 }, -- 46-47 : +4 % critique
			{ 1, 16821, "Improved Moonfire", 1, 2 }, -- 48-49 : accès au palier 3
			{ 1, 16814, "Improved Wrath", 1, 1 }, -- 50
			{ 1, 1223083, "Nature's Splendor", 1, 1 }, -- 51 : Récupération et Rétablissement plus longs
			{ 3, 1309631, "Living Spirit", 2, 3 }, -- 52-53 : +15 % Esprit
			{ 3, 24968, "Tranquil Spirit", 1, 5 }, -- 54-58 : Toucher guérisseur moins cher
			{ 3, 17123, "Improved Tranquility", 1, 2 }, -- 59-60 : Tranquillité plus souvent
		}),
	},
}
Auto.PLANS = PLANS

local function PlayerClass()
	local _, token = Call(UnitClass, "player")
	return type(token) == "string" and token or "?"
end

-- Le plan suivi : celui choisi dans les réglages, sinon celui de ton rôle (comme la fenêtre Équipement).
function Auto.Plan()
	local plans = PLANS[PlayerClass()]
	if not plans then
		return nil
	end
	local choice = Cfg().talentPlan
	if choice and choice ~= "auto" and plans[choice] then
		return plans[choice], choice
	end
	local role = ns.Gear and ns.Gear.Role and ns.Gear.Role() or nil
	if role and plans[role] then
		return plans[role], role
	end
	local keys = SortedKeys(plans)
	for _, key in ipairs(keys) do
		if plans[key].role == role then
			return plans[key], key
		end
	end
	return plans[keys[1]], keys[1]
end

-- Les plans de ta classe : { { key, label }, … }.
function Auto.PlanChoices()
	local out = {}
	local plans = PLANS[PlayerClass()] or {}
	for _, key in ipairs(SortedKeys(plans)) do
		out[#out + 1] = { key = key, label = plans[key].label, role = plans[key].role }
	end
	return out
end

local function Lower(s)
	return type(s) == "string" and s:lower() or nil
end

local function SpellName(id)
	if C_Spell and C_Spell.GetSpellName then
		local n = Call(C_Spell.GetSpellName, id)
		if type(n) == "string" and n ~= "" then
			return n
		end
	end
	if C_Spell and C_Spell.GetSpellInfo then
		local info = Call(C_Spell.GetSpellInfo, id)
		if type(info) == "table" and type(info.name) == "string" then
			return info.name
		end
	end
	local n = Call(rawget(_G, "GetSpellInfo"), id)
	return type(n) == "string" and n or nil
end

-------------------------------------------------------------------------------
-- Lecture des talents
--   Forever : arbre « à la Retail » (C_Traits) : une config (C_ClassTalents.GetActiveConfigID) d'un seul arbre, dont
--   les trois onglets sont des groupes (C_Traits.GetGroupDisplayInfoByTreeID). Un point se PRÉPARE
--   (C_Traits.PurchaseRank) puis s'APPLIQUE (CommitConfig : une courte incantation, il faut rester immobile).
--   Secours : l'API Classic (GetTalentInfo / LearnTalent), si le jeu l'a.
-- Format commun : trees[onglet] = { name, points, talents = { [clé] = t }, byName, bySpell }, trees.free,
--   trees.mode (« traits » ou « classic »), trees.configID ; t = { key, name, spell, rank, max, can, tab }.
-------------------------------------------------------------------------------
local function TraitIDs()
	if not (C_ClassTalents and C_Traits and type(C_ClassTalents.GetActiveConfigID) == "function"
		and type(C_Traits.GetTreeNodes) == "function") then
		return nil
	end
	local configID = Num(Call(C_ClassTalents.GetActiveConfigID))
	local info = configID and Call(C_Traits.GetConfigInfo, configID)
	local treeID = type(info) == "table" and type(info.treeIDs) == "table" and Num(info.treeIDs[1]) or nil
	if not treeID then
		return nil
	end
	return configID, treeID
end

local function TraitTrees(configID, treeID)
	local groups = {}
	for _, g in ipairs(Call(C_Traits.GetGroupDisplayInfoByTreeID, treeID) or {}) do
		if type(g) == "table" and Num(g.groupID) then
			groups[#groups + 1] = g
		end
	end
	table.sort(groups, function(a, b)
		return (Num(a.orderIndex) or 0) < (Num(b.orderIndex) or 0)
	end)
	local trees, byGroup, ids = { mode = "traits", configID = configID, treeID = treeID }, {}, {}
	for tab, g in ipairs(groups) do
		trees[tab] = { name = g.displayName, groupID = g.groupID, points = 0, talents = {}, byName = {}, bySpell = {} }
		byGroup[g.groupID] = tab
		ids[#ids + 1] = g.groupID
	end
	-- (un onglet sans point manque dans la réponse : 0)
	for _, e in ipairs(Call(C_Traits.GetGroupCurrencyInfo, configID, ids) or {}) do
		local tab = type(e) == "table" and byGroup[e.traitNodeGroupID]
		local c = tab and type(e.currencyInfos) == "table" and e.currencyInfos[1]
		if c then
			trees[tab].points = Num(c.spent) or 0
		end
	end
	for _, nodeID in ipairs(Call(C_Traits.GetTreeNodes, treeID) or {}) do
		local n = Call(C_Traits.GetNodeInfo, configID, nodeID)
		local tab
		for _, g in ipairs(type(n) == "table" and type(n.groupIDs) == "table" and n.groupIDs or {}) do
			tab = tab or byGroup[g]
		end
		if tab and n.isVisible ~= false then
			local entryID = type(n.activeEntry) == "table" and n.activeEntry.entryID
				or type(n.entryIDs) == "table" and n.entryIDs[1] or nil
			local entry = entryID and Call(C_Traits.GetEntryInfo, configID, entryID)
			local def = type(entry) == "table" and entry.definitionID and Call(C_Traits.GetDefinitionInfo, entry.definitionID)
			local spell = type(def) == "table" and Num(def.spellID) or nil
			local name = type(def) == "table" and type(def.overrideName) == "string" and def.overrideName ~= "" and def.overrideName
				or (spell and SpellName(spell))
			local t = { key = nodeID, tab = tab, name = name, spell = spell, rank = Num(n.currentRank) or 0,
				max = Num(n.maxRanks) or 1, can = n.canPurchaseRank == true }
			local tree = trees[tab]
			tree.talents[nodeID] = t
			if spell then
				tree.bySpell[spell] = nodeID
			end
			if name then
				tree.byName[Lower(name)] = nodeID
			end
		end
	end
	local currency = Call(C_Traits.GetTreeCurrencyInfo, configID, treeID, false)
	local c = type(currency) == "table" and currency[1]
	trees.free = type(c) == "table" and Num(c.quantity) or 0
	return trees
end

-- Un talent Classic : nom, palier, rang, rang max, prérequis remplis.
local function TalentInfo(tab, index)
	local name, icon, tier, _, rank, maxRank, _, available = Call(GetTalentInfo, tab, index)
	if type(name) ~= "string" then
		return nil
	end
	return { key = index, tab = tab, name = name, icon = icon, tier = Num(tier) or 1, rank = Num(rank) or 0,
		max = Num(maxRank) or 1, available = available ~= false }
end

local function ClassicTrees()
	if type(GetTalentInfo) ~= "function" or type(GetNumTalents) ~= "function" then
		return nil
	end
	local trees = { mode = "classic" }
	local spent = 0
	for tab = 1, Num(Call(GetNumTalentTabs)) or 3 do
		local tree = { points = 0, talents = {}, byName = {}, bySpell = {} }
		local tabName = Call(GetTalentTabInfo, tab)
		tree.name = type(tabName) == "string" and tabName or nil
		for index = 1, Num(Call(GetNumTalents, tab)) or 0 do
			local t = TalentInfo(tab, index)
			if t then
				tree.talents[index] = t
				tree.points = tree.points + t.rank
				tree.byName[Lower(t.name)] = index
			end
		end
		spent = spent + tree.points
		trees[tab] = tree
	end
	trees.free = Num(Call(UnitCharacterPoints, "player")) or math.max(0, Level() - 9 - spent)
	for _, tree in ipairs(trees) do
		for _, t in pairs(tree.talents) do
			t.can = t.rank < t.max and t.available and tree.points >= ((t.tier - 1) * 5) and trees.free > 0
		end
	end
	return trees
end

function Auto.Trees()
	local configID, treeID = TraitIDs()
	if configID then
		return TraitTrees(configID, treeID)
	end
	return ClassicTrees()
end

-- Points dépensés par onglet (pour deviner le rôle) : { { name, points }, … } ou nil.
-- (appelé à chaque bulle d'objet : seulement les points par onglet, gardés 2 secondes)
local pointsCache, pointsAt = nil, -10
function Auto.TreePoints()
	if pointsCache and GetTime() - pointsAt < 2 then
		return pointsCache
	end
	local out
	local configID, treeID = TraitIDs()
	if configID then
		local groups, ids, byGroup = {}, {}, {}
		for _, g in ipairs(Call(C_Traits.GetGroupDisplayInfoByTreeID, treeID) or {}) do
			if type(g) == "table" and Num(g.groupID) then
				groups[#groups + 1] = g
			end
		end
		table.sort(groups, function(a, b)
			return (Num(a.orderIndex) or 0) < (Num(b.orderIndex) or 0)
		end)
		out = {}
		for tab, g in ipairs(groups) do
			out[tab] = { name = g.displayName, points = 0 }
			byGroup[g.groupID] = tab
			ids[#ids + 1] = g.groupID
		end
		for _, e in ipairs(Call(C_Traits.GetGroupCurrencyInfo, configID, ids) or {}) do
			local tab = type(e) == "table" and byGroup[e.traitNodeGroupID]
			local c = tab and type(e.currencyInfos) == "table" and e.currencyInfos[1]
			if c then
				out[tab].points = Num(c.spent) or 0
			end
		end
	else
		local trees = ClassicTrees()
		if trees then
			out = {}
			for tab, t in ipairs(trees) do
				out[tab] = { name = t.name, points = t.points }
			end
		end
	end
	pointsCache, pointsAt = out, GetTime()
	return out
end

-- Où est le talent d'un pas du plan : onglet et clé (par son sort, puis le nom de son sort, puis son nom anglais).
local function Resolve(trees, step)
	for tab, t in ipairs(trees) do
		if t.bySpell[step.spell] then
			return tab, t.bySpell[step.spell]
		end
	end
	for _, name in ipairs({ Lower(SpellName(step.spell)), Lower(step.en) }) do
		if name then
			local tree = trees[step.tab]
			if tree and tree.byName[name] then
				return step.tab, tree.byName[name]
			end
			for tab, t in ipairs(trees) do
				if t.byName[name] then
					return tab, t.byName[name]
				end
			end
		end
	end
	return nil
end

local skippedSteps = {} -- [n° du pas] = raison (talent introuvable, refusé par le jeu) : cette session
local snoozedAt -- « Plus tard » : plus de question avant le prochain niveau

-- Le prochain point du plan : { tab, key, name, rank, max, step, plan } ou nil, raison.
-- `extra` = rangs déjà préparés par nous que le jeu ne montre pas encore : { [clé] = n, total = n }.
function Auto.NextTalent(extra)
	extra = extra or { total = 0 }
	local plan = Auto.Plan()
	if not plan then
		return nil, "pas de plan pour ta classe (pour l'instant : guerrier)"
	end
	local trees = Auto.Trees()
	if not trees then
		return nil, "talents illisibles"
	end
	if trees.free - extra.total <= 0 then
		return nil, "aucun point à mettre", plan
	end
	for i, step in ipairs(plan.steps) do
		if not skippedSteps[i] then
			local tab, key = Resolve(trees, step)
			if not tab then
				skippedSteps[i] = "introuvable"
				if step.rank == 1 or not skippedSteps[i - 1] then
					Note("talent introuvable : " .. step.en)
				end
			else
				local t = trees[tab].talents[key]
				local rank = t.rank + (extra[key] or 0)
				if rank < step.rank and rank < t.max and t.can then
					return { tab = tab, key = key, name = t.name or step.en, rank = rank + 1, max = t.max, step = i, plan = plan,
						mode = trees.mode, configID = trees.configID }
				end
			end
		end
	end
	return nil, "plan terminé (ou rien de possible pour l'instant)", plan
end

-------------------------------------------------------------------------------
-- Apprendre
-------------------------------------------------------------------------------
local learning -- Classic : { tab, key, rank, at, name, step } ; Forever : { configID, at, names }
local ourStaged -- Forever : des rangs préparés par nous et pas encore appliqués
local waitStill, waitAccepted -- un point à mettre dès que tu ne bouges plus (Forever : l'incantation demande l'immobilité)

local function Moving()
	local speed = Num(Call(GetUnitSpeed, "player")) or 0
	return speed > 0 or (IsFalling and Call(IsFalling)) or false
end

local function LearnClassic(nextT, why)
	local before = nextT.rank - 1
	learning = { tab = nextT.tab, key = nextT.key, rank = nextT.rank, at = GetTime(), name = nextT.name, step = nextT.step }
	if not pcall(LearnTalent, nextT.tab, nextT.key) then
		skippedSteps[nextT.step] = "refusé"
		learning = nil
		return false
	end
	Note("talent " .. tostring(nextT.name) .. " " .. nextT.rank .. "/" .. nextT.max .. (why and (" (" .. why .. ")") or ""))
	C_Timer.After(1.5, function()
		local l = learning
		if l and l.tab and GetTime() - l.at >= 1.4 then
			local t = TalentInfo(l.tab, l.key)
			if t and t.rank <= before then
				skippedSteps[l.step] = "refusé par le jeu"
				Note("talent refusé par le jeu : " .. tostring(l.name))
				ns.Print("talents : le jeu n'a pas pris « " .. tostring(l.name) .. " » ; je passe au suivant du plan.")
			end
			learning = nil
		end
	end)
	ns.Print("talent appris : |cff00ff00" .. tostring(nextT.name) .. "|r (rang " .. nextT.rank .. "/" .. nextT.max .. ")")
	return true
end

local function NodeRank(configID, nodeID)
	local n = Call(C_Traits.GetNodeInfo, configID, nodeID)
	return type(n) == "table" and Num(n.currentRank) or 0
end

local function Commit(configID)
	if C_ClassTalents and C_ClassTalents.CommitConfig then
		local ok, res = pcall(C_ClassTalents.CommitConfig)
		if ok and res ~= false then
			return true
		end
	end
	if C_Traits.CommitConfig then
		local ok, res = pcall(C_Traits.CommitConfig, configID)
		return ok and res ~= false
	end
	return false
end

-- Forever : prépare tous les points libres du plan, puis les applique en une fois (une seule incantation).
local function LearnTraits(why)
	local configID = TraitIDs()
	if not configID then
		return false
	end
	if Call(C_Traits.ConfigHasStagedChanges, configID) then
		if not ourStaged then
			Note("talents : changements en cours dans la fenêtre des talents, je n'y touche pas")
			return false
		end
		Call(C_Traits.RollbackConfig, configID) -- (les nôtres, restés d'une incantation interrompue)
	end
	local extra, names = { total = 0 }, {}
	for _ = 1, 51 do
		local nextT = Auto.NextTalent(extra)
		if not nextT then
			break
		end
		local before = NodeRank(configID, nextT.key)
		local ok, res = pcall(C_Traits.PurchaseRank, configID, nextT.key)
		if not ok or res == false then
			if #names == 0 then -- (après d'autres points : sans doute plus de point libre, pas un refus)
				skippedSteps[nextT.step] = "refusé"
				Note("talent refusé : " .. tostring(nextT.name))
			end
			break
		end
		ourStaged = true
		if NodeRank(configID, nextT.key) <= before then
			-- (le jeu ne montre pas encore le rang préparé : on le compte nous-mêmes)
			extra[nextT.key] = (extra[nextT.key] or 0) + 1
			extra.total = extra.total + 1
		end
		names[#names + 1] = tostring(nextT.name) .. " " .. nextT.rank .. "/" .. nextT.max
	end
	if #names == 0 then
		return false
	end
	learning = { configID = configID, at = GetTime(), names = names }
	if not Commit(configID) then
		Call(C_Traits.RollbackConfig, configID)
		learning, ourStaged = nil, nil
		Note("talents : le jeu refuse d'appliquer (" .. table.concat(names, ", ") .. ")")
		return false
	end
	Note("talents appliqués : " .. table.concat(names, ", ") .. (why and (" (" .. why .. ")") or ""))
	ns.Print("talents : |cff00ff00" .. table.concat(names, ", ") .. "|r — reste immobile quelques secondes, le jeu les apprend.")
	return true
end

-- Le jeu a appliqué (ou refusé) nos talents.
function Auto.OnTraitsCommitted(configID, failed)
	local l = learning
	if not (l and l.configID) or (Num(configID) and Num(configID) ~= l.configID) then
		return
	end
	learning = nil
	if not failed then
		ourStaged = nil
	end
	if failed then
		Call(C_Traits.RollbackConfig, l.configID)
		ourStaged = nil
		waitStill, waitAccepted = true, true
		Note("talents pas appliqués (incantation interrompue) : nouvel essai quand tu ne bouges plus")
		ns.Print("talents : pas appris (tu as bougé ou été attaqué ?). Je réessaie dès que tu es immobile.")
	end
end

local function Learn(why)
	if InCombat() then
		Auto.pending = true
		return false
	end
	local nextT = Auto.NextTalent()
	if not nextT then
		return false
	end
	if nextT.mode == "traits" then
		if Moving() then
			waitStill = true -- (l'incantation serait interrompue : dès que tu t'arrêtes)
			return false
		end
		return LearnTraits(why)
	end
	return LearnClassic(nextT, why)
end

-- Regarde s'il y a un point à mettre ; le met (mode automatique) ou le propose (mode « demander »).
function Auto.CheckTalents(reason)
	local cfg = Cfg()
	if learning and GetTime() - (learning.at or 0) > 15 then
		learning = nil -- (le jeu n'a rien répondu : on reprend)
	end
	if cfg.talents == "non" or not Allowed("talents") or learning then
		return
	end
	if InCombat() then
		Auto.pending = true
		return
	end
	local nextT = Auto.NextTalent()
	if not nextT then
		return
	end
	if cfg.talents == "auto" or reason == "accepté" then
		Learn(reason)
		return
	end
	if snoozedAt and snoozedAt >= Level() and reason ~= "demande" then
		return
	end
	if Auto.Asking("talent") then
		return
	end
	local trees = Auto.Trees()
	local free = trees and trees.free or 1
	local tabName = trees and trees[nextT.tab] and trees[nextT.tab].name or ("arbre " .. nextT.tab)
	Auto.Ask("talent", string.format("Talent à mettre (%d point%s libre%s) :\n|cffffd200%s|r rang %d/%d (%s)\n|cff888888Plan : %s (autre plan : /iti reglages > Pilote)|r%s",
		free, free > 1 and "s" or "", free > 1 and "s" or "", tostring(nextT.name), nextT.rank, nextT.max, tostring(tabName),
		nextT.plan.label, nextT.mode == "traits" and "\n|cff888888Reste immobile quelques secondes après avoir accepté.|r" or ""), {
		{ label = "Apprendre", func = function()
			if not Learn("accepté") and waitStill then
				waitAccepted = true
				ns.Print("talents : arrête-toi une seconde, je les apprends dès que tu es immobile.")
			end
		end },
		{ label = "Plus tard", func = function()
			snoozedAt = Level()
			ns.Print("talents : je redemande au prochain niveau (ou /iti talents).")
		end },
		{ label = "Toujours", func = function()
			cfg.talents = "auto"
			ns.Print("talents : |cff00ff00automatiques|r (réglage : /iti reglages > Pilote).")
			if not Learn("accepté") and waitStill then
				waitAccepted = true
			end
		end },
	})
end

-- Attente d'immobilité (Forever) : un coup d'œil toutes les demi-secondes, seulement quand il y a un point en attente.
local stillSince
local watcher = CreateFrame("Frame")
local acc = 0
watcher:SetScript("OnUpdate", function(_, elapsed)
	acc = acc + (elapsed or 0)
	if acc < 0.5 or not waitStill then
		return
	end
	acc = 0
	if InCombat() or Moving() then
		stillSince = nil
		return
	end
	stillSince = stillSince or GetTime()
	if GetTime() - stillSince >= 1 then
		waitStill, stillSince = nil, nil
		local accepted = waitAccepted
		waitAccepted = nil
		local ok, err = pcall(Auto.CheckTalents, accepted and "accepté" or "immobile")
		if not ok and ns.OnError then
			ns.OnError("pilote (talents) : " .. tostring(err))
		end
	end
end)

-------------------------------------------------------------------------------
-- Équipement : mettre ce qui t'améliore
-------------------------------------------------------------------------------
local MIN_GAIN = 2 -- points de note
local MIN_PCT = 3 -- et au moins 3 % de mieux (sauf emplacement vide)
local refused = {} -- [itemID] = true : remis à la main ou refusé (cette session)
local lastAuto = {} -- [emplacement] = { id, at }
local equipAt = 0
local pendingBind -- { at } : objet lié quand équipé accepté par le joueur

local function ContainerItem(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		local info = Call(C_Container.GetContainerItemInfo, bag, slot)
		if type(info) == "table" then
			return info.hyperlink, info.itemID, info.isBound, info.isLocked
		end
		return nil
	end
	local _, _, locked, _, _, _, link, _, _, id, bound = Call(rawget(_G, "GetContainerItemInfo"), bag, slot)
	return link, id, bound, locked
end

local function NumSlots(bag)
	local fn = (C_Container and C_Container.GetContainerNumSlots) or rawget(_G, "GetContainerNumSlots")
	return Num(Call(fn, bag)) or 0
end

-- Lié ? true / false / nil (inconnu). Lié quand équipé ? (type de lien 2 dans les infos de l'objet)
local function BindState(link, bound)
	local _, _, _, _, _, _, _, _, _, _, _, _, _, bindType = Call((C_Item and C_Item.GetItemInfo) or rawget(_G, "GetItemInfo"), link)
	local isBound = nil
	if bound == true or bound == false then
		isBound = bound
	end
	return isBound, Num(bindType) == 2
end

local function HasUse(link)
	local fn = (C_Item and C_Item.GetItemSpell) or rawget(_G, "GetItemSpell")
	local spell = Call(fn, link)
	return spell ~= nil
end

local function WornLink(slot)
	return Call(GetInventoryItemLink, "player", slot)
end

local function IdOf(link)
	return tonumber(tostring(link or ""):match("item:(%d+)"))
end

-- Les meilleurs objets des sacs à mettre maintenant : celui qui ne se lie pas (ou l'est déjà), et celui qui se lierait
-- en le mettant (« lié quand équipé ») : { link, id, e (évaluation), bag, slot, boe }.
function Auto.BestUpgrade()
	local G = ns.Gear
	if not (G and G.Evaluate) then
		return nil
	end
	local ignored = G.Config and G.Config().ignored or {}
	local best, bestBoE
	for bag = 0, 4 do
		for slot = 1, NumSlots(bag) do
			local link, id, bound, locked = ContainerItem(bag, slot)
			id = id or IdOf(link)
			if link and id and not locked and not refused[id] and not ignored[id] then
				local e = G.Evaluate(link, { now = true })
				if e and e.gain >= MIN_GAIN and (e.empty or (e.pct or 0) >= MIN_PCT) then
					local worn = WornLink(e.slot)
					if e.empty or not (worn and HasUse(worn)) then -- (un objet à effet « Utiliser » porté : à toi de voir)
						local isBound, boe = BindState(link, bound)
						local u = { link = link, id = id, e = e, bag = bag, slot = slot, boe = boe and isBound ~= true }
						if u.boe then
							if not bestBoE or e.gain > bestBoE.e.gain then
								bestBoE = u
							end
						elseif not best or e.gain > best.e.gain then
							best = u
						end
					end
				end
			end
		end
	end
	return best, bestBoE
end

local function Equip(u)
	if InCombat() or Call(UnitIsDeadOrGhost, "player") then
		Auto.pending = true
		return false
	end
	if Call(rawget(_G, "CursorHasItem")) or Call(rawget(_G, "UnitCastingInfo"), "player") then
		C_Timer.After(2, function()
			Auto.Soon(0)
		end) -- (tu tiens un objet ou tu incantes : plus tard)
		return false
	end
	equipAt = GetTime()
	lastAuto[u.e.slot] = { id = u.id, at = equipAt }
	local ok
	local pickup = C_Container and C_Container.PickupContainerItem
	local toSlot = rawget(_G, "EquipCursorItem")
	if pickup and toSlot then
		-- prendre CET objet-là (deux objets identiques : « par le nom » pourrait prendre l'autre) et le mettre
		ok = pcall(pickup, u.bag, u.slot) and Call(rawget(_G, "CursorHasItem")) and pcall(toSlot, u.e.slot) or false
		if Call(rawget(_G, "CursorHasItem")) then
			Call(rawget(_G, "ClearCursor"))
		end
	else
		local fn = (C_Item and C_Item.EquipItemByName) or rawget(_G, "EquipItemByName")
		ok = pcall(fn, u.link, u.e.slot)
	end
	if ok then
		Note("équipé " .. tostring(u.e.name) .. " (" .. u.e.slotName .. ")")
		ns.Print("équipé : " .. tostring(u.link) .. " |cff00ff00" .. ns.Gear.GainText(u.e) .. "|r (" .. u.e.slotName
			.. ") — remets l'ancien si tu préfères : je n'y toucherai plus.")
	end
	return ok
end

function Auto.CheckGear()
	local cfg = Cfg()
	if not Allowed("equip") then
		return
	end
	if InCombat() then
		Auto.pending = true
		return
	end
	local free, u = Auto.BestUpgrade()
	if free then
		Equip(free) -- (un objet à la fois : la suite au prochain BAG_UPDATE_DELAYED)
		return
	end
	if not u or cfg.equipBoE == "non" then
		return
	end
	if cfg.equipBoE == "auto" then
		pendingBind = { at = GetTime() }
		Equip(u)
		return
	end
	if Auto.Asking("equip" .. u.id) then
		return
	end
	Auto.Ask("equip" .. u.id, string.format("Équiper %s ?\n|cff00ff00%s|r pour toi (%s).\n|cff888888Il deviendra lié à toi (lié quand équipé) : il ne se revendra plus à l'hôtel des ventes.|r",
		tostring(u.link), ns.Gear.GainText(u.e), u.e.slotName), {
		{ label = "Équiper", func = function()
			pendingBind = { at = GetTime() }
			Equip(u)
		end },
		{ label = "Non", func = function()
			refused[u.id] = true
		end },
	})
end

-- Le joueur remet un autre objet là où le pilote vient d'en mettre un : on ne touche plus à cet objet.
function Auto.OnEquipmentChanged(slot)
	slot = Num(slot)
	local mine = slot and lastAuto[slot]
	if not mine or GetTime() - equipAt < 3 then
		return
	end
	local now = IdOf(WornLink(slot))
	if now ~= mine.id then
		refused[mine.id] = true
		lastAuto[slot] = nil
		Note("objet remis à la main : " .. mine.id .. " laissé de côté")
	end
end

-- Blizzard demande de confirmer un objet « lié quand équipé » : le joueur a déjà dit oui dans notre question.
function Auto.OnBindConfirm(slot)
	if pendingBind and GetTime() - pendingBind.at < 3 then
		pendingBind = nil
		local fn = rawget(_G, "EquipPendingItem")
		if type(fn) == "function" and pcall(fn, slot) then
			Call(rawget(_G, "StaticPopup_Hide"), "EQUIP_BIND")
		end -- (sinon la fenêtre du jeu reste : un clic de plus)
	end
end

-------------------------------------------------------------------------------
-- Sacs : un sac des sacs va dans un emplacement de sac libre
-------------------------------------------------------------------------------
local function FreeBagSlot()
	for bag = 1, 4 do
		local fn = (C_Container and C_Container.ContainerIDToInventoryID) or rawget(_G, "ContainerIDToInventoryID")
		local inv = Num(Call(fn, bag))
		if inv and not Call(GetInventoryItemID, "player", inv) then
			return inv
		end
	end
	return nil
end

function Auto.CheckBags()
	if not Allowed("bags") or InCombat() then
		return
	end
	local inv = FreeBagSlot()
	if not inv then
		return
	end
	local best
	for bag = 0, 4 do
		for slot = 1, NumSlots(bag) do
			local link, id, _, locked = ContainerItem(bag, slot)
			if link and not locked then
				local G = ns.Gear
				local inst = G and G.Instant and G.Instant(link)
				local info = G and G.Info and G.Info(link)
				-- (sacs ordinaires seulement : pas de carquois, giberne, sac d'âmes ou de métier)
				if inst and inst.classID == 1 and inst.subclassID == 0 and info then
					if not best or info.ilvl > best.ilvl then
						best = { link = link, id = id, bag = bag, slot = slot, ilvl = info.ilvl }
					end
				end
			end
		end
	end
	if not best then
		return
	end
	local pickup = (C_Container and C_Container.PickupContainerItem) or rawget(_G, "PickupContainerItem")
	if pcall(pickup, best.bag, best.slot) and pcall(PutItemInBag, inv) then
		Note("sac mis : " .. tostring(best.link))
		ns.Print("sac mis : " .. tostring(best.link) .. ".")
	end
	if CursorHasItem and Call(CursorHasItem) then
		Call(ClearCursor)
	end
end

-------------------------------------------------------------------------------
-- Barres d'action : les sorts de ta classe qui n'y sont pas vont dans les cases VIDES des barres affichées, et un sort
-- dont tu as appris un rang supérieur passe à ce rang (Forever garde les rangs, comme Classic, et ne met pas à jour
-- les barres). Rien n'est jamais déplacé ni retiré ; un sort que tu enlèves d'une barre n'y revient plus.
-- Hors combat seulement (le jeu interdit de toucher aux barres en combat), curseur vide.
-------------------------------------------------------------------------------
-- Barres affichées, dans l'ordre où on les remplit (la barre principale en dernier, et jamais si elle change avec
-- la posture ou la forme : guerrier, druide, voleur…).
local MULTI_BARS = { "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft", "MultiBar5",
	"MultiBar6", "MultiBar7" }

local function ButtonSlot(b)
	local slot = Num(rawget(b, "action"))
	if not slot and b.GetAttribute then
		slot = Num(Call(b.GetAttribute, b, "action"))
	end
	return slot
end

local function Visible(b)
	return type(b) == "table" and b.IsVisible and Call(b.IsVisible, b) and true or false
end

-- Les cases vides des barres affichées.
function Auto.FreeActionSlots()
	local out, seen = {}, {}
	local function Add(b)
		local slot = Visible(b) and ButtonSlot(b)
		if slot and not seen[slot] and not Call(HasAction, slot) then
			seen[slot] = true
			out[#out + 1] = slot
		end
	end
	for _, bar in ipairs(MULTI_BARS) do
		for i = 1, 12 do
			Add(rawget(_G, bar .. "Button" .. i))
		end
	end
	if (Num(Call(rawget(_G, "GetBonusBarOffset"))) or 0) == 0 then
		for i = 1, 12 do
			Add(rawget(_G, "ActionButton" .. i))
		end
	end
	return out
end

local function SpellNameOf(id)
	return SpellName(id)
end

-- Les formes et postures (elles ont leur propre barre) : [sort] = true.
local function FormSpells()
	local out = {}
	for i = 1, Num(Call(rawget(_G, "GetNumShapeshiftForms"))) or 0 do
		local _, _, _, spell = Call(GetShapeshiftFormInfo, i)
		if Num(spell) then
			out[spell] = true
		end
	end
	return out
end

-- Rang d'un sort (« Rang 3 » -> 3), ou 0.
local function RankOf(id)
	local text = C_Spell and C_Spell.GetSpellSubtext and Call(C_Spell.GetSpellSubtext, id)
	return tonumber(tostring(text or ""):match("(%d+)")) or 0
end

-- Les sorts actifs appris de ta classe : liste dans l'ordre du grimoire de { id, name } (le plus haut rang de chaque
-- nom seulement) et [nom] = id de ce plus haut rang.
function Auto.ClassSpells()
	local list, byName = {}, {}
	local forms = FormSpells()
	local function Add(id, name)
		id = Num(id)
		name = name or (id and SpellNameOf(id))
		if not (id and type(name) == "string" and name ~= "") or forms[id] then
			return
		end
		local prev = byName[name]
		if not prev then
			byName[name] = id
			list[#list + 1] = { id = id, name = name }
		elseif prev ~= id then
			-- plusieurs rangs dans le grimoire : on garde le plus haut
			local highest = C_ActionBar and C_ActionBar.IsHighestSpellRank
			local better = highest and Call(highest, id) == true or (not highest and RankOf(id) > RankOf(prev))
			if better then
				byName[name] = id
				for _, e in ipairs(list) do
					if e.name == name then
						e.id = id
					end
				end
			end
		end
	end
	local SB = C_SpellBook
	if SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookItemInfo then
		local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
		local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1
		local className = Call(UnitClass, "player")
		local lines, chosen = Num(Call(SB.GetNumSpellBookSkillLines)) or 0, nil
		for i = 1, lines do
			local info = Call(SB.GetSpellBookSkillLineInfo, i)
			if type(info) == "table" and info.name == className then
				chosen = info
			end
		end
		chosen = chosen or (lines >= 2 and Call(SB.GetSpellBookSkillLineInfo, 2)) or nil
		if type(chosen) == "table" then
			local first = Num(chosen.itemIndexOffset) or 0
			for index = first + 1, first + (Num(chosen.numSpellBookItems) or 0) do
				local item = Call(SB.GetSpellBookItemInfo, index, bank)
				if type(item) == "table" and not item.isPassive and not item.isOffSpec
					and (item.itemType == nil or item.itemType == spellType) then
					Add(item.spellID or item.actionID, item.name)
				end
			end
		end
	elseif type(GetSpellTabInfo) == "function" then
		local _, _, first, count = Call(GetSpellTabInfo, 2)
		for index = (Num(first) or 0) + 1, (Num(first) or 0) + (Num(count) or 0) do
			local kind, id = Call(GetSpellBookItemInfo, index, "spell")
			if kind == "SPELL" and not Call(IsPassiveSpell, index, "spell") then
				Add(id)
			end
		end
	end
	return list, byName
end

-- Ce qu'il y a sur les barres : [nom du sort] = { slot, id } (premier trouvé).
local function SpellsOnBars()
	local out = {}
	for slot = 1, 180 do
		local kind, id = Call(GetActionInfo, slot)
		if kind == "spell" and Num(id) then
			local name = SpellNameOf(id)
			if name and not out[name] then
				out[name] = { slot = slot, id = id }
			end
		end
	end
	return out
end

local function CursorBusy()
	return Call(rawget(_G, "GetCursorInfo")) ~= nil
end

-- Pose le sort `id` dans la case `slot` (vide, ou à remplacer par son rang supérieur).
local function PutSpell(id, slot)
	local pick = (C_Spell and C_Spell.PickupSpell) or rawget(_G, "PickupSpell")
	if not pcall(pick, id) or not CursorBusy() then
		Call(rawget(_G, "ClearCursor"))
		return false
	end
	local ok = pcall(PlaceAction, slot)
	local kind, held = Call(GetCursorInfo)
	if kind == "spell" and Num(held) == id then
		Call(ClearCursor) -- (pas posé)
		return false
	end
	if kind then
		Call(ClearCursor) -- l'ancien rang remplacé
	end
	return ok
end

-- ns.char.actionbars = { placed = { [nom] = true }, removed = { [nom] = true }, layout = version | "non",
--   owned = { [case] = nom }, locked = { [case] = true }, parked = { [case] = { kind, id } } (objet ou macro mis par
--   nous sur une touche libre d'une page de posture, faute de place ailleurs), journal = { at, ops } }
local function BarState()
	local char = ns.char or {}
	char.actionbars = type(char.actionbars) == "table" and char.actionbars or {}
	local s = char.actionbars
	s.placed = type(s.placed) == "table" and s.placed or {}
	s.removed = type(s.removed) == "table" and s.removed or {}
	s.owned = type(s.owned) == "table" and s.owned or {}
	s.locked = type(s.locked) == "table" and s.locked or {}
	s.parked = type(s.parked) == "table" and s.parked or {}
	return s
end
local fullWarned

-- Un sort de la barre dont tu connais un rang supérieur passe à ce rang, partout où il est (même place).
local function UpgradeRanks(byName, done)
	local seen = {}
	local highest = C_ActionBar and C_ActionBar.IsHighestSpellRank
	for slot = 1, 180 do
		local kind, id = Call(GetActionInfo, slot)
		id = Num(id)
		if kind == "spell" and id then
			local name = SpellNameOf(id)
			local best = name and byName[name]
			if best and best ~= id then
				local outdated = highest and Call(highest, id) == false or (not highest and RankOf(best) > RankOf(id))
				if outdated and PutSpell(best, slot) and not seen[name] then
					seen[name] = true
					done[#done + 1] = name .. " (rang supérieur)"
				end
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Barres rangées par posture, forme ou camouflage (guerrier, druide, voleur)
--   La barre principale change de page avec la posture du guerrier, la forme du druide (félin, ours ; sélénien et
--   « félin en rôdant » si le jeu leur donne une page) et le camouflage du voleur. Chaque touche y garde le MÊME RÔLE
--   d'une page à l'autre (guerrier : 1 engager, 3 riposte, 8 interrompre, 9 provoquer, 12 survie… ; druide : 1 Griffe
--   / Mutiler / Colère, 3 Griffure / Lacérer / Éclat lunaire, 6 Lucioles partout… ; voleur : 1 Attaque pernicieuse /
--   Coup bas, 2 Attaque sournoise / Embuscade, 5 Rupture / Garrot, 7 Suriner / Assommer…).
--   Un sort absent d'une page où il marche va sur la BARRE FIXE : la première barre affichée en plus de la
--   principale (la même partout). Les pages passagères (camouflage, rôder) ne comptent pas pour la barre fixe.
--   Exigences (posture, forme, camouflage) : celles de Forever 1.60.1 (ForeverDB, build 70959 ; outils/postures.py) :
--   Coup de tonnerre en Combat ET en Défensive, Charge en Défensive avec Avant-garde, Lucioles dans toutes les formes,
--   Charge farouche en félin et en ours, Préméditation sans camouflage…
--   La page d'une forme est celle que le jeu montre vraiment : vue en jeu (`seen`), sinon celle de Classic (félin 1,
--   ours 3, camouflage 1) ; les pages incertaines (sélénien, rôder) ne servent qu'une fois vues.
--   Rangement complet (une question, une fois ; ou /iti barres ranger) : tes objets et macros des touches du
--   rangement vont dans une case libre affichée (jamais effacés ; sans case libre, la touche reste à toi), et tout
--   est noté pour /iti barres annuler. Ensuite, entretien : un nouveau sort va à sa touche si elle est vide (ou tenue
--   par un sort que nous y avions mis en attendant) ; une case que tu changes reste à toi.
-------------------------------------------------------------------------------
local STRIKE = { 23922, 12294, 23881, 402927 } -- Heurt de bouclier, Frappe mortelle, Sanguinaire ; Sursaut de victoire
local CAT = { [2] = true, [3] = true } -- druide : félin (et en rôdant)
local BEAR = { [4] = true }
local HUMAN = { [1] = true } -- soins : pas en sélénien
local STEALTH = { [2] = true } -- voleur : camouflé
local LAYOUTS = {
	WARRIOR = {
		version = 1,
		what = "posture",
		ask = "Ranger tes barres d'action par posture ?\nChaque touche garde le même rôle dans chaque posture (1 Charge, "
			.. "3 Fulgurance / Vengeance, 8 interrompre, 9 provoquer, 12 survie…) ; les cris et les autres sorts vont sur "
			.. "la barre du dessus. Tes objets et macros sont déplacés, jamais effacés. /iti barres annuler pour revenir.",
		-- pages : leur forme (posture) et leur page de la barre principale (GetBonusBarOffset)
		pages = {
			{ key = "combat", label = "Combat", form = { 2457 }, offset = 1 },
			{ key = "defensive", label = "Défensive", form = { 71 }, offset = 2 },
			{ key = "berserker", label = "Berserker", form = { 2458 }, offset = 3 },
		},
		-- arme demandée : « shield » (bouclier porté, ou rôle tank)
		weapon = { [72] = "shield", [2565] = "shield", [871] = "shield", [23922] = "shield" },
		-- pages où un sort marche (absent = toutes) : [page] = true, ou le talent qui l'y permet
		only = {
			[100] = { [1] = true, [2] = 1310317 }, -- Charge (Défensive : talent Avant-garde)
			[7384] = { [1] = true }, -- Fulgurance
			[694] = { [1] = true }, -- Coup railleur
			[20230] = { [1] = true }, -- Représailles
			[12292] = { [1] = true }, -- Attaques circulaires
			[1310222] = { [1] = true }, -- Spearing Strike (Forever)
			[772] = { [1] = true, [2] = true }, -- Pourfendre
			[6343] = { [1] = true, [2] = true }, -- Coup de tonnerre (Forever : aussi en Défensive)
			[72] = { [1] = true, [2] = true }, -- Coup de bouclier
			[1715] = { [1] = true, [3] = true }, -- Brise-genou
			[5308] = { [1] = true, [3] = true }, -- Exécution
			[355] = { [2] = true }, -- Provocation
			[676] = { [2] = true }, -- Désarmement
			[6572] = { [2] = true }, -- Vengeance
			[2565] = { [2] = true }, -- Maîtrise du blocage
			[871] = { [2] = true }, -- Mur protecteur
			[1680] = { [3] = true }, -- Tourbillon
			[1719] = { [3] = true }, -- Témérité
			[18499] = { [3] = true }, -- Rage berserker
			[20252] = { [3] = true }, -- Interception
			[6552] = { [3] = true }, -- Volée de coups
		},
		-- touches 1 à 12 : { rôle, { page 1 }, { page 2 }, … } ; dans chaque liste, le premier sort connu (et permis sur
		-- la page) qui n'y est pas déjà
		keys = {
			{ "engager", { 100 }, { 100 }, { 20252 } },
			{ "frappe héroïque", { 78 }, { 78 }, { 78 } },
			{ "riposte", { 7384 }, { 6572 }, { 1680 } },
			{ "grosse frappe", STRIKE, STRIKE, STRIKE },
			{ "fracasser l'armure", { 7386 }, { 7386 }, { 7386 } },
			{ "zone", { 6343 }, { 6343 }, { 845 } },
			{ "entretien", { 772 }, { 2565, 772 }, { 18499 } },
			{ "interrompre", { 72, 12292, 1310222 }, { 72 }, { 6552 } },
			{ "provoquer", { 694 }, { 355 }, { 1161 } },
			{ "achever / affaiblir", { 5308 }, { 1160 }, { 5308 } },
			{ "contrôle", { 1715 }, { 676 }, { 1715 } },
			{ "survie", { 20230 }, { 871, 12975 }, { 1719 } },
		},
		-- ordre de la barre fixe (les sorts que ce tableau ne connaît pas suivent, dans l'ordre du grimoire)
		static = { 402927, 2687, 6673, 1160, 845, 772, 12975, 12809, 5246, 1161, 1240193, 12323, 12328, 1329555, 12292,
			1310222, 18499, 72 },
	},
	DRUID = {
		version = 1,
		what = "forme",
		ask = "Ranger tes barres d'action par forme ?\nChaque touche garde le même rôle dans chaque forme (1 Colère / "
			.. "Griffe / Mutiler, 3 Éclat lunaire / Griffure / Lacérer, 6 Lucioles partout, 8 étourdir…) ; le reste va "
			.. "sur la barre du dessus. Tes objets et macros sont déplacés, jamais effacés. /iti barres annuler pour revenir.",
		free = { [1] = true, [5] = true }, -- un sort sans forme exigée : en humanoïde et en sélénien
		pages = {
			{ key = "humanoide", label = "Humanoïde", always = true, offset = 0 },
			{ key = "felin", label = "Félin", form = { 768 }, offset = 1 },
			{ key = "rodeur", label = "Félin en rôdant", need = { 5215 }, within = 2, stealth = true, offset = 2,
				optional = true, transient = true, keysFrom = 2, usableAs = 2 },
			{ key = "ours", label = "Ours", form = { 5487, 9634 }, offset = 3 },
			{ key = "selenien", label = "Sélénien", form = { 24858 }, offset = 4, optional = true, keysFrom = 1 },
		},
		only = {
			-- félin (et en rôdant)
			[1082] = CAT, [5221] = CAT, [1822] = CAT, [1328618] = CAT, [1079] = CAT, [9005] = CAT, [6785] = CAT,
			[8998] = CAT, [1850] = CAT, [5215] = CAT, [5225] = CAT, [1322605] = CAT,
			-- ours
			[6807] = BEAR, [779] = BEAR, [1328617] = BEAR, [407995] = BEAR, [99] = BEAR, [5211] = BEAR, [6795] = BEAR,
			[22842] = BEAR, [5229] = BEAR, [5209] = BEAR,
			-- Forever : Charge farouche en félin et en ours, Lucioles dans toutes les formes
			[1238122] = { [2] = true, [3] = true, [4] = true },
			[770] = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true },
			-- soins et résurrections : en humanoïde seulement (le sélénien les interdit)
			[5185] = HUMAN, [774] = HUMAN, [8936] = HUMAN, [18562] = HUMAN, [408120] = HUMAN, [740] = HUMAN,
			[20484] = HUMAN, [437138] = HUMAN,
		},
		-- { rôle, { humanoïde }, { félin }, { rôder : comme félin }, { ours }, { sélénien : comme humanoïde } }
		keys = {
			{ "frappe", { 5176 }, { 1082 }, {}, { 6807 } }, -- Colère / Griffe / Mutiler
			{ "frappe 2", { 2912 }, { 5221 }, {}, { 779 } }, -- Feu stellaire / Lambeau / Balayage
			{ "saignement", { 8921 }, { 1822 }, {}, { 1328617 } }, -- Éclat lunaire / Griffure / Lacérer
			{ "grosse frappe", { 5570, 16914 }, { 1328618 }, {}, { 407995 } }, -- Essaim d'insectes / Morsure féroce / Morsure primale
			{ "finir / affaiblir", { 339 }, { 1079 }, {}, { 99 } }, -- Sarments / Déchirure / Rugissement démoralisant
			{ "lucioles", { 770 }, { 770 }, {}, { 770 } },
			{ "soigner / charger", { 5185 }, { 1238122 }, {}, { 1238122 } }, -- Toucher guérisseur / Charge farouche
			{ "soigner / étourdir", { 774 }, { 9005 }, {}, { 5211 } }, -- Récupération / Traquenard / Sonner
			{ "soigner / provoquer", { 8936 }, { 6785 }, {}, { 6795 } }, -- Rétablissement / Ravager / Grondement
			{ "survie", { 18562, 408120 }, { 8998 }, {}, { 22842 } }, -- Prompte guérison / Dérobade / Régénération frénétique
			{ "vitesse / rage", { 17116, 22812 }, { 1850 }, {}, { 5229 } }, -- Rapidité de la nature / Célérité / Enrager
			{ "rôder / défi", { 29166, 22812 }, { 5215 }, {}, { 5209 } }, -- Innervation / Rôder / Rugissement provocateur
		},
		static = { 16689, 22812, 29166, 2782, 2893, 8946, 20484, 437138, 1126, 467, 21849, 2637, 16914, 740, 408120,
			18562, 2908, 1322605, 5225, 18960 },
	},
	ROGUE = {
		version = 1,
		what = "camouflage",
		ask = "Ranger tes barres d'action pour le camouflage ?\nLa barre principale change quand tu es camouflé ; chaque "
			.. "touche y garde le même rôle (1 Attaque pernicieuse / Coup bas, 2 Attaque sournoise / Embuscade, 5 Rupture / "
			.. "Garrot, 7 Suriner / Assommer…) ; les autres techniques vont sur la barre du dessus. Tes objets et macros "
			.. "sont déplacés, jamais effacés. /iti barres annuler pour revenir.",
		pages = {
			{ key = "normal", label = "Normal", always = true, offset = 0 },
			{ key = "camouflage", label = "Camouflé", need = { 1784 }, stealth = true, offset = 1, transient = true },
		},
		-- « dagger » : dague en main droite ; « dagger2 » : dagues dans les deux mains
		weapon = { [53] = "dagger", [8676] = "dagger", [399956] = "dagger2" },
		only = { [1833] = STEALTH, [8676] = STEALTH, [703] = STEALTH, [6770] = STEALTH, [921] = STEALTH },
		keys = {
			{ "générer", { 399956, 16511, 1752 }, { 1833, 8676, 703 } }, -- Mutilation, Hémorragie, Attaque pernicieuse / Coup bas
			{ "dans le dos", { 53, 14278 }, { 8676, 703 } }, -- Attaque sournoise, Frappe fantomatique / Embuscade, Garrot
			{ "finir", { 2098 }, { 2098 } }, -- Éviscération
			{ "débiter", { 5171 }, { 5171 } }, -- Débiter
			{ "saignement", { 1943 }, { 703, 1943 } }, -- Rupture / Garrot
			{ "interrompre", { 1766 }, { 1766 } }, -- Coup de pied
			{ "neutraliser", { 1776 }, { 6770 } }, -- Suriner / Assommer
			{ "étourdir / voler", { 408 }, { 921 } }, -- Aiguillon perfide / Vol à la tire
			{ "réaction / ouverture", { 14251, 8647 }, { 14183, 1725 } }, -- Riposte, Exposer l'armure / Préméditation, Distraction
			{ "survie", { 5277 }, { 1725 } }, -- Évasion / Distraction
			{ "fuite", { 2983 }, { 2983 } }, -- Sprint
			{ "disparaître", { 1856, 1784 }, { 1784 } }, -- Disparition (sinon Camouflage) / Camouflage
		},
		static = { 1784, 1966, 2094, 1329283, 14177, 13877, 13750, 14185, 1316709, 8647, 1725, 1856, 53, 1842 },
	},
}
Auto.LAYOUTS = LAYOUTS

local function SpellKnown(id)
	if not id then
		return false
	end
	return Call(rawget(_G, "IsPlayerSpell"), id) == true or Call(rawget(_G, "IsSpellKnown"), id) == true
		or (C_SpellBook and Call(C_SpellBook.IsSpellKnown, id) == true) or false
end

-- Le sort marche-t-il sur la page `index` ? (absent de `only` : sur les pages `free`, sinon partout)
local function Usable(layout, rank1, index)
	local only = rank1 and layout.only[rank1]
	if not only then
		return not layout.free or layout.free[index] == true
	end
	local v = only[index]
	return v == true or (type(v) == "number" and SpellKnown(v))
end

local function HandSubclass(slot)
	local link = Call(rawget(_G, "GetInventoryItemLink"), "player", slot)
	if type(link) ~= "string" then
		return nil
	end
	local fn = (C_Item and C_Item.GetItemInfoInstant) or rawget(_G, "GetItemInfoInstant")
	local _, _, _, _, _, classID, subclassID = Call(fn, link)
	return Num(classID), Num(subclassID)
end

-- L'arme qu'il faut est-elle portée ? « shield » : bouclier (ou rôle tank) ; « dagger » : dague en main droite ;
-- « dagger2 » : dagues dans les deux mains.
local function WeaponOK(need)
	if not need then
		return true
	end
	if need == "shield" then
		local c, s = HandSubclass(17)
		return (c == 4 and s == 6) or (ns.Gear and ns.Gear.Role and Call(ns.Gear.Role) == "tank") or false
	end
	local c, s = HandSubclass(16)
	local main = c == 2 and s == 15
	if need == "dagger" then
		return main
	end
	local c2, s2 = HandSubclass(17)
	return main and c2 == 2 and s2 == 15
end

-- Case d'une touche (1 à 12) de la page `offset` de la barre principale : page 0 = cases 1 à 12 (hors posture),
-- page 1 = 73 à 84, page 2 = 85 à 96, etc.
local function PageSlot(offset, key)
	if offset == 0 then
		return key
	end
	local pages = Num(rawget(_G, "NUM_ACTIONBAR_PAGES")) or 6
	local per = Num(rawget(_G, "NUM_ACTIONBAR_BUTTONS")) or 12
	return (pages + offset - 1) * per + key
end

-- La barre principale suit-elle les pages qu'on croit ? Sinon on ne touche à rien (raison pour /iti rapport).
local function PagingProblem()
	local offset = Num(Call(rawget(_G, "GetBonusBarOffset"))) or 0
	local b = rawget(_G, "ActionButton1")
	local slot = type(b) == "table" and ButtonSlot(b) or nil
	if slot and slot ~= PageSlot(offset, 1) then
		return "la barre principale montre la case " .. slot .. " (page " .. offset .. ", attendu " .. PageSlot(offset, 1)
			.. (offset == 0 and " : remets la page 1 de ta barre" or "") .. ")"
	end
end

-- Ce qu'il y a dans une case : { kind, id, name (sort), class (sort de ta classe) } ou nil.
local function SlotContent(slot, byName)
	local kind, id = Call(GetActionInfo, slot)
	if type(kind) ~= "string" then
		return nil
	end
	local c = { kind = kind, id = Num(id) }
	if kind == "spell" and c.id then
		c.name = SpellNameOf(c.id)
		c.class = c.name ~= nil and byName[c.name] ~= nil
	end
	return c
end

-- Les barres affichées en plus de la principale : la barre fixe (la première) et les cases des autres.
local function ExtraBars()
	local fixed, others = nil, {}
	for _, bar in ipairs(MULTI_BARS) do
		local slots = {}
		for i = 1, 12 do
			local b = rawget(_G, bar .. "Button" .. i)
			local slot = Visible(b) and ButtonSlot(b)
			if slot then
				slots[#slots + 1] = slot
			end
		end
		if #slots > 0 and not fixed then
			fixed = slots
		else
			for _, s in ipairs(slots) do
				others[#others + 1] = s
			end
		end
	end
	return fixed or {}, others
end

-- La forme (ou posture) active : son sort, ou nil.
local function ActiveForm()
	for i = 1, Num(Call(rawget(_G, "GetNumShapeshiftForms"))) or 0 do
		local _, active, _, spell = Call(GetShapeshiftFormInfo, i)
		if active == true and Num(spell) then
			return spell
		end
	end
end

local function PageMatches(layout, index, formName, stealthed)
	local p = layout.pages[index]
	if p.form then
		local ok = false
		for _, id in ipairs(p.form) do
			if formName and SpellName(id) == formName then
				ok = true
			end
		end
		if not ok then
			return false
		end
	end
	if p.stealth and not stealthed then
		return false
	end
	if p.within and not PageMatches(layout, p.within, formName, stealthed) then
		return false
	end
	return p.always or p.form ~= nil or p.stealth ~= nil
end

-- La page que tu vois maintenant (la plus précise : « félin en rôdant » plutôt que « félin ») : son index, ou nil.
local function CurrentPage(layout)
	local form = ActiveForm()
	local formName = form and SpellName(form)
	local stealthed = Call(rawget(_G, "IsStealthed")) == true
	local best, bestScore
	for i, p in ipairs(layout.pages) do
		if PageMatches(layout, i, formName, stealthed) then
			local score = (p.form and 1 or 0) + (p.stealth and 1 or 0) + (p.within and 1 or 0)
			if not best or score > bestScore then
				best, bestScore = i, score
			end
		end
	end
	return best
end

-- Note la page que le jeu montre dans la forme actuelle (hors combat). Rend true si c'est nouveau.
function Auto.ObservePage()
	local layout = LAYOUTS[PlayerClass()]
	if not layout or InCombat() then
		return false
	end
	local index = CurrentPage(layout)
	local offset = Num(Call(rawget(_G, "GetBonusBarOffset")))
	if not (index and offset) then
		return false
	end
	local state = BarState()
	state.seen = type(state.seen) == "table" and state.seen or {}
	local key = layout.pages[index].key
	if state.seen[key] ~= offset then
		state.seen[key] = offset
		return true
	end
	return false
end

-- Ce que le rangement veut, d'après les sorts que tu connais : t.pages = { { offset, label, index, keys =
-- { [touche] = { id, name, role } } }, … } (pages de ta barre principale), t.static = { { id, name }, … } (barre
-- fixe, dans l'ordre), t.byName (sorts de ta classe) ; nil si ta classe n'a pas de rangement.
function Auto.LayoutTargets()
	local layout = LAYOUTS[PlayerClass()]
	if not layout then
		return nil
	end
	Auto.ObservePage()
	local list, byName = Auto.ClassSpells()
	local forms = FormSpells()
	local formsByName = {}
	for id in pairs(forms) do
		local name = SpellName(id)
		if name then
			formsByName[name] = id
		end
	end
	local rank1Of, order, all = {}, {}, {}
	for _, s in ipairs(list) do
		all[#all + 1] = s
	end
	local function Remember(id)
		local name = SpellName(id)
		if name and not rank1Of[name] then
			rank1Of[name] = id
		end
		return name
	end
	-- un sort des tableaux : son plus haut rang connu (un talent actif absent du grimoire de classe, ou une forme comme
	-- le Camouflage du voleur, compte aussi)
	local function Known(rank1)
		local name = Remember(rank1)
		if not name then
			return nil
		end
		local id = byName[name] or formsByName[name] or (SpellKnown(rank1) and rank1) or nil
		if id and not byName[name] then
			byName[name] = id
			all[#all + 1] = { id = id, name = name }
		end
		return id, name
	end
	for i, id in ipairs(layout.static) do
		local name = Remember(id)
		if name and not order[name] then
			order[name] = i
		end
		Known(id)
	end
	for id in pairs(layout.only) do
		Remember(id)
	end
	local seen = type(BarState().seen) == "table" and BarState().seen or {}
	local t = { pages = {}, static = {}, byName = byName }
	local placed, usedOffsets = {}, {} -- placed[nom] = { [page] = true }
	for index, p in ipairs(layout.pages) do
		local known = p.always
		for _, id in ipairs(p.form or p.need or {}) do
			known = known or forms[id] or formsByName[SpellName(id) or ""] or SpellKnown(id)
		end
		local offset = Num(seen[p.key]) or p.offset
		if p.optional and not (Num(seen[p.key]) and seen[p.key] > 0) then
			known = false
		end
		if known and not usedOffsets[offset] then
			usedOffsets[offset] = true
			local page = { offset = offset, label = p.label, index = index, transient = p.transient, keys = {} }
			local used = {}
			local usableAs = p.usableAs or index
			for key, row in ipairs(layout.keys) do
				for _, rank1 in ipairs(row[(p.keysFrom or index) + 1] or {}) do
					local id, name
					if Usable(layout, rank1, usableAs) and WeaponOK(layout.weapon and layout.weapon[rank1]) then
						id, name = Known(rank1)
					end
					if id and not used[name] then
						used[name] = true
						page.keys[key] = { id = id, name = name, role = row[1] }
						placed[name] = placed[name] or {}
						placed[name][index] = true
						break
					end
				end
			end
			t.pages[#t.pages + 1] = page
		end
	end
	-- barre fixe : un sort sur aucune page, ou absent d'une page (pas passagère) où il marche
	local rest = {}
	for i, spell in ipairs(all) do
		local missing = not placed[spell.name]
		for _, page in ipairs(t.pages) do
			if not page.transient and not (placed[spell.name] and placed[spell.name][page.index])
				and Usable(layout, rank1Of[spell.name], page.index) then
				missing = true
			end
		end
		if missing then
			rest[#rest + 1] = { id = spell.id, name = spell.name, sort = order[spell.name] or (1000 + i) }
		end
	end
	table.sort(rest, function(a, b)
		return a.sort < b.sort
	end)
	t.static = rest
	return t, layout
end

local function Journal(journal, op)
	if journal then
		journal[#journal + 1] = op
	end
end

-- Vide une case (un sort de ta classe seulement).
local function ClearSlot(slot, journal, before)
	Call(rawget(_G, "PickupAction"), slot)
	local kind = Call(GetCursorInfo)
	Call(ClearCursor)
	if kind then
		Journal(journal, { op = "set", slot = slot, before = before or {} })
	end
	return kind ~= nil
end

local function SetSpell(slot, id, journal, before)
	if PutSpell(id, slot) then
		Journal(journal, { op = "set", slot = slot, before = before or {} })
		return true
	end
	return false
end

-- Déplace ce qu'il y a dans `from` (objet, macro…) vers la case vide `to`. Jamais effacé : si le jeu refuse, la chose
-- revient à sa place (ou reste sur le curseur).
local function MoveAction(from, to, journal, c)
	if Call(HasAction, to) then
		return false
	end
	Call(rawget(_G, "PickupAction"), from)
	if not CursorBusy() then
		return false
	end
	pcall(PlaceAction, to)
	if CursorBusy() then
		pcall(PlaceAction, from)
		return false
	end
	Journal(journal, { op = "move", from = from, to = to, kind = c and c.kind, id = c and c.id })
	return true
end

-- Range (force : rangement complet) ou entretient les barres. Rend { placed = { texte, … }, moved, kept = { touche,
-- … }, missing, pages } ou nil et la raison.
function Auto.ArrangeBars(force)
	if InCombat() then
		Auto.pending = true
		return nil, "en combat"
	end
	if CursorBusy() then
		return nil, "il y a quelque chose sur le curseur"
	end
	if type(PlaceAction) ~= "function" or type(GetActionInfo) ~= "function"
		or type(rawget(_G, "PickupAction")) ~= "function" then
		return nil, "barres d'action illisibles"
	end
	local t, layout = Auto.LayoutTargets()
	if not t then
		return nil, "pas de rangement pour ta classe"
	end
	if #t.pages == 0 then
		return nil, "rien à ranger : pas encore de " .. layout.what
	end
	local problem = PagingProblem()
	if problem then
		return nil, problem
	end
	local state = BarState()
	local owned, locked, removed, parked = state.owned, state.locked, state.removed, state.parked
	local byName = t.byName
	local journal = force and {} or nil
	local fixed, others = ExtraBars()
	local res = { placed = {}, moved = 0, kept = {}, missing = 0, pages = t.pages, what = layout.what }
	UpgradeRanks(byName, res.placed)
	local function Content(slot)
		return SlotContent(slot, byName)
	end
	local want, stanceSlots, pageOf = {}, {}, {}
	for _, page in ipairs(t.pages) do
		for key = 1, 12 do
			local slot = PageSlot(page.offset, key)
			stanceSlots[#stanceSlots + 1] = slot
			pageOf[slot] = page
			want[slot] = page.keys[key]
		end
	end
	local shown = {} -- cases affichées hors des pages de posture : la barre fixe, puis les autres barres
	for _, s in ipairs(fixed) do
		shown[#shown + 1] = s
	end
	for _, s in ipairs(others) do
		shown[#shown + 1] = s
	end
	local function KeyText(slot)
		local page = pageOf[slot]
		return page.label .. " " .. (slot - PageSlot(page.offset, 0))
	end
	-- 1. ce que tu as changé depuis le dernier passage reste à toi (rangement complet : tout est remis à plat)
	if force then
		wipe(locked)
		wipe(removed)
		wipe(owned)
		wipe(parked)
	else
		for slot, p in pairs(parked) do
			local c = Content(slot)
			if not (c and type(p) == "table" and c.kind == p.kind and c.id == p.id) then
				parked[slot] = nil
			end
		end
		local onBars = SpellsOnBars()
		for slot, name in pairs(owned) do
			local c = Content(slot)
			if not (c and c.name == name) then
				owned[slot] = nil
				locked[slot] = true
				if not onBars[name] then
					removed[name] = true
					Note("barres : « " .. name .. " » enlevé à la main, laissé de côté")
				end
			end
		end
	end
	-- 2. rangement complet : les sorts de ta classe qui ne sont pas à leur place s'en vont (remis à la bonne ensuite)
	if force then
		for _, slots in ipairs({ stanceSlots, shown }) do
			for _, slot in ipairs(slots) do
				local c = Content(slot)
				if c and c.class and not (want[slot] and want[slot].name == c.name) then
					ClearSlot(slot, journal, { id = c.id })
				end
			end
		end
	end
	local function Empty(slot)
		return not want[slot] and not Call(HasAction, slot)
	end
	-- (rangement complet : les premières cases vides de la barre fixe sont gardées pour ses sorts)
	local reserved = {}
	if force then
		local n = 0
		for _, slot in ipairs(fixed) do
			if n < #t.static and Empty(slot) then
				reserved[slot] = true
				n = n + 1
			end
		end
	end
	-- une case libre pour un objet ou une macro qui doit laisser sa touche : une barre affichée en plus de la
	-- principale, sinon une touche libre de la même page (« garé » : il repartira si cette touche sert un jour)
	local function FreeFor(page)
		for _, s in ipairs(shown) do
			if Empty(s) and not reserved[s] and not locked[s] then
				return s, false
			end
		end
		for key = 1, 12 do
			local s = PageSlot(page.offset, key)
			if Empty(s) and not locked[s] then
				return s, true
			end
		end
	end
	-- 3. les touches de chaque posture
	for _, slot in ipairs(stanceSlots) do
		local w = want[slot]
		if w and not locked[slot] then
			local c = Content(slot)
			if c and c.name == w.name then
				owned[slot] = w.name
			elseif not c or (c.class and owned[slot]) then
				if SetSpell(slot, w.id, journal, c and c.kind == "spell" and { id = c.id } or {}) then
					owned[slot] = w.name
					res.placed[#res.placed + 1] = w.name .. " (" .. KeyText(slot) .. ")"
				end
			elseif force or (type(parked[slot]) == "table" and parked[slot].kind == c.kind and parked[slot].id == c.id) then
				-- un objet, une macro… : vers une case libre affichée, sinon la touche reste à toi
				local dest, onPage = FreeFor(pageOf[slot])
				if dest and MoveAction(slot, dest, journal, c) then
					parked[slot] = nil
					if onPage then
						parked[dest] = { kind = c.kind, id = c.id }
					end
					res.moved = res.moved + 1
					if SetSpell(slot, w.id, journal, {}) then
						owned[slot] = w.name
						res.placed[#res.placed + 1] = w.name .. " (" .. KeyText(slot) .. ")"
					end
				elseif force then
					res.kept[#res.kept + 1] = KeyText(slot)
				end
			end
		end
	end
	-- 4. la barre fixe
	local staticSet = {}
	for _, s in ipairs(t.static) do
		staticSet[s.name] = true
	end
	if not force then
		-- un sort que nous y avions mis et qui a maintenant sa touche dans toutes ses postures : retiré
		for _, slot in ipairs(shown) do
			local c = owned[slot] and Content(slot)
			if c and c.class and c.name == owned[slot] and not staticSet[c.name] then
				ClearSlot(slot)
				owned[slot] = nil
			end
		end
	end
	local present = {}
	for _, slot in ipairs(shown) do
		local c = Content(slot)
		if c and c.name then
			present[c.name] = true
		end
	end
	for _, s in ipairs(t.static) do
		if not present[s.name] and not removed[s.name] then
			local dest
			for _, slot in ipairs(shown) do
				if Empty(slot) and not locked[slot] then
					dest = slot
					break
				end
			end
			if not dest then
				res.missing = res.missing + 1
			elseif SetSpell(dest, s.id, journal, {}) then
				owned[dest] = s.name
				present[s.name] = true
				res.placed[#res.placed + 1] = s.name .. " (barre du dessus)"
			end
		end
	end
	if journal and #journal > 0 then
		state.journal = { at = date("%Y-%m-%d %H:%M"), ops = journal }
	end
	return res
end

local function ReportArranged(res, force)
	if force then
		local labels = {}
		for _, p in ipairs(res.pages) do
			labels[#labels + 1] = p.label
		end
		ns.Print(string.format("barres rangées par %s (%s) : %d sort(s) posé(s)%s. /iti barres pour voir chaque "
			.. "touche, /iti barres annuler pour revenir.", res.what or "posture", table.concat(labels, ", "), #res.placed,
			res.moved > 0 and (", " .. res.moved .. " objet(s) ou macro(s) déplacé(s) vers une case libre") or ""))
	elseif #res.placed > 0 then
		ns.Print("barres d'action : " .. table.concat(res.placed, ", ")
			.. (res.moved > 0 and (" (" .. res.moved .. " objet(s) ou macro(s) déplacé(s) pour leur faire place)") or "") .. ".")
	end
	if #res.placed > 0 then
		Note("barres : " .. table.concat(res.placed, ", "))
	end
	if #res.kept > 0 then
		ns.Print("barres : touche(s) laissée(s) à tes objets ou macros, faute de case libre : "
			.. table.concat(res.kept, ", ") .. ".")
	end
	if res.missing > 0 and (force or not fullWarned) then
		fullWarned = true
		ns.Print("barres : plus de case libre pour " .. res.missing .. " sort(s) : affiche une barre de plus (Échap > "
			.. "Options > Barres d'action) puis /iti barres ranger.")
	end
end

-- Annule le dernier rangement complet (et arrête l'entretien). Rend true et le nombre de cases pas remises, ou nil
-- et la raison.
function Auto.UndoBars()
	local state = BarState()
	local j = state.journal
	if type(j) ~= "table" or type(j.ops) ~= "table" or #j.ops == 0 then
		return nil, "rien à annuler"
	end
	if InCombat() then
		return nil, "en combat"
	end
	if CursorBusy() then
		return nil, "il y a quelque chose sur le curseur"
	end
	local _, byName = Auto.ClassSpells()
	local fails = 0
	for i = #j.ops, 1, -1 do
		local op = j.ops[i]
		if type(op) == "table" and op.op == "set" and Num(op.slot) then
			local c = SlotContent(op.slot, byName)
			local before = type(op.before) == "table" and Num(op.before.id) or nil
			if c and not c.class then
				fails = fails + 1 -- un objet ou une macro posé depuis : on n'y touche pas
			elseif before then
				if not (c and c.id == before) and not PutSpell(before, op.slot) then
					fails = fails + 1
				end
			elseif c then
				ClearSlot(op.slot)
			end
		elseif type(op) == "table" and op.op == "move" and Num(op.from) and Num(op.to) then
			local c = SlotContent(op.to, byName)
			if not (c and c.kind == op.kind and c.id == op.id and not Call(HasAction, op.from)
				and MoveAction(op.to, op.from, nil, c)) then
				fails = fails + 1
			end
		end
	end
	state.journal = nil
	state.layout = "non"
	wipe(state.owned)
	wipe(state.locked)
	wipe(state.parked)
	return true, fails
end

-- /iti barres : chaque touche de chaque posture, et la barre fixe.
function Auto.LayoutLines()
	local t, layout = Auto.LayoutTargets()
	if not t then
		return { "barres : pas de rangement pour ta classe (guerrier, druide et voleur seulement ; le pilote remplit les "
			.. "cases vides)." }
	end
	local state = BarState()
	local status = state.layout == layout.version and "rangées, entretenues par le pilote"
		or state.layout == "non" and "pas rangées (/iti barres ranger pour le faire)"
		or "pas encore rangées (/iti barres ranger)"
	local lines = { "barres par " .. layout.what .. " : " .. status .. (type(state.journal) == "table"
		and (" · /iti barres annuler revient à l'état du " .. tostring(state.journal.at)) or "") }
	for _, page in ipairs(t.pages) do
		local parts = {}
		for key = 1, 12 do
			local w = page.keys[key]
			parts[#parts + 1] = key .. " " .. (w and w.name or "-")
		end
		lines[#lines + 1] = page.label .. " : " .. table.concat(parts, " · ")
	end
	local names = {}
	for _, s in ipairs(t.static) do
		names[#names + 1] = s.name
	end
	lines[#lines + 1] = "barre du dessus (partout) : " .. (#names > 0 and table.concat(names, ", ") or "-")
	return lines
end

-- /iti barres [ranger | annuler | non]
function Auto.BarsCommand(arg)
	local layout = LAYOUTS[PlayerClass()]
	local state = BarState()
	if not layout then
		ns.Print(Auto.LayoutLines()[1])
		return
	end
	if arg == "ranger" or arg == "range" then
		if ns.Pilote.Blocked and ns.Pilote.Blocked("actionbars") then
			ns.Print("barres : le jeu a bloqué cette partie du pilote pour la session (/iti rapport).")
			return
		end
		local res, why = Auto.ArrangeBars(true)
		if not res then
			state.layoutError = why
			ns.Print("barres : rien rangé (" .. tostring(why) .. ").")
			return
		end
		state.layout = layout.version
		state.layoutError = nil
		ReportArranged(res, true)
		if not Allowed("actionbars") then
			ns.Print("barres : l'entretien (nouveaux sorts à leur touche) se fera quand le pilote et sa case « barres "
				.. "d'action » seront allumés (/iti reglages > Pilote).")
		end
	elseif arg == "annuler" or arg == "undo" then
		local ok, fails = Auto.UndoBars()
		if not ok then
			ns.Print("barres : " .. tostring(fails) .. ".")
		else
			ns.Print("barres : rangement annulé" .. (fails > 0 and (" (" .. fails .. " case(s) changée(s) depuis, laissée(s) "
				.. "telle(s) quelle(s))") or "") .. ". Plus d'entretien du rangement (/iti barres ranger pour le refaire).")
		end
	elseif arg == "non" or arg == "stop" then
		state.layout = "non"
		ns.Print("barres : plus d'entretien du rangement (/iti barres ranger pour le refaire).")
	else
		for _, line in ipairs(Auto.LayoutLines()) do
			ns.Print(line)
		end
		ns.Print("/iti barres ranger · /iti barres annuler · /iti barres non")
	end
end

local layoutAsked
local function AskLayout(layout)
	if layoutAsked or Auto.Asking("barres") then
		return
	end
	layoutAsked = true
	Auto.Ask("barres", layout.ask, {
		{ label = "Ranger", func = function()
			Auto.BarsCommand("ranger")
		end },
		{ label = "Plus tard" },
		{ label = "Jamais", func = function()
			BarState().layout = "non"
			ns.Print("barres : pas de rangement (/iti barres ranger quand tu veux).")
		end },
	})
end

function Auto.CheckActionBars()
	if not Allowed("actionbars") or InCombat() then
		if InCombat() then
			Auto.pending = true
		end
		return
	end
	if CursorBusy() or type(PlaceAction) ~= "function" or type(GetActionInfo) ~= "function" then
		return
	end
	local layout = LAYOUTS[PlayerClass()]
	local state = BarState()
	-- barres rangées par posture : entretien
	if layout and state.layout == layout.version then
		local res, why = Auto.ArrangeBars(false)
		if res then
			ReportArranged(res, false)
		elseif why and why ~= state.layoutError then
			state.layoutError = why
			Note("barres : " .. why)
		end
		return
	end
	local list, byName = Auto.ClassSpells()
	if #list == 0 then
		return
	end
	local onBars = SpellsOnBars()
	-- un sort que nous avions posé et qui n'est plus sur les barres : tu l'as enlevé, il n'y revient plus
	for name in pairs(state.placed) do
		if not onBars[name] then
			state.placed[name] = nil
			state.removed[name] = true
			Note("barres : « " .. name .. " » enlevé à la main, laissé de côté")
		end
	end
	local done = {}
	-- 1. rangs supérieurs, à la même place (partout)
	UpgradeRanks(byName, done)
	onBars = SpellsOnBars()
	-- 2. sorts qui manquent, dans les cases vides
	local free = Auto.FreeActionSlots()
	local missing = 0
	for _, spell in ipairs(list) do
		if not onBars[spell.name] and not state.removed[spell.name] then
			local slot = table.remove(free, 1)
			if not slot then
				missing = missing + 1
			elseif PutSpell(spell.id, slot) then
				state.placed[spell.name] = true
				done[#done + 1] = spell.name
			end
		end
	end
	if #done > 0 then
		Note("barres : " .. table.concat(done, ", "))
		ns.Print("barres d'action : " .. table.concat(done, ", ") .. ".")
	end
	if missing > 0 and not fullWarned then
		fullWarned = true
		ns.Print("barres d'action : plus de case vide pour " .. missing .. " sort(s) (affiche une barre de plus : Échap > Options > Barres d'action).")
	end
	-- ta classe a un rangement par posture : proposé une fois
	if layout and state.layout == nil then
		AskLayout(layout)
	end
end

-------------------------------------------------------------------------------
-- Événements
-------------------------------------------------------------------------------
local timer
local function Soon(delay)
	if timer then
		return
	end
	timer = true
	C_Timer.After(delay or 0.6, function()
		timer = nil
		if not ns.ready then
			return
		end
		Auto.pending = false
		for _, fn in ipairs({ Auto.CheckTalents, Auto.CheckGear, Auto.CheckBags, Auto.CheckActionBars }) do
			local ok, err = pcall(fn)
			if not ok and ns.OnError then
				ns.OnError("pilote (talents / équipement) : " .. tostring(err))
			end
		end
	end)
end
Auto.Soon = Soon

local events = CreateFrame("Frame")
local HANDLERS = {
	PLAYER_LEVEL_UP = function()
		Soon(1.5)
	end,
	CHARACTER_POINTS_CHANGED = function()
		learning = nil
		Soon(0.6)
	end,
	BAG_UPDATE_DELAYED = function()
		Soon(0.8)
	end,
	-- nouveau sort (ou rang) appris : barres d'action
	SPELLS_CHANGED = function()
		Soon(1.5)
	end,
	LEARNED_SPELL_IN_SKILL_LINE = function()
		Soon(1)
	end,
	LEARNED_SPELL_IN_TAB = function()
		Soon(1)
	end,
	PLAYER_EQUIPMENT_CHANGED = function(slot)
		Auto.OnEquipmentChanged(slot)
	end,
	EQUIP_BIND_CONFIRM = function(slot)
		Auto.OnBindConfirm(slot)
	end,
	AUTOEQUIP_BIND_CONFIRM = function(slot)
		Auto.OnBindConfirm(slot)
	end,
	-- Forever : nos talents appliqués, ou l'incantation interrompue
	TRAIT_CONFIG_UPDATED = function(configID)
		Auto.OnTraitsCommitted(configID, false)
		Soon(0.8)
	end,
	CONFIG_COMMIT_FAILED = function(configID)
		Auto.OnTraitsCommitted(configID, true)
	end,
	-- posture, forme ou camouflage : la page que le jeu montre (une page encore inconnue : on la range)
	UPDATE_SHAPESHIFT_FORM = function()
		if Auto.ObservePage() then
			Soon(1)
		end
	end,
	UPDATE_BONUS_ACTIONBAR = function()
		if Auto.ObservePage() then
			Soon(1)
		end
	end,
	UPDATE_STEALTH = function()
		if Auto.ObservePage() then
			Soon(1)
		end
	end,
	PLAYER_REGEN_ENABLED = function()
		if Auto.pending then
			Soon(1)
		end
		ShowNext()
	end,
}
for event in pairs(HANDLERS) do
	pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...)
	local fn = HANDLERS[event]
	if not (fn and ns.ready) then
		return
	end
	local ok, err = pcall(fn, ...)
	if not ok and ns.OnError then
		ns.OnError("pilote (" .. event .. ") : " .. tostring(err))
	end
end)

-- Au démarrage (Questie prêt) : un premier tour quelques secondes après.
function Auto.Init()
	C_Timer.After(6, function()
		Soon(0)
	end)
end

-- /iti talents : où en est le plan.
function Auto.TalentsText()
	local plan, key = Auto.Plan()
	if not plan then
		return "talents : pas encore de plan pour ta classe (guerrier pour l'instant)."
	end
	local nextT, why = Auto.NextTalent()
	local mode = Cfg().talents
	return string.format("talents : plan « %s » · mode %s · %s", plan.label,
		mode == "auto" and "automatique" or mode == "non" and "coupé" or "je demande",
		nextT and ("prochain : " .. tostring(nextT.name) .. " " .. nextT.rank .. "/" .. nextT.max) or tostring(why))
end

local function SeenText(state)
	local parts = {}
	for key, offset in pairs(type(state.seen) == "table" and state.seen or {}) do
		parts[#parts + 1] = tostring(key) .. "=" .. tostring(offset)
	end
	table.sort(parts)
	return #parts > 0 and (", pages vues " .. table.concat(parts, " ")) or ""
end

-- État du rangement par posture, pour /iti rapport.
local function BarsReport()
	local layout = LAYOUTS[PlayerClass()]
	if not layout then
		return ""
	end
	local state = BarState()
	local n = 0
	for _ in pairs(state.owned) do
		n = n + 1
	end
	local locked = 0
	for _ in pairs(state.locked) do
		locked = locked + 1
	end
	local ok, problem = pcall(PagingProblem)
	return " (rangement : " .. tostring(state.layout or "pas demandé") .. ", " .. n .. " cases à nous, " .. locked
		.. " à toi" .. (state.layoutError and (", dernier refus : " .. tostring(state.layoutError)) or "")
		.. (ok and problem and problem ~= state.layoutError and (", " .. problem) or "") .. SeenText(state) .. ", barre " .. tostring(Num(Call(rawget(_G, "GetBonusBarOffset"))))
		.. ")"
end

function Auto.ReportLine()
	local cfg = Cfg()
	local trees = Auto.Trees()
	local parts = {}
	for tab, t in ipairs(trees or {}) do
		parts[#parts + 1] = tostring(t.name or tab) .. " " .. t.points
	end
	local skipped = {}
	for i, why in pairs(skippedSteps) do
		skipped[#skipped + 1] = i .. "=" .. why
	end
	return Auto.TalentsText() .. " · arbres " .. table.concat(parts, "/") .. (trees and (" · libres " .. trees.free) or "")
		.. (#skipped > 0 and (" · pas sautés " .. table.concat(skipped, ",")) or "")
		.. " · équipement auto " .. (cfg.equip ~= false and "oui" or "non") .. " (lié quand équipé : " .. tostring(cfg.equipBoE) .. ")"
		.. " · sacs " .. (cfg.bags ~= false and "oui" or "non")
		.. " · barres d'action " .. (cfg.actionbars ~= false and "oui" or "non") .. BarsReport()
		.. (#Auto.log > 0 and ("\n  dernières actions : " .. table.concat(Auto.log, " | ")) or "")
end
