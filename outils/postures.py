# Vérifie le rangement des barres d'Itinéraire (Itineraire/Autonomie.lua, table LAYOUTS : guerrier par posture,
# druide par forme, voleur camouflé) contre les exigences de WoW Forever publiées par ForeverDB
# (https://foreverdb.net/spell/<id> : « Requires Battle Stance, Defensive Stance. », « Requires Cat Form. »,
# « Requires Stealth. » ; données extraites du client du jeu).
#
#   python -I outils/postures.py            (télécharge les pages des sorts, rien n'est enregistré dans le dépôt)
#   python -I outils/postures.py <dossier>  (lit <dossier>/<id>.html déjà enregistrés)
#
# Pour chaque sort des tables `keys`, `static` et `only` : les pages de `only` (une valeur numérique = page permise
# par un talent, pas comptée) doivent être celles que donne ForeverDB ; un sort sans entrée dans `only` ne doit rien
# exiger. Exceptions voulues, vérifiées à la main sur ForeverDB : druide, Lucioles dans toutes les formes (note
# « Usable in caster form, Cat, Bear, Dire Bear or Moonkin Form ») et soins en humanoïde seulement (la forme de
# sélénien « prevents the use of healing spells »). Sortie : une ligne par sort ; code de sortie 1 s'il y a une erreur.
import html
import os
import re
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# texte de ForeverDB -> pages de la table `pages` de chaque classe
REQUIRES = {
    "WARRIOR": {"Battle Stance": {1}, "Defensive Stance": {2}, "Berserker Stance": {3}},
    "DRUID": {"Cat Form": {2, 3}, "Bear Form": {4}, "Dire Bear Form": {4}},
    "ROGUE": {"Stealth": {2}},
}
DRUID_ALL_FORMS = {770}  # Lucioles
DRUID_HEALS = {5185, 774, 8936, 18562, 408120, 740, 20484, 437138}


def page(spell, folder):
    if folder:
        with open(os.path.join(folder, "%d.html" % spell), encoding="utf-8", errors="replace") as f:
            return f.read()
    time.sleep(0.4)
    req = urllib.request.Request("https://foreverdb.net/spell/%d" % spell, headers={"User-Agent": "Itineraire-postures"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8", "replace")


def requirement(text, words):
    text = re.sub(r"<script.*?</script>|<style.*?</style>", "", text, flags=re.S)
    text = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", text)))
    name = text.split(" - WoW Forever")[0].split(" | ")[0].strip()
    m = re.search(r" is a \w+ \w+ in the WoW Forever client\. (.*?)"
                  r"(Changed in the live client|New in the live client|All ranks vs Classic|Rank Level|See every|Data from)",
                  text)
    desc = m.group(1) if m else ""
    found = set()
    for req in re.findall(r"Requires ([^.]*?)(?:\.|$| [A-Z][a-z]+ an? )", desc):
        for part in req.split(","):
            part = part.strip()
            if part in words:
                found |= words[part]
    return name, found


def constants(lua):
    out = {}
    for name, body in re.findall(r"^local ([A-Z]+) = \{([^}\n]*)\}", lua, re.M):
        out[name] = body
    return out


def layouts(lua):
    consts = constants(lua)
    block = lua.split("local LAYOUTS = {", 1)[1].split("\nAuto.LAYOUTS", 1)[0]
    parts = re.split(r"\n\t([A-Z]+) = \{\n", block)
    for i in range(1, len(parts), 2):
        token, body = parts[i], parts[i + 1]
        only = {}
        only_block = body.split("only = {", 1)[1].split("\n\t\t},", 1)[0]
        for spell, value in re.findall(r"\[(\d+)\] = (\{[^}]*\}|[A-Z]+)", only_block):
            body_txt = consts.get(value, value) if not value.startswith("{") else value
            only[int(spell)] = {int(k) for k, v in re.findall(r"\[(\d)\] = (true|\d+)", body_txt) if v == "true"}
        strike = consts.get("STRIKE", "")
        keys = body.split("keys = {", 1)[1].split("\n\t\t},", 1)[0].replace("STRIKE", "{ %s }" % strike)
        keys = re.sub(r"--[^\n]*", "", keys)
        static = body.split("static = {", 1)[1].split("}", 1)[0]
        spells = set(only) | {int(x) for x in re.findall(r"\b(\d{2,})\b", keys)} | {int(x) for x in re.findall(r"\d+", static)}
        yield token, only, spells


def expected(token, spell, found):
    if token == "DRUID" and spell in DRUID_ALL_FORMS:
        return {1, 2, 3, 4, 5}
    if token == "DRUID" and spell in DRUID_HEALS and not found:
        return {1}
    return found


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    folder = sys.argv[1] if len(sys.argv) > 1 else None
    with open(os.path.join(ROOT, "Itineraire", "Autonomie.lua"), encoding="utf-8") as f:
        lua = f.read()
    bad = total = 0
    for token, only, spells in layouts(lua):
        print("== " + token)
        for spell in sorted(spells):
            name, found = requirement(page(spell, folder), REQUIRES[token])
            need = expected(token, spell, found)
            mine = only.get(spell, set())
            ok = need == mine
            total += 1
            bad += 0 if ok else 1
            print("%-8d %-34s ForeverDB %-14s Itinéraire %-14s %s" % (spell, name[:34], sorted(need) or "aucune",
                                                                      sorted(mine) or "aucune", "OK" if ok else "ERREUR"))
    print("%d sorts, %d erreur(s)" % (total, bad))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
