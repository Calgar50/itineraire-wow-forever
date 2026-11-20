-- Barres rangées par forme (druide farouche, niveau 40) : humanoïde (cases 1-12), félin (73-84), ours (97-108) ;
-- même rôle par touche (Lucioles en 6 partout), sorts d'humanoïde pas sur les pages animales, barre fixe qui déborde
-- sur l'autre barre affichée, page « félin en rôdant » rangée seulement une fois vue en jeu.
CLASS_TOKEN, CLASS_NAME, LEVEL = "DRUID", "Druide", 40
NAMES = {
	[5176] = "Colère", [8921] = "Éclat lunaire", [2912] = "Feu stellaire", [339] = "Sarments", [770] = "Lucioles",
	[5185] = "Toucher guérisseur", [774] = "Récupération", [8936] = "Rétablissement", [1126] = "Marque du fauve",
	[467] = "Épines", [2782] = "Délivrance de la malédiction", [2893] = "Abolir le poison", [20484] = "Renaissance",
	[29166] = "Innervation", [2637] = "Hibernation", [16689] = "Emprise de la nature", [18960] = "Téléportation : Reflet-de-Lune",
	[437138] = "Ranimer", [16914] = "Ouragan", [740] = "Tranquillité", [2908] = "Apaiser les animaux",
	[1082] = "Griffe", [5221] = "Lambeau", [1822] = "Griffure", [1328618] = "Morsure féroce", [1079] = "Déchirure",
	[9005] = "Traquenard", [6785] = "Ravager", [8998] = "Dérobade", [1850] = "Célérité", [5215] = "Rôder",
	[5225] = "Pistage des humanoïdes", [6807] = "Mutiler", [779] = "Balayage", [99] = "Rugissement démoralisant",
	[5211] = "Sonner", [6795] = "Grondement", [22842] = "Régénération frénétique", [5229] = "Enrager",
	[5209] = "Rugissement provocateur", [1238122] = "Charge farouche", [1328617] = "Lacérer", [407995] = "Morsure primale",
	[9634] = "Forme d'ours redoutable", [5487] = "Forme d'ours", [768] = "Forme de félin", [1066] = "Forme aquatique",
	[783] = "Forme de voyage", [24858] = "Forme de sélénien", [5570] = "Essaim d'insectes", [18562] = "Prompte guérison",
	[408120] = "Croissance sauvage", [17116] = "Rapidité de la nature", [22812] = "Écorce", [8946] = "Guérison du poison",
	[21849] = "Don du fauve", [1322605] = "Puissance changeante",
}
CLASS = { 5176, 8921, 2912, 339, 770, 5185, 774, 8936, 1126, 467, 2782, 2893, 20484, 29166, 2637, 16689, 18960, 437138,
	16914, 740, 2908, 1082, 5221, 1822, 1328618, 1079, 9005, 6785, 8998, 1850, 5215, 5225, 6807, 779, 99, 5211, 6795,
	22842, 5229, 5209, 1238122, 1328617, 407995 }
FORMS = { 9634, 1066, 768, 783 }
PRED = false -- le jeu donne-t-il une page à « félin en rôdant » ?
PAGE_OF = function(form, stealthed)
	if form == 768 then return (stealthed and PRED) and 2 or 1 end
	if form == 9634 then return 3 end
	return 0
end
dofile(TESTS .. "/layout_mock.lua")

-- Avant : un peu de tout sur la page humanoïde et la page félin, une pierre de foyer sur la barre du dessus.
ACTIONS[1], ACTIONS[2], ACTIONS[3] = A("spell", 6603), A("spell", 5176), A("spell", 5185)
ACTIONS[4], ACTIONS[61] = A("item", 6948), A("item", 6948)
ACTIONS[73], ACTIONS[74] = A("spell", 1082), A("spell", 8921) -- Éclat lunaire sur la page félin : inutilisable
ACTIONS[97] = A("macro", 3)
local ns = Start()

Answer("Ranger")
assert(Printed("barres rangées par forme %(Humanoïde, Félin, Ours%)"), "message de rangement")
assert(CURSOR == nil, "curseur pas vidé")
ExpectPage(0, { 5176, 2912, 8921, 16914, 339, 770, 5185, 774, 8936, nil, nil, 29166 }, "humanoïde")
ExpectPage(72, { 1082, 5221, 1822, 1328618, 1079, 770, 1238122, 9005, 6785, 8998, 1850, 5215 }, "félin")
ExpectPage(96, { 6807, 779, 1328617, 407995, 99, 770, 1238122, 5211, 6795, 22842, 5229, 5209 }, "ours")
-- ce qui n'est pas un sort de druide : déplacé, jamais effacé (l'Attaque, la pierre, la macro)
local where = {}
for s, a in pairs(ACTIONS) do where[a[1] .. a[2]] = (where[a[1] .. a[2]] or 0) + 1 end
assert(where.spell6603 == 1 and where.item6948 == 2 and where.macro3 == 1, "objet, macro ou Attaque perdu")
-- barre fixe : sorts d'humanoïde sans touche et sorts de félin sans touche, dans l'ordre ; elle déborde à droite
local fixed = {}
for s = 61, 72 do local a = ACTIONS[s] if a and a[1] == "spell" then fixed[#fixed + 1] = NAMES[a[2]] end end
fixed = table.concat(fixed, ", ")
assert(fixed:find("^Emprise de la nature, Délivrance de la malédiction, Abolir le poison, Renaissance"),
	"barre fixe : " .. fixed)
local spill = 0
for s = 49, 60 do local a = ACTIONS[s] if a and a[1] == "spell" then spill = spill + 1 end end
assert(spill >= 1, "pas de débordement sur l'autre barre affichée")
for s = 1, 180 do
	assert(not Is(s, "spell", 8921) or s == 3, "Éclat lunaire ailleurs qu'en humanoïde : case " .. s)
end
print(table.concat(ns.Auto.LayoutLines(), "\n"))

-- Félin en rôdant : le jeu lui donne une page (85-96) : vue, puis rangée comme la page félin.
PRED = true
SetForm(768, false)
Fire("UPDATE_SHAPESHIFT_FORM")
Advance(3)
assert(not ACTIONS[85], "page de rôder remplie avant d'être vue")
SetForm(768, true)
Fire("UPDATE_STEALTH")
Advance(3)
ExpectPage(84, { 1082, 5221, 1822, 1328618, 1079, 770, 1238122, 9005, 6785, 8998, 1850, 5215 }, "félin en rôdant")
assert(ns.ReportText():find("pages vues felin=1 humanoide=0 rodeur=2"), "pages vues absentes du rapport : "
	.. tostring(ns.ReportText():match("rangement[^\n]*")))

-- Sélénien (talent du niveau 40) avec sa page (109-120) : les touches de l'humanoïde, sans les soins.
FORMS[#FORMS + 1] = 24858
Learn(24858)
local oldPage = PAGE_OF
PAGE_OF = function(form, stealthed) if form == 24858 then return 4 end return oldPage(form, stealthed) end
SetForm(24858, false)
Fire("UPDATE_SHAPESHIFT_FORM")
Advance(3)
ExpectPage(108, { 5176, 2912, 8921, 16914, 339, 770, nil, nil, nil, nil, nil, 29166 }, "sélénien")
print(ns.ReportText():match("Autonomie[^\n]*"))
print("OK barres par forme (druide)")
