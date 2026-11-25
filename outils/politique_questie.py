"""Reprend deux listes de politique de Questie (GPL v3) pour le moteur interne d'Itinéraire, évaluées pour WoW Forever.

  CACHEES  quêtes que Questie ne propose jamais (doublons, retirées, tests…)
           = QuestieQuestBlacklist:Load() filtrée comme BlacklistFilter.filterExpansion (WoW Forever = contenu « Era »),
           + toutes les quêtes d'événements saisonniers (Holidays/quests/*.lua : Questie ne les montre que pendant
           l'événement ; Itinéraire, pour monter, ne les propose jamais)
  TAGS     étiquettes corrigées (élite, donjon, raid, JcJ) quand l'API du jeu se trompe
           = _QuestieDB.questTagCorrections (questTagInfoCorrections.lua)

Les fichiers de Questie sont exécutés dans lupa avec des remplaçants minimaux (aucun accès disque ni système depuis le
Lua), puis les deux tables sont écrites dans Itineraire/Donnees/Politique.lua avec la version de Questie et le SHA-256
des fichiers lus. À relancer après une mise à jour de Questie qui touche ces listes.

Usage : <python du venv lupa> -I outils/politique_questie.py [dossier de l'addon Questie]
"""
import hashlib
import pathlib
import re
import sys

import lupa

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "Itineraire" / "Donnees" / "Politique.lua"
DEFAULT = pathlib.Path(r"C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\Questie")
FILES = ["Database/Corrections/QuestieQuestBlacklist.lua", "Database/Corrections/questTagInfoCorrections.lua"]

STUBS = r"""
local modules = {}
local function Module(name)
  local m = modules[name]
  if not m then m = { private = {} }; modules[name] = m end
  return m
end
QuestieLoader = { ImportModule = function(_, n) return Module(n) end, CreateModule = function(_, n) return Module(n) end }
-- WoW Forever = contenu « Era » (Expansions.lua de Questie : WOW_PROJECT 18 -> 1)
local e = Module("Expansions")
e.Era, e.Classic, e.Tbc, e.Wotlk, e.Cata, e.MoP, e.Current = 1, 1, 2, 3, 4, 5, 1
Module("ContentPhases").activePhases = {}
Questie = { IsForever = true, IsSoD = false, IsTBC = false, IsMoP = false, IsSoM = false, IsTitanReforged = false,
  IsChinaRegion = false, IsAnniversaryEra = false, IsAnniversaryHardcore = false, IsHardcore = false,
  DEBUG_DEVELOP = 1, DEBUG_INFO = 2, DEBUG_CRITICAL = 3, Debug = function() end }
setmetatable(Module("l10n"), { __call = function(_, s) return s end })
Module("QuestieDB").private = Module("QuestieDB").private or {}
Module("QuestieEvent").eventQuests = {}
MODULES = modules
"""


def main():
    src = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    toc = (src / "Questie_Forever.toc").read_text(encoding="utf-8", errors="replace")
    version = re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    for name in ("io", "os", "package", "dofile", "loadfile", "require"):
        g[name] = None
    lua.execute(STUBS)
    sums = []
    for rel in FILES:
        data = (src / rel).read_bytes()
        sums.append((rel, hashlib.sha256(data).hexdigest()))
        lua.execute(data.decode("utf-8"))
    hidden = lua.eval("MODULES.QuestieQuestBlacklist:Load()")
    cachees = set(int(k) for k, v in hidden.items() if v not in (False, None))
    events = 0
    for f in sorted((src / "Database/Corrections/Holidays/quests").glob("*.lua")):
        data = f.read_bytes()
        sums.append((f.relative_to(src).as_posix(), hashlib.sha256(data).hexdigest()))
        lua.execute(data.decode("utf-8"))
    for q in lua.eval("MODULES.QuestieEvent.eventQuests").values():
        if q[2] is not None:
            cachees.add(int(q[2]))
            events += 1
    cachees = sorted(cachees)
    lua.eval("MODULES.QuestieDB.private.InitializeQuestTagInfoCorrections")()
    corr = lua.eval("MODULES.QuestieDB.private.questTagCorrections")
    tags = sorted((int(k), int(v[1])) for k, v in corr.items() if v is not None and v[1] is not None)

    out = ["-- Itinéraire : listes de politique reprises de Questie " + version + " (GPL v3, github.com/Questie/Questie),",
           "-- évaluées pour WoW Forever (contenu « Era ») par outils/politique_questie.py : ne pas modifier à la main.",
           "-- Fichiers lus (SHA-256) :"]
    out += ["--   %s %s" % (rel, h) for rel, h in sums]
    out += ["local _, ns = ...", "ns.ext = ns.ext or {}",
            "-- quêtes que Questie ne propose jamais",
            "local c = {}", "for id in (\"" + " ".join(str(i) for i in cachees) + "\"):gmatch(\"%d+\") do",
            "\tc[tonumber(id)] = true", "end", "ns.ext.CACHEES = c",
            "-- étiquettes corrigées : 1 élite, 41 JcJ, 62 raid, 81 donjon…",
            "ns.ext.TAGS = {"]
    line = "\t"
    for qid, tag in tags:
        item = "[%d] = %d, " % (qid, tag)
        if len(line) + len(item) > 118:
            out.append(line.rstrip())
            line = "\t"
        line += item
    if line.strip():
        out.append(line.rstrip())
    out.append("}")
    text = "\n".join(out) + "\n"
    OUT.write_bytes(text.encode("utf-8"))
    print("Questie", version, ":", len(cachees), "quêtes cachées (dont", events, "d'événements),", len(tags),
          "étiquettes ->", OUT)


if __name__ == "__main__":
    main()
