-- Itinéraire : réglages tout-en-un (/iti reglages, bouton … → Réglages) et assistant de départ.
-- Trois onglets : le trajet, la fenêtre, et les réglages utiles de Questie et de Shortest Path.
local _, ns = ...
local Options = {}
ns.Options = Options

local panel
local controls = {}
local pages, tabs = {}, {}

local BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 14,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local DEFAULT_UI = {
	scale = 1, alpha = 0.82, width = 360, font = "normal", compact = false, icons = true, times = true,
	summary = true, advice = true, theme = "bleu", locked = false, rows = 8,
	hideCombat = false, hideInstance = false, fade = false, fadeAlpha = 0.4, autoDisable = true,
	banner = true, bannerScale = 1, adviceCollapsed = false,
}
Options.DEFAULT_UI = DEFAULT_UI

local function S()
	return ns.db.ui
end

local function Apply()
	ns.UI.ApplySettings()
	ns.UI.UpdateVisibility()
end

-------------------------------------------------------------------------------
-- Questie et Shortest Path : leurs propres réglages, lus et écrits là où ils les rangent
-------------------------------------------------------------------------------
local Ext = {}
Options.Ext = Ext

function Ext.QuestieProfile()
	local ok, profile = pcall(function()
		return Questie.db.profile
	end)
	return ok and type(profile) == "table" and profile or nil
end

function Ext.GetQuestie(key)
	local p = Ext.QuestieProfile()
	if not p then
		return nil
	end
	if key == "autocomplete" then
		return p.autocomplete and true or false
	elseif key == "autoaccept" then
		return type(p.autoAccept) == "table" and p.autoAccept.enabled and true or false
	end
	return nil
end

function Ext.SetQuestie(key, value)
	local p = Ext.QuestieProfile()
	if not p then
		return false
	end
	if key == "autocomplete" then
		p.autocomplete = value and true or false
	elseif key == "autoaccept" and type(p.autoAccept) == "table" then
		p.autoAccept.enabled = value and true or false
	else
		return false
	end
	return true
end

function Ext.SPDB()
	local db = rawget(_G, "ShortestPathForeverDB")
	return type(db) == "table" and db or nil
end

-- « arrowTime » = le temps restant sous la flèche (réglage arrowLabel de Shortest Path).
function Ext.GetSP(key)
	local db = Ext.SPDB()
	if not db then
		return nil
	end
	if key == "arrowTime" then
		return db.arrowLabel == "both" or db.arrowLabel == "time"
	end
	if db[key] == nil then
		return true -- ces réglages sont actifs par défaut dans Shortest Path
	end
	return db[key] and true or false
end

function Ext.SetSP(key, value)
	local db = Ext.SPDB()
	if not db then
		return false
	end
	if key == "arrowTime" then
		db.arrowLabel = value and "both" or "distance"
	else
		db[key] = value and true or false
	end
	return true
end

-- Ce qu'Itinéraire conseille dans Shortest Path : trajets et flèche actifs, temps restant affiché, tracé
-- sur la minicarte et la carte, étapes suivantes visibles, pierre de foyer permise.
Ext.RECOMMENDED_SP = {
	{ key = "journey", label = "trajets activés" },
	{ key = "arrow", label = "flèche" },
	{ key = "arrowTime", label = "temps restant sous la flèche" },
	{ key = "minimapLine", label = "trajet sur la minicarte" },
	{ key = "mapLine", label = "trajet sur la carte" },
	{ key = "laterLegs", label = "étapes suivantes" },
	{ key = "useHearthstone", label = "pierre de foyer" },
}

function Ext.ApplyRecommended()
	local changed = {}
	for _, item in ipairs(Ext.RECOMMENDED_SP) do
		if Ext.GetSP(item.key) == false and Ext.SetSP(item.key, true) then
			changed[#changed + 1] = item.label
		end
	end
	return changed
end

-------------------------------------------------------------------------------
-- Petits composants (sans modèles du client, pour éviter les surprises de version)
-------------------------------------------------------------------------------
local function Header(parent, text, y)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("TOPLEFT", 16, y)
	fs:SetText(text)
	return fs
end

local function Note(parent, text, y)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	fs:SetPoint("TOPLEFT", 16, y)
	fs:SetPoint("RIGHT", -16, 0)
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
	return fs
end

-- Case à cocher branchée sur une lecture / écriture (nil à la lecture = addon absent : case grisée).
local function CheckFn(parent, label, tip, get, set, x, y)
	local c = CreateFrame("CheckButton", nil, parent)
	c:SetSize(22, 22)
	c:SetPoint("TOPLEFT", x, y)
	c:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
	c:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
	c:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
	c:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
	c:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
	c.label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
	c.label:SetText(label)
	c:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
		Apply()
	end)
	c:SetScript("OnEnter", function(self)
		if tip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(label, 1, 0.82, 0)
			GameTooltip:AddLine(tip, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	c:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	c.Refresh = function(self)
		local value = get()
		self:SetEnabled(value ~= nil)
		self.label:SetText(value == nil and (label .. " |cff888888(addon absent)|r") or label)
		self:SetChecked(value and true or false)
	end
	controls[#controls + 1] = c
	return c
end

-- Case sur un réglage de la fenêtre (ns.db.ui).
local function Check(parent, label, tip, key, x, y, onChange)
	return CheckFn(parent, label, tip, function()
		return S()[key] and true or false
	end, function(v)
		S()[key] = v
		if onChange then
			onChange()
		end
	end, x, y)
end

-- Case sur un réglage du trajet (ns.db) : recalcule le trajet.
local function PlanCheck(parent, label, tip, key, defaultOn, x, y)
	return CheckFn(parent, label, tip, function()
		if defaultOn then
			return ns.db[key] ~= false
		end
		return ns.db[key] and true or false
	end, function(v)
		ns.db[key] = v
		ns.RequestPlan("option", 0)
	end, x, y)
end

local function Slider(parent, label, key, minV, maxV, step, x, y, format, onChange)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(200, 40)
	holder:SetPoint("TOPLEFT", x, y)
	holder.label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	holder.label:SetPoint("TOPLEFT", 0, 0)
	local s = CreateFrame("Slider", nil, holder, "BackdropTemplate")
	s:SetOrientation("HORIZONTAL")
	s:SetSize(190, 16)
	s:SetPoint("TOPLEFT", 0, -16)
	s:SetBackdrop({
		bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
		edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
		tile = true, tileSize = 8, edgeSize = 8,
		insets = { left = 3, right = 3, top = 6, bottom = 6 },
	})
	s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	if s.SetObeyStepOnDrag then
		s:SetObeyStepOnDrag(true)
	end
	local function Text(v)
		holder.label:SetText(label .. " : |cffffffff" .. format(v) .. "|r")
	end
	s:SetScript("OnValueChanged", function(_, v)
		v = math.floor(v / step + 0.5) * step
		Text(v)
		if holder.ready and S()[key] ~= v then
			S()[key] = v
			if onChange then
				onChange()
			end
			Apply()
		end
	end)
	holder.Refresh = function(self)
		self.ready = false
		s:SetValue(S()[key] or minV)
		Text(S()[key] or minV)
		self.ready = true
	end
	controls[#controls + 1] = holder
	return holder
end

-- Rangée de boutons à choix unique (taille du texte, thème).
local function Choice(parent, label, key, list, x, y)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(330, 40)
	holder:SetPoint("TOPLEFT", x, y)
	holder.label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	holder.label:SetPoint("TOPLEFT", 0, 0)
	holder.label:SetText(label)
	holder.buttons = {}
	local prev
	for _, item in ipairs(list) do
		local b = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
		b:SetSize(62, 20)
		b:SetText(item.label)
		if prev then
			b:SetPoint("LEFT", prev, "RIGHT", 2, 0)
		else
			b:SetPoint("TOPLEFT", 0, -15)
		end
		b:SetScript("OnClick", function()
			S()[key] = item.key
			holder:Refresh()
			Apply()
		end)
		b.key = item.key
		holder.buttons[#holder.buttons + 1] = b
		prev = b
	end
	holder.Refresh = function(self)
		for _, b in ipairs(self.buttons) do
			if b.key == S()[key] then
				b:LockHighlight()
			else
				b:UnlockHighlight()
			end
		end
	end
	controls[#controls + 1] = holder
	return holder
end

local function Button(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

-- Texte qui se met à jour à l'ouverture (ex. : ton rythme mesuré).
local function LiveText(parent, y, fn)
	local fs = Note(parent, "", y)
	local holder = { Refresh = function()
		local ok, text = pcall(fn)
		fs:SetText(ok and text or "")
	end }
	controls[#controls + 1] = holder
	return fs
end

-------------------------------------------------------------------------------
-- Onglets
-------------------------------------------------------------------------------
local function Percent(v)
	return math.floor(v * 100 + 0.5) .. " %"
end

local function BuildRoutePage(page)
	Header(page, "Ce que le trajet comprend", -6)
	PlanCheck(page, "Finir la région où tu es avant d'en sortir (avec toutes ses quêtes)",
		"Toutes les quêtes de la région, même celles pas encore prises ; le reste passe « après la région ».",
		"regionMode", true, 16, -24)
	PlanCheck(page, "Proposer les quêtes à prendre (région, trajet, suites)",
		"Étapes « Prendre » chez les donneurs : quêtes de la région, quêtes sur ton trajet et suites de quêtes.",
		"includePickups", false, 16, -48)
	PlanCheck(page, "Inclure les donjons", "Les objectifs dans un donjon deviennent une étape « Donjon ».",
		"includeDungeons", false, 16, -72)
	PlanCheck(page, "Arrêt réparer / vendre quand il faut",
		"Équipement usé ou sacs presque pleins : arrêt chez le forgeron le plus pratique.", "includeServices", true, 16, -96)
	PlanCheck(page, "Visite au maître de classe (niveaux pairs)",
		"L'étape disparaît dès que tu ouvres la fenêtre du maître.", "includeTrainer", true, 16, -120)
	PlanCheck(page, "Conseils pierre de foyer", "À quelle étape la prendre, et où la lier si une autre auberge t'irait mieux.",
		"useHearth", true, 16, -144)

	Header(page, "À plusieurs et affichage", -176)
	CheckFn(page, "Partage de groupe (2 à 5 joueurs)",
		"Chaque joueur l'active : le chef de groupe calcule UN trajet avec les quêtes de tout le monde.", function()
			return ns.db.groupShare == true
		end, function(v)
			if v ~= (ns.db.groupShare == true) then
				ns.Group.SetEnabled(v)
			end
		end, 16, -194)
	Check(page, "Bandeau « prochaine étape » près de la flèche",
		"En gros : ce qu'il y a à faire maintenant, le temps qu'il reste et l'étape d'après. Clic : afficher / masquer la fenêtre ; glisser : le déplacer.",
		"banner", 16, -218)
	Slider(page, "Taille du bandeau", "bannerScale", 0.6, 1.6, 0.05, 20, -246, Percent)
	local place = Button(page, "Replacer le bandeau", 150, function()
		ns.UI.ResetBannerPosition()
	end)
	place:SetPoint("TOPLEFT", 226, -258)

	Header(page, "Ton rythme (appris en jouant)", -296)
	LiveText(page, -314, function()
		return (ns.PaceText() or "Pas encore de mesure : il apprend en jouant (temps par monstre, par objet, déplacements par zone).")
			.. "\nLes temps affichés sont des fourchettes : elles se resserrent au fil des mesures."
	end)
	local resetPace = Button(page, "Remettre le rythme à zéro", 190, function()
		ns.ResetPace()
		ns.Print("rythme remis à zéro : retour aux temps par défaut.")
		ns.RequestPlan("option", 0)
		Options.Refresh()
	end)
	resetPace:SetPoint("TOPLEFT", 14, -360)

	local wizardBtn = Button(page, "Assistant de départ…", 150, function()
		Options.ShowWizard()
	end)
	wizardBtn:SetPoint("TOPLEFT", 14, -400)
	local report = Button(page, "Rapport à copier…", 140, function()
		ns.ShowReport()
	end)
	report:SetPoint("LEFT", wizardBtn, "RIGHT", 6, 0)
	local turnins = Button(page, "Route des rendus", 120, function()
		ns.ToggleTurnins()
	end)
	turnins:SetPoint("LEFT", report, "RIGHT", 6, 0)
end

local function BuildWindowPage(page)
	Header(page, "Apparence", -6)
	Slider(page, "Taille", "scale", 0.6, 1.6, 0.05, 20, -26, Percent)
	Slider(page, "Opacité du fond", "alpha", 0, 1, 0.05, 210, -26, Percent)
	Slider(page, "Largeur", "width", 260, 700, 10, 20, -68, function(v)
		return v .. " px"
	end)
	Slider(page, "Étapes affichées", "rows", 3, 20, 1, 210, -68, function(v)
		return tostring(v)
	end)
	Choice(page, "Taille du texte", "font", ns.UI.FONTS, 20, -112)
	Choice(page, "Thème", "theme", ns.UI.THEMES, 20, -156)

	Header(page, "Contenu", -204)
	Check(page, "Mode compact", "Une seule ligne par étape (sans le nom des quêtes ni la zone).", "compact", 16, -222)
	Check(page, "Icônes", "L'icône du type d'étape (rendre, tuer, ramasser…).", "icons", 200, -222)
	Check(page, "Temps de trajet", "La durée du trajet jusqu'à chaque étape, à droite.", "times", 16, -246)
	Check(page, "Résumé", "La ligne « 32 étapes · 55–70 min · ~10 800 XP ».", "summary", 200, -246)
	Check(page, "Bloc « À savoir »", "Les quêtes sans position, JcJ, échouées… sous les étapes.", "advice", 16, -270)
	Check(page, "« À savoir » replié", "Une seule ligne « À savoir (5) » : clic dessus pour déplier.", "adviceCollapsed", 200, -270)
	Check(page, "Désactiver les autres guides", "Au chargement, désactive RestedXP, Zygor, Guidelime, Adventure Guide… qui se disputeraient la flèche avec Itinéraire (effet au prochain /reload).", "autoDisable", 16, -294)

	Header(page, "Comportement", -326)
	Check(page, "Verrouiller la position et la largeur", "Empêche de déplacer ou d'élargir la fenêtre (et le bandeau) par erreur.", "locked", 16, -344)
	Check(page, "Masquer en combat", "La fenêtre et le bandeau disparaissent pendant les combats et reviennent après.", "hideCombat", 16, -368)
	Check(page, "Masquer en donjon", "La fenêtre et le bandeau disparaissent dans les donjons et champs de bataille.", "hideInstance", 200, -368)
	Check(page, "Estomper quand la souris n'est pas dessus", "La fenêtre devient transparente tant que tu ne la survoles pas.", "fade", 16, -392)
	Slider(page, "Opacité estompée", "fadeAlpha", 0.1, 0.9, 0.05, 20, -418, Percent)

	Note(page, "Astuces : la poignée en bas à droite de la fenêtre change sa largeur ; la molette fait défiler les étapes. Raccourcis clavier : Échap > Options > Raccourcis > AddOns > Itinéraire.", -462)
end

local function BuildAddonsPage(page)
	Header(page, "Questie", -6)
	CheckFn(page, "Rendre les quêtes terminées automatiquement",
		"Réglage de Questie (onglet Auto) : la quête se rend dès que tu parles au PNJ. Garde MAJ enfoncée pour choisir toi-même.",
		function()
			return Ext.GetQuestie("autocomplete")
		end, function(v)
			Ext.SetQuestie("autocomplete", v)
		end, 16, -24)
	CheckFn(page, "Accepter les quêtes automatiquement",
		"Réglage de Questie (onglet Auto) : les quêtes proposées par un PNJ sont acceptées d'office. Garde MAJ enfoncée pour choisir.",
		function()
			return Ext.GetQuestie("autoaccept")
		end, function(v)
			Ext.SetQuestie("autoaccept", v)
		end, 16, -48)

	Header(page, "Shortest Path (la flèche)", -82)
	local items = {
		{ "journey", "Trajets activés (indispensable à Itinéraire)", "Sans les trajets, Shortest Path refuse le trajet d'Itinéraire." },
		{ "arrow", "Flèche de direction", "La flèche à l'écran qui montre où aller." },
		{ "arrowTime", "Temps restant sous la flèche", "Sous la flèche : la distance ET le temps qu'il reste." },
		{ "minimapLine", "Trajet en points sur la minicarte", "Le tracé du chemin sur la minicarte." },
		{ "mapLine", "Trajet sur la carte du monde", "Le tracé du chemin sur la grande carte." },
		{ "laterLegs", "Étapes suivantes (en pâle) sur la carte", "Montre la suite du trajet, pas seulement l'étape en cours." },
		{ "useHearthstone", "Utiliser la pierre de foyer dans les trajets", "Shortest Path peut te faire prendre la pierre de foyer quand c'est plus rapide." },
	}
	for k, item in ipairs(items) do
		local key = item[1]
		CheckFn(page, item[2], item[3] .. " (réglage de Shortest Path)", function()
			return Ext.GetSP(key)
		end, function(v)
			Ext.SetSP(key, v)
		end, 16, -100 - (k - 1) * 24)
	end
	Note(page, "Ce sont les réglages de Questie et de Shortest Path eux-mêmes (les mêmes que dans leurs menus). Certains ne s'appliquent qu'après « Recharger l'interface ».", -276)
	local recommended = Button(page, "Réglages conseillés", 160, function()
		local changed = Ext.ApplyRecommended()
		Options.Refresh()
		if #changed > 0 then
			ns.Print("Shortest Path : " .. table.concat(changed, ", ") .. " activé(s). Recharge l'interface pour que tout prenne effet.")
		else
			ns.Print("Shortest Path est déjà réglé comme conseillé.")
		end
	end)
	recommended:SetPoint("TOPLEFT", 14, -320)
	local reload = Button(page, "Recharger l'interface", 160, function()
		if ReloadUI then
			ReloadUI()
		end
	end)
	reload:SetPoint("LEFT", recommended, "RIGHT", 6, 0)

	Header(page, "Mises à jour", -360)
	LiveText(page, -378, function()
		return "Itinéraire " .. tostring(ns.AddonVersion and ns.AddonVersion("Itineraire") or "?") .. " · " .. ns.InstallerText()
			.. "\nPour tout garder à jour tout seul (Itinéraire, Questie, Shortest Path) : relance Installer-Itineraire.cmd"
			.. " et réponds « o » à « Activer la mise à jour automatique ». Les mises à jour se font quand WoW est fermé"
			.. " et que l'ordinateur est inutilisé ; elles comptent au lancement suivant."
			.. "\nPaquet et nouveautés : " .. ns.HOME
	end)
end

-- Équipement : récompenses de quête, rôle, améliorations.
local function RoleButtons(parent, y)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(390, 24)
	holder:SetPoint("TOPLEFT", 16, y)
	holder.buttons = {}
	local prev
	for _, r in ipairs(ns.Gear.ROLES or {}) do
		local b = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
		b:SetSize(r.key == "auto" and 52 or 62, 20)
		b:SetText(r.label)
		if prev then
			b:SetPoint("LEFT", prev, "RIGHT", 2, 0)
		else
			b:SetPoint("TOPLEFT", 0, 0)
		end
		b:SetScript("OnClick", function()
			ns.Gear.Config().role = r.key
			ns.Gear.ResetWorn()
			ns.Gear.Rescan()
			Options.Refresh()
		end)
		b.key = r.key
		holder.buttons[#holder.buttons + 1] = b
		prev = b
	end
	holder.Refresh = function(self)
		local current = ns.char and ns.char.gear and ns.char.gear.role or "auto"
		for _, b in ipairs(self.buttons) do
			if b.key == current then
				b:LockHighlight()
			else
				b:UnlockHighlight()
			end
		end
	end
	controls[#controls + 1] = holder
	return holder
end

local function BuildGearPage(page)
	if ns.gearMissing or not ns.Gear.Config then
		Note(page, "L'équipement arrive avec de nouveaux fichiers : quitte et relance complètement WoW.", -10)
		return
	end
	Header(page, "Récompenses de quête", -6)
	CheckFn(page, "Conseiller la meilleure récompense au rendu d'une quête",
		"Quand une quête propose plusieurs récompenses : la meilleure pour ton rôle est encadrée (sinon la plus chère à revendre), avec un message.",
		function()
			return ns.Gear.Config().rewardAdvice ~= false
		end, function(v)
			ns.Gear.Config().rewardAdvice = v
		end, 16, -24)
	CheckFn(page, "La présélectionner (tu cliques toi-même sur « Terminer »)",
		"La récompense conseillée est déjà choisie dans la fenêtre de la quête ; rien n'est validé à ta place.",
		function()
			return ns.Gear.Config().preselect ~= false
		end, function(v)
			ns.Gear.Config().preselect = v
		end, 16, -48)

	Header(page, "Ton rôle (pour noter les objets)", -82)
	RoleButtons(page, -100)
	LiveText(page, -128, function()
		local role, why = ns.Gear.Role()
		return "Rôle utilisé : " .. (ns.Gear.ROLE_LABEL[role] or role) .. " (" .. why .. "). Auto = d'après l'arbre de talents le plus rempli."
	end)

	Header(page, "Améliorations (récompenses, vendeurs, butins)", -170)
	LiveText(page, -188, function()
		return ns.Gear.ReportLine()
	end)
	local open = Button(page, "Ouvrir la fenêtre Équipement", 200, function()
		ns.GearUI.Toggle(true)
	end)
	open:SetPoint("TOPLEFT", 14, -222)
	local rescan = Button(page, "Relancer l'analyse", 140, function()
		ns.Gear.ResetWorn()
		ns.Gear.Rescan()
		Options.Refresh()
	end)
	rescan:SetPoint("LEFT", open, "RIGHT", 6, 0)
	Note(page, "Chaque objet est noté avec ses vraies caractéristiques (celles du jeu, à jour) selon ton rôle, puis comparé à ce "
		.. "que tu portes. Les sources viennent de la base de Questie : récompenses de quêtes (seulement celles que ta classe "
		.. "et ta race peuvent faire), vendeurs, PNJ et coffres qui le font tomber. Les taux de butin ne sont pas connus.\n\n"
		.. "Dans la fenêtre Équipement, « Y aller » ajoute la source au trajet (la flèche t'y emmène) ; l'objectif disparaît "
		.. "dès que l'objet est dans tes sacs. /iti equipement l'ouvre aussi.", -262)
end

local PAGES = {
	{ key = "trajet", label = "Trajet", build = BuildRoutePage, width = 72 },
	{ key = "fenetre", label = "Fenêtre", build = BuildWindowPage, width = 78 },
	{ key = "equipement", label = "Équipement", build = BuildGearPage, width = 96 },
	{ key = "addons", label = "Questie & flèche", build = BuildAddonsPage, width = 124 },
}

local function ShowPage(key)
	for _, def in ipairs(PAGES) do
		local on = def.key == key
		pages[def.key]:SetShown(on)
		if on then
			tabs[def.key]:LockHighlight()
		else
			tabs[def.key]:UnlockHighlight()
		end
	end
	Options.page = key
end

local function Build()
	panel = CreateFrame("Frame", "ItineraireOptions", UIParent, "BackdropTemplate")
	panel:SetSize(420, 600)
	panel:SetPoint("CENTER")
	panel:SetBackdrop(BACKDROP)
	panel:SetBackdropColor(0.03, 0.03, 0.06, 0.96)
	panel:SetBackdropBorderColor(0.4, 0.6, 0.9, 1)
	panel:SetFrameStrata("DIALOG")
	panel:SetClampedToScreen(true)
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
	panel:Hide()
	tinsert(UISpecialFrames, "ItineraireOptions")

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -12)
	title:SetText("Itinéraire — réglages")
	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	local prev
	for _, def in ipairs(PAGES) do
		local tab = Button(panel, def.label, def.width or 90, function()
			ShowPage(def.key)
		end)
		if prev then
			tab:SetPoint("LEFT", prev, "RIGHT", 4, 0)
		else
			tab:SetPoint("TOPLEFT", 16, -36)
		end
		tabs[def.key] = tab
		prev = tab
		local page = CreateFrame("Frame", nil, panel)
		page:SetPoint("TOPLEFT", 0, -64)
		page:SetPoint("BOTTOMRIGHT", 0, 44)
		pages[def.key] = page
		def.build(page)
	end

	local reset = Button(panel, "Tout réinitialiser", 130, function()
		local keep = { point = S().point, rel = S().rel, x = S().x, y = S().y, shown = true, bannerPos = S().bannerPos }
		wipe(ns.db.ui)
		for k, v in pairs(DEFAULT_UI) do
			ns.db.ui[k] = v
		end
		for k, v in pairs(keep) do
			ns.db.ui[k] = v
		end
		Options.Refresh()
		Apply()
	end)
	reset:SetPoint("BOTTOMLEFT", 14, 12)
	local recenter = Button(panel, "Replacer la fenêtre", 140, function()
		ns.UI.ResetPosition()
	end)
	recenter:SetPoint("LEFT", reset, "RIGHT", 6, 0)
	local done = Button(panel, "Fermer", 80, function()
		panel:Hide()
	end)
	done:SetPoint("BOTTOMRIGHT", -14, 12)

	panel:SetScript("OnShow", Options.Refresh)
	ShowPage("fenetre")
end

function Options.Refresh()
	for _, c in ipairs(controls) do
		c:Refresh()
	end
end

-- `page` : « trajet », « fenetre », « equipement » ou « addons » (sinon l'onglet précédent).
function Options.Toggle(show, page)
	if not panel then
		Build()
	end
	if show == nil then
		show = not panel:IsShown()
	end
	if show then
		if page and pages[page] then
			ShowPage(page)
		end
		panel:Show()
		Options.Refresh()
	else
		panel:Hide()
	end
end

-------------------------------------------------------------------------------
-- Assistant de départ : 5 questions, une fois (/iti assistant pour le rouvrir)
-------------------------------------------------------------------------------
local wizard

local function WizardRow(parent, y, question, options)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(440, 46)
	holder:SetPoint("TOPLEFT", 18, y)
	holder.label = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	holder.label:SetPoint("TOPLEFT", 0, 0)
	holder.label:SetText(question)
	holder.buttons = {}
	local prev
	for i, opt in ipairs(options) do
		local b = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
		b:SetSize(opt.width or 210, 22)
		b:SetText(opt.label)
		if prev then
			b:SetPoint("LEFT", prev, "RIGHT", 6, 0)
		else
			b:SetPoint("TOPLEFT", 0, -18)
		end
		b.value, b.labelText = opt.value, opt.label
		b:SetScript("OnClick", function()
			holder:Select(opt.value)
		end)
		if opt.tip then
			b:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:AddLine(opt.tip, 1, 1, 1, true)
				GameTooltip:Show()
			end)
			b:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)
		end
		holder.buttons[i] = b
		prev = b
	end
	function holder:Select(value)
		self.value = value
		for _, b in ipairs(self.buttons) do
			if b.value == value then
				b:LockHighlight()
				b:SetText("|cff33ff33" .. b.labelText .. "|r")
			else
				b:UnlockHighlight()
				b:SetText(b.labelText)
			end
		end
	end
	function holder:SetAvailable(on)
		for _, b in ipairs(self.buttons) do
			b:SetEnabled(on)
		end
	end
	return holder
end

local function ApplyWizard()
	local r = wizard.rows
	local group = r.group.value == "groupe"
	if group ~= (ns.db.groupShare == true) then
		ns.Group.SetEnabled(group)
	end
	ns.db.regionMode = r.order.value == "region"
	if r.auto.available then
		Ext.SetQuestie("autocomplete", r.auto.value == "oui")
	end
	if r.window.value == "legere" then
		S().rows, S().adviceCollapsed = 3, true
	else
		S().rows, S().adviceCollapsed = 8, false
	end
	S().banner = true
	S().shown = true
	local changed = r.sp.value == "oui" and Ext.ApplyRecommended() or {}
	ns.db.wizardDone = true
	wizard:Hide()
	ns.UI.ApplySettings()
	ns.UI.UpdateVisibility()
	ns.RequestPlan("assistant", 0)
	ns.Print("c'est réglé ! " .. (group and "Partage de groupe activé" or "Tu joues seul")
		.. (ns.db.regionMode and ", région d'abord" or ", tout au plus court")
		.. (r.window.value == "legere" and ", fenêtre légère + bandeau" or ", fenêtre complète + bandeau")
		.. ". Tout se change dans … > Réglages.")
	if #changed > 0 then
		ns.Print("Shortest Path : " .. table.concat(changed, ", ") .. " activé(s). Tape |cffffff00/reload|r pour que tout prenne effet.")
	end
end

function Options.ShowWizard()
	if not wizard then
		wizard = CreateFrame("Frame", "ItineraireWizard", UIParent, "BackdropTemplate")
		wizard:SetSize(480, 400)
		wizard:SetPoint("CENTER", 0, 40)
		wizard:SetBackdrop(BACKDROP)
		wizard:SetBackdropColor(0.03, 0.03, 0.06, 0.97)
		wizard:SetBackdropBorderColor(1, 0.82, 0, 1)
		wizard:SetFrameStrata("DIALOG")
		wizard:SetClampedToScreen(true)
		wizard:SetMovable(true)
		wizard:EnableMouse(true)
		wizard:RegisterForDrag("LeftButton")
		wizard:SetScript("OnDragStart", wizard.StartMoving)
		wizard:SetScript("OnDragStop", wizard.StopMovingOrSizing)
		local title = wizard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		title:SetPoint("TOP", 0, -14)
		title:SetText("Bienvenue dans Itinéraire !")
		local intro = wizard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		intro:SetPoint("TOPLEFT", 18, -40)
		intro:SetPoint("RIGHT", -18, 0)
		intro:SetJustifyH("LEFT")
		intro:SetText("5 réponses pour régler l'essentiel (le choix conseillé est déjà sélectionné). Tout se change ensuite dans le bouton … > Réglages.")
		wizard.rows = {
			group = WizardRow(wizard, -74, "Tu joues…", {
				{ label = "Seul", value = "solo", tip = "Ton propre trajet." },
				{ label = "En groupe (2 à 5)", value = "groupe", tip = "Chaque joueur active le partage : le chef de groupe calcule un trajet avec les quêtes de tout le monde." },
			}),
			order = WizardRow(wizard, -124, "Dans quel ordre ?", {
				{ label = "Finir ma région d'abord", value = "region", tip = "Conseillé : toutes les quêtes de la région où tu es (même pas encore prises), puis la suite." },
				{ label = "Tout mon journal au plus court", value = "tout", tip = "L'ordre le plus court à travers tout ton journal, toutes zones confondues." },
			}),
			auto = WizardRow(wizard, -174, "Rendre les quêtes automatiquement (Questie) ?", {
				{ label = "Oui", value = "oui", tip = "Conseillé : une quête terminée se rend dès que tu parles au PNJ (MAJ enfoncée pour choisir toi-même)." },
				{ label = "Non, je clique moi-même", value = "non" },
			}),
			window = WizardRow(wizard, -224, "Quelle fenêtre ?", {
				{ label = "Légère : bandeau + 3 étapes", value = "legere", tip = "Conseillé : un bandeau près de la flèche dit quoi faire ; la fenêtre ne montre que les 3 prochaines étapes (molette ou « Voir plus » pour la suite)." },
				{ label = "Complète : 8 étapes", value = "complete", tip = "La fenêtre avec 8 étapes et le bloc « À savoir » déplié, plus le bandeau." },
			}),
			sp = WizardRow(wizard, -274, "Régler la flèche de Shortest Path comme conseillé ?", {
				{ label = "Oui", value = "oui", tip = "Active (si ce n'est pas déjà fait) : trajets, flèche, temps restant sous la flèche, tracé sur la minicarte et la carte, étapes suivantes, pierre de foyer." },
				{ label = "Non, ne touche à rien", value = "non" },
			}),
		}
		local go = Button(wizard, "C'est parti !", 160, ApplyWizard)
		go:SetPoint("BOTTOMRIGHT", -16, 14)
		local later = Button(wizard, "Plus tard", 110, function()
			ns.session.wizardLater = true
			wizard:Hide()
			ns.Print("assistant fermé : |cffffff00/iti assistant|r pour le rouvrir.")
		end)
		later:SetPoint("RIGHT", go, "LEFT", -8, 0)
	end
	local r = wizard.rows
	r.group:Select(ns.db.groupShare and "groupe" or "solo")
	r.order:Select(ns.db.regionMode == false and "tout" or "region")
	r.auto.available = Ext.QuestieProfile() ~= nil
	r.auto:SetAvailable(r.auto.available)
	r.auto:Select("oui")
	r.window:Select("legere")
	r.sp.available = Ext.SPDB() ~= nil
	r.sp:SetAvailable(r.sp.available)
	r.sp:Select(r.sp.available and "oui" or "non")
	wizard:Show()
end

-- Entrée dans Échap → Options → AddOns (si le client le permet), avec un bouton qui ouvre la fenêtre.
function Options.RegisterSettings()
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
		return
	end
	pcall(function()
		local canvas = CreateFrame("Frame")
		local t = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		t:SetPoint("TOPLEFT", 16, -16)
		t:SetText("Itinéraire")
		local d = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -8)
		d:SetText("Trajet le plus court à travers ton journal de quêtes.")
		local b = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
		b:SetSize(220, 24)
		b:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -12)
		b:SetText("Ouvrir les réglages")
		b:SetScript("OnClick", function()
			if SettingsPanel and SettingsPanel.Close then
				pcall(SettingsPanel.Close, SettingsPanel)
			end
			Options.Toggle(true, "trajet")
		end)
		local category = Settings.RegisterCanvasLayoutCategory(canvas, "Itinéraire")
		Settings.RegisterAddOnCategory(category)
	end)
end
