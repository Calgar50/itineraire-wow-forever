# Vérifie les plans de talents d'Itinéraire (Itineraire/Autonomie.lua) contre les arbres de talents de WoW Forever
# publiés par ForeverDB (https://foreverdb.net/class/<Classe>/talents, données extraites du client du jeu).
#
#   python -I outils/plans_talents.py            (télécharge les 9 pages, rien n'est enregistré dans le dépôt)
#   python -I outils/plans_talents.py <dossier>  (lit <dossier>/<Classe>.html déjà enregistrés)
#
# Pour chaque plan : 51 points (niveaux 10 à 60), sort et nom anglais du talent présents dans l'arbre de la classe,
# bon onglet, rangs dans l'ordre et pas au-delà du maximum, palier N seulement après (N-1)*5 points dans CET arbre,
# niveau minimum du talent. Les prérequis (flèches) ne sont pas publiés : ils ne sont pas vérifiés.
# Sortie : une ligne par plan, puis les erreurs ; code de sortie 1 s'il y en a.
import html
import os
import re
import sys
import urllib.request

CLASSES = {"WARRIOR": "Warrior", "PALADIN": "Paladin", "HUNTER": "Hunter", "ROGUE": "Rogue", "PRIEST": "Priest",
           "SHAMAN": "Shaman", "MAGE": "Mage", "WARLOCK": "Warlock", "DRUID": "Druid"}
ROLES = {"tank", "melee", "ranged", "caster", "healer"}
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def page(name, folder):
    if folder:
        with open(os.path.join(folder, name + ".html"), encoding="utf-8", errors="replace") as f:
            return f.read()
    url = "https://foreverdb.net/class/%s/talents" % name
    req = urllib.request.Request(url, headers={"User-Agent": "Itineraire-plans-talents"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8", "replace")


def trees(text):
    out = {}
    sections = re.finditer(r'<h2>([^<]+) talents</h2><ul class="ssr-list">(.*?)</ul>', text, re.S)
    for tab, sec in enumerate(sections, start=1):
        for li in re.findall(r"<li>(.*?)</li>", sec.group(2), re.S):
            m = re.match(r'Tier (\d+): <a href="/spell/(\d+)">([^<]+)</a>.*?\((\d+) ranks?, level (\d+)\+\)', li, re.S)
            if m:
                tier, spell, name, mx, lvl = m.groups()
                out[int(spell)] = dict(tab=tab, tier=int(tier), name=html.unescape(name), max=int(mx), level=int(lvl))
    return out


def plans(lua):
    block = lua.split("local PLANS = {", 1)[1].split("\nAuto.PLANS", 1)[0]
    for part in re.split(r"\n\t(?=[A-Z]+ = \{\n)", "\n" + block):
        m = re.match(r"([A-Z]+) = \{", part.strip())
        if not m:
            continue
        for key, role, label, body in re.findall(r'(\w+)\s*=\s*Plan\("(\w+)",\s*"([^"]+)",\s*\{(.*?)\n\s*\}\)', part, re.S):
            steps = re.findall(r'\{\s*(\d)\s*,\s*(\d+)\s*,\s*"([^"]+)"\s*,\s*(\d+)\s*,\s*(\d+)\s*\}', body)
            yield m.group(1), key, role, label, steps


def check(db, role, steps):
    errors, points, ranks, level = [], {}, {}, 9
    if role not in ROLES:
        errors.append("rôle inconnu : " + role)
    for tab, spell, en, a, b in steps:
        tab, spell, a, b = int(tab), int(spell), int(a), int(b)
        t = db.get(spell)
        if not t:
            errors.append("%s : sort %d absent de l'arbre" % (en, spell))
            continue
        if t["tab"] != tab:
            errors.append("%s : onglet %d au lieu de %d" % (en, tab, t["tab"]))
        if t["name"] != en:
            errors.append("%s : le talent s'appelle « %s »" % (en, t["name"]))
        for rank in range(a, b + 1):
            level += 1
            if ranks.get(spell, 0) != rank - 1:
                errors.append("%s : rang %d dans le désordre" % (en, rank))
            if rank > t["max"]:
                errors.append("%s : rang %d > %d" % (en, rank, t["max"]))
            have = points.get(t["tab"], 0)
            if have < (t["tier"] - 1) * 5:
                errors.append("%s (niveau %d) : palier %d avec %d points dans l'arbre" % (en, level, t["tier"], have))
            if level < t["level"]:
                errors.append("%s : niveau %d < %d" % (en, level, t["level"]))
            ranks[spell] = rank
            points[t["tab"]] = have + 1
    if level - 9 != 51:
        errors.append("%d points au lieu de 51" % (level - 9))
    return errors, points


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else None
    with open(os.path.join(ROOT, "Itineraire", "Autonomie.lua"), encoding="utf-8") as f:
        lua = f.read()
    cache, total, bad = {}, 0, 0
    for token, key, role, label, steps in plans(lua):
        name = CLASSES.get(token)
        if not name:
            print("%s : classe inconnue" % token)
            bad += 1
            continue
        if name not in cache:
            cache[name] = trees(page(name, folder))
        errors, points = check(cache[name], role, steps)
        total += 1
        bad += len(errors)
        print("%-8s %-20s %-7s %-45s %s %s" % (token, key, role, label, [points.get(i, 0) for i in (1, 2, 3)],
                                               "OK" if not errors else "ERREURS"))
        for e in errors:
            print("    - " + e)
    print("%d plans, %d erreur(s)" % (total, bad))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
