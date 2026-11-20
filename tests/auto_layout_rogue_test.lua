-- Barres rangées pour le camouflage (voleur, niveau 30, dague en main droite) : page normale (cases 1-12) et page
-- camouflée (73-84) avec le même rôle par touche ; Camouflage (une forme) posé à son plus haut rang ; la page
-- camouflée ne compte pas pour la barre fixe ; si le jeu ne change pas de page en camouflage, les techniques de
-- camouflage passent sur la barre fixe.
CLASS_TOKEN, CLASS_NAME, LEVEL = "ROGUE", "Voleur", 30
NAMES = {
	[1752] = "Attaque pernicieuse", [2098] = "Éviscération", [53] = "Attaque sournoise", [921] = "Vol à la tire",
	[1776] = "Suriner", [5277] = "Évasion", [6770] = "Assommer", [5171] = "Débiter", [2983] = "Sprint",
	[1766] = "Coup de pied", [8647] = "Exposer l'armure", [703] = "Garrot", [1966] = "Feinte", [8676] = "Embuscade",
	[1943] = "Rupture", [1725] = "Distraction", [1856] = "Disparition", [1329283] = "Surinage", [1833] = "Coup bas",
	[408] = "Aiguillon perfide", [1842] = "Désarmement de piège", [14183] = "Préméditation", [1784] = "Camouflage",
	[1785] = "Camouflage", [399956] = "Mutilation", [16511] = "Hémorragie", [14278] = "Frappe fantomatique",
	[14251] = "Riposte", [2094] = "Cécité", [14177] = "Sang froid", [13877] = "Déluge de lames",
	[13750] = "Poussée d'adrénaline", [14185] = "Préparation", [1316709] = "Marque de mort",
}
CLASS = { 1752, 2098, 53, 921, 1776, 5277, 6770, 5171, 2983, 1766, 8647, 703, 1966, 8676, 1943, 1725, 1856, 1329283,
	1833, 408, 1842, 14183 }
FORMS = { 1785 } -- Camouflage (rang 2) : une « forme » de la barre des postures
PAGES = true -- le jeu donne-t-il une page au camouflage ?
PAGE_OF = function(_, stealthed) return (stealthed and PAGES) and 1 or 0 end
dofile(TESTS .. "/layout_mock.lua")
WEAPONS[16] = { 2, 15 } -- dague en main droite
WEAPONS[17] = { 2, 7 } -- épée en main gauche
ACTIONS[1], ACTIONS[2] = A("spell", 1752), A("item", 5140) -- poudre éclipsante
ACTIONS[73] = A("spell", 1785)
local ns = Start()

Answer("Ranger")
assert(Printed("barres rangées par camouflage %(Normal, Camouflé%)"), "message de rangement")
ExpectPage(0, { 1752, 53, 2098, 5171, 1943, 1766, 1776, 408, 8647, 5277, 2983, 1856 }, "normale")
ExpectPage(72, { 1833, 8676, 2098, 5171, 703, 1766, 6770, 921, 14183, 1725, 2983, 1785 }, "camouflée")
Expect(61, "spell", 1785, "Camouflage (rang 2) en tête de la barre fixe")
local fixed = {}
for s = 61, 72 do local a = ACTIONS[s] if a and a[1] == "spell" then fixed[NAMES[a[2]]] = true end end
assert(fixed["Distraction"] and fixed["Préméditation"] and fixed["Feinte"], "barre fixe incomplète")
assert(not fixed["Attaque sournoise"] and not fixed["Exposer l'armure"] and not fixed["Coup bas"],
	"la page camouflée (passagère) a envoyé des sorts sur la barre fixe")
local item = false
for _, a in pairs(ACTIONS) do item = item or (a[1] == "item" and a[2] == 5140) end
assert(item, "poudre éclipsante perdue")
print(table.concat(ns.Auto.LayoutLines(), "\n"))

-- Le jeu ne change pas de page en camouflage (vu en jeu) : la page camouflée disparaît, ses techniques (Coup bas…)
-- vont sur la barre fixe.
PAGES = false
SetForm(1785, true)
Fire("UPDATE_STEALTH")
Advance(3)
local onFixed = {}
for s = 49, 72 do local a = ACTIONS[s] if a and a[1] == "spell" then onFixed[NAMES[a[2]]] = true end end
assert(onFixed["Coup bas"] and onFixed["Embuscade"] and onFixed["Garrot"], "techniques de camouflage pas sur la barre fixe")
assert(ns.ReportText():find("camouflage=0"), "page vue absente du rapport")
print("OK barres pour le camouflage (voleur)")
