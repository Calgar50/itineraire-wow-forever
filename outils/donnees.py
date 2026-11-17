"""Importe les données d'autres addons WoW Forever dans Itineraire/Donnees/ (versions épinglées, SHA-256 vérifié).

  Butins.lua        butins des donjons et raids (boss -> objets)    Dropdon (MIT), tiré d'All The Things (MIT)
  Objets.lua        nom / qualité / niveaux de secours des objets   Dropdon (MIT), tiré d'All The Things (MIT)
  Entrees.lua       entrées des donjons vérifiées en jeu            DonData (MIT)
  Recettes.lua      recettes de métiers (résultat, compétence)      Guildon Crafts (GPL v3 : CMaNGOS, ForeverDB, ATT)
  PNJ.lua           vendeurs, entraîneurs, rares + positions        Finddon (GPL v3 : CMaNGOS, ForeverDB, ATT)
  Marchandises.lua  ce que vendent les vendeurs                     Finddon (GPL v3 : CMaNGOS, ForeverDB)

Les tables gardent leur forme d'origine, rangées dans ns.ext (pas de collision avec le code d'Itinéraire).
Licences et mentions : LICENSE (GPL v3) et THIRD_PARTY.md.

Usage : python -I outils/donnees.py            (télécharge, vérifie, écrit)
        python -I outils/donnees.py --empreintes (affiche les SHA-256 des versions épinglées, sans rien écrire :
                                                   à recopier dans PINS après avoir changé un commit)
"""
import hashlib
import pathlib
import re
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "Itineraire" / "Donnees"
BASE = "https://raw.githubusercontent.com/WoW-Forever-Addons"

# dépôt, commit, fichier, sortie, renommages, licence, sha256 attendu
PINS = [
    ("dropdon", "d4095fbdceabbe22ec6fb83e554c3767c5258637", "Data/Drops.lua", "Butins.lua",
     {"DROPS": "BUTINS"}, "MIT (DonCoohd) ; données d'All The Things (MIT)",
     "4f0e5c4e0aea5b44d508ea8a318fcf1c299a0de10134a99aa9b5f1543dc39aa9"),
    ("dropdon", "d4095fbdceabbe22ec6fb83e554c3767c5258637", "Data/Names.lua", "Objets.lua",
     {"ITEM_FALLBACK": "OBJETS"}, "MIT (DonCoohd) ; données d'All The Things (MIT)",
     "188fcd07236d80d7cd48238e3f284aee9757c02eccb5dc305f02d11119374dd6"),
    ("dondata", "2b94e5216022d21afd27f496dc0bb06b22f5682e", "Data/Dungeon_Entrances.lua", "Entrees.lua",
     {"DUNGEON_ENTRANCES": "ENTREES"}, "MIT (DonCoohd)",
     "7066db23711333566b3546a6c8d0c665e5be8692a2fbd46e188bfaacdf388619"),
    ("guildon-crafts", "576abfcfd87a5a9162297258a44f7319e496a1a6", "Data/Recipes.lua", "Recettes.lua",
     {"RECIPES": "RECETTES"}, "GPL v3 (CMaNGOS classic-db, ForeverDB.net) ; All The Things (MIT)",
     "1c33e67ab56a27882717fd09d3955a86f8344a19d559b872a305abbd6a3c350e"),
    ("finddon", "da188b2953a8047a1e7c53098e296d7726126d6c", "Data/NPCs.lua", "PNJ.lua",
     {"NPC_COUNT": "PNJ_NB", "NPC_DATA": "PNJ"}, "GPL v3 (CMaNGOS classic-db, ForeverDB.net) ; All The Things (MIT)",
     "72093c350016ce62569ae478ea7946c2c1ea833a748ba41cbd08ef5f514e0580"),
    ("finddon", "da188b2953a8047a1e7c53098e296d7726126d6c", "Data/Goods.lua", "Marchandises.lua",
     {"GOODS_COUNT": "MARCHANDISES_NB", "GOODS_DATA": "MARCHANDISES"}, "GPL v3 (CMaNGOS classic-db, ForeverDB.net)",
     "9e3b68717f7223f0c16665bc4c08202cae977c89f2ed32b7432e36fb0e01d532"),
]

# Rien d'exécutable dans des fichiers de données : seulement des tables et des chaînes.
FORBIDDEN = re.compile(r"\b(function|require|loadstring|load|setfenv|getfenv|RunScript|_G|rawset|rawget|pcall)\b")


def fetch(repo, sha, path):
    url = f"{BASE}/{repo}/{sha}/{path}"
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        sys.exit(f"Commit invalide : {sha}")
    req = urllib.request.Request(url, headers={"User-Agent": "Itineraire-outils"})
    with urllib.request.urlopen(req, timeout=60) as r:
        if r.status != 200:
            sys.exit(f"{url} : HTTP {r.status}")
        return r.read()


def code_only(text):
    """Le texte sans les commentaires ni le contenu des chaînes (pour la vérification de sécurité)."""
    text = re.sub(r"\[(=*)\[.*?\]\1\]", '""', text, flags=re.S)  # chaînes longues [==[ ... ]==]
    text = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', text)
    text = re.sub(r"'(?:[^'\\\n]|\\.)*'", "''", text)
    text = re.sub(r"--[^\n]*", "", text)
    return text


def convert(raw, repo, sha, path, renames, licence):
    text = raw.decode("utf-8").replace("\r\n", "\n")
    head = "local _, ns = ...\n"
    if not text.count(head) == 1:
        sys.exit(f"{repo}/{path} : en-tête « local _, ns = ... » introuvable")
    for old, new in renames.items():
        n = len(re.findall(rf"\bns\.{old}\b", text))
        if n != 1:
            sys.exit(f"{repo}/{path} : ns.{old} trouvé {n} fois (attendu : 1)")
        text = re.sub(rf"\bns\.{old}\b", f"ns.ext.{new}", text)
    code = code_only(text)
    others = [m for m in re.findall(r"\bns\.(\w+)", code) if m != "ext"]
    if others:
        sys.exit(f"{repo}/{path} : références inattendues {sorted(set(others))}")
    bad = FORBIDDEN.findall(code)
    if bad:
        sys.exit(f"{repo}/{path} : mots interdits dans un fichier de données : {sorted(set(bad))}")
    banner = (
        f"-- Itinéraire : données reprises de {repo} (https://github.com/WoW-Forever-Addons/{repo}, fichier {path},\n"
        f"-- commit {sha}). Licence : {licence}. Voir LICENCE.txt et TIERS.txt.\n"
        f"-- Fichier produit par outils/donnees.py : ne pas modifier à la main.\n"
    )
    return banner + text.replace(head, head + "ns.ext = ns.ext or {}\n", 1)


def main():
    show = "--empreintes" in sys.argv
    OUT.mkdir(parents=True, exist_ok=True)
    for repo, sha, path, out, renames, licence, expected in PINS:
        raw = fetch(repo, sha, path)
        digest = hashlib.sha256(raw).hexdigest()
        if show:
            print(f"{repo}/{path}  {digest}")
            continue
        if digest != expected:
            sys.exit(f"{repo}/{path} : SHA-256 {digest} différent de l'empreinte épinglée {expected or '(aucune)'}")
        (OUT / out).write_text(convert(raw, repo, sha, path, renames, licence), encoding="utf-8", newline="\n")
        print(f"Donnees/{out}  <- {repo}/{path}  ({len(raw)} octets)")


if __name__ == "__main__":
    main()
