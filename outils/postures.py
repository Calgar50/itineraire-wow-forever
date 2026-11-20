# Vérifie le rangement des barres par posture d'Itinéraire (Itineraire/Autonomie.lua, table LAYOUTS) contre les
# exigences de posture de WoW Forever publiées par ForeverDB (https://foreverdb.net/spell/<id> : « Requires Battle
# Stance, Defensive Stance. », données extraites du client du jeu).
#
#   python -I outils/postures.py            (télécharge les pages des sorts, rien n'est enregistré dans le dépôt)
#   python -I outils/postures.py <dossier>  (lit <dossier>/<id>.html déjà enregistrés)
#
# Pour chaque sort des tables `keys`, `static` et `only` du guerrier : les postures de `only` (une valeur numérique =
# posture permise par un talent, pas comptée) doivent être exactement celles de ForeverDB, et un sort sans entrée
# dans `only` ne doit demander aucune posture. Sortie : une ligne par sort ; code de sortie 1 s'il y a une erreur.
import html
import os
import re
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STANCES = {"Battle Stance": 1, "Defensive Stance": 2, "Berserker Stance": 3}


def page(spell, folder):
    if folder:
        with open(os.path.join(folder, "%d.html" % spell), encoding="utf-8", errors="replace") as f:
            return f.read()
    time.sleep(0.4)
    req = urllib.request.Request("https://foreverdb.net/spell/%d" % spell, headers={"User-Agent": "Itineraire-postures"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8", "replace")


def requirement(text):
    text = re.sub(r"<script.*?</script>|<style.*?</style>", "", text, flags=re.S)
    text = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", text)))
    name = text.split(" - WoW Forever")[0].split(" | ")[0].strip()
    m = re.search(r" is a Warrior \w+ in the WoW Forever client\. (.*?)(All ranks vs Classic|Rank Level|See every|Data from)",
                  text)
    desc = m.group(1) if m else ""
    found = set()
    for req in re.findall(r"Requires ([^.]*Stance[^.]*)\.", desc):
        for part in req.split(","):
            part = part.strip()
            if part in STANCES:
                found.add(STANCES[part])
    return name, found


def layout(lua):
    block = lua.split("local LAYOUTS = {", 1)[1].split("\nAuto.LAYOUTS", 1)[0]
    war = block.split("WARRIOR = {", 1)[1]
    only = {}
    for spell, body in re.findall(r"\[(\d+)\] = \{([^}]*)\}", war.split("only = {", 1)[1].split("\n\t\t},", 1)[0]):
        only[int(spell)] = {int(k) for k, v in re.findall(r"\[(\d)\] = (true|\d+)", body) if v == "true"}
    strike = [int(x) for x in re.findall(r"\d+", lua.split("local STRIKE = {", 1)[1].split("}", 1)[0])]
    keys = war.split("keys = {", 1)[1].split("\n\t\t},", 1)[0].replace("STRIKE", "{ %s }" % ", ".join(map(str, strike)))
    static = war.split("static = {", 1)[1].split("}", 1)[0]
    spells = set(only) | {int(x) for x in re.findall(r"\b(\d{2,})\b", keys)} | {int(x) for x in re.findall(r"\d+", static)}
    return only, spells


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    folder = sys.argv[1] if len(sys.argv) > 1 else None
    with open(os.path.join(ROOT, "Itineraire", "Autonomie.lua"), encoding="utf-8") as f:
        only, spells = layout(f.read())
    bad = 0
    for spell in sorted(spells):
        name, need = requirement(page(spell, folder))
        mine = only.get(spell, set())
        ok = need == mine
        bad += 0 if ok else 1
        print("%-8d %-40s ForeverDB %-10s Itinéraire %-10s %s" % (spell, name[:40], sorted(need) or "toutes",
                                                                 sorted(mine) or "toutes", "OK" if ok else "ERREUR"))
    print("%d sorts, %d erreur(s)" % (len(spells), bad))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
