# Lanceur des tests qui chargent la VRAIE base QuestieDB (Forever, mode baked) hors du jeu.
# Même ligne de commande que run_lua.py : run_lua_vraie.py <test.lua> CLE=valeur...
# En plus : QUESTIEDB=<dossier de l'addon> (par défaut, celui de l'installation WoW).
# L'addon est lu sur place, en lecture seule ; ses .lua tournent dans un Lua bridé
# (pas de fichiers, pas de commandes système, pas d'accès à Python).
import base64
import os
import re
import sys
import zlib

import lupa.lua51 as L

QUESTIEDB_DEFAUT = r"C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\QuestieDB"
SAVEUR_TOC = "_Forever.toc"
TAILLE_MAX_LUA = 64 * 1024 * 1024        # aucun .lua de l'addon n'approche cette taille
TAILLE_MAX_DECOMPRESSE = 256 * 1024 * 1024  # garde-fou contre une bombe zlib

args = {}
for kv in sys.argv[2:]:
    k, v = kv.split("=", 1)
    args[k] = v
args.setdefault("QUESTIEDB", QUESTIEDB_DEFAUT)


def reel(chemin):
    return os.path.normcase(os.path.realpath(chemin))


# Dossiers lisibles : les tests, l'addon testé, la vraie base. Rien d'autre.
racines = [reel(os.path.dirname(os.path.abspath(sys.argv[1])))]
for cle in ("TESTS", "ADDON_DIR", "QUESTIEDB"):
    if cle in args:
        racines.append(reel(args[cle]))


def autorise(chemin):
    """Chemin résolu s'il reste dans une racine autorisée, sinon None."""
    if any(part == ".." for part in re.split(r"[\\/]", chemin)):
        return None
    r = reel(chemin)
    for racine in racines:
        try:
            if os.path.commonpath([r, racine]) == racine:
                return r
        except ValueError:  # autre lecteur
            pass
    return None


def texte(b):
    return b.decode("utf-8") if isinstance(b, bytes) else str(b)


def sans_exception(fn):
    # Une erreur Python ne remonte jamais telle quelle dans Lua : (nil, message) à la place.
    def enveloppe(*a):
        try:
            return fn(*a)
        except Exception as e:  # noqa: BLE001 - le message part vers Lua qui lèvera l'erreur
            return None, ("%s: %s" % (type(e).__name__, e)).encode("utf-8", "replace")
    return enveloppe


@sans_exception
def lire(chemin):
    chemin = texte(chemin)
    r = autorise(chemin)
    if r is None or not r.endswith(".lua"):
        return None, ("lecture refusée : " + chemin).encode("utf-8")
    if os.path.getsize(r) > TAILLE_MAX_LUA:
        return None, ("fichier trop gros : " + chemin).encode("utf-8")
    with open(r, "rb") as f:
        return f.read()


metas = {}  # nom d'addon en minuscules -> {clé en minuscules: valeur brute}


@sans_exception
def ouvrir_toc(dossier):
    """Lit <dossier>/<nom>_Forever.toc : retourne nom, fichiers .lua séparés par \\n, ou false si absent."""
    dossier = texte(dossier)
    r = autorise(dossier)
    if r is None:
        return None, ("dossier refusé : " + dossier).encode("utf-8")
    nom = os.path.basename(os.path.realpath(dossier))
    toc = os.path.join(r, nom + SAVEUR_TOC)
    if not os.path.isfile(toc):
        return False
    meta, fichiers = {}, []
    with open(toc, "rb") as f:
        contenu = f.read()
    if contenu.startswith(b"\xef\xbb\xbf"):
        contenu = contenu[3:]
    for ligne in contenu.split(b"\n"):
        ligne = ligne.strip()
        if ligne.startswith(b"##"):
            cle, _, valeur = ligne[2:].partition(b":")
            meta[cle.strip().lower()] = valeur.strip()
        elif ligne and not ligne.startswith(b"#"):
            if b"[" in ligne:
                return None, b"ligne de TOC conditionnelle non geree : " + ligne
            fichiers.append(ligne.replace(b"\\", b"/"))
    metas[nom.lower().encode("utf-8")] = meta
    return nom.encode("utf-8"), b"\n".join(fichiers)


def meta_addon(addon, cle):
    # Chemin chaud (une lecture par champ) : rien ne peut lever ; clé absente -> nil.
    # Valeur brute : l'addon recolle lui-même les morceaux « ~N~ ».
    if type(addon) is not bytes or type(cle) is not bytes:
        return None
    m = metas.get(addon.lower())
    return m.get(cle.lower()) if m is not None else None


@sans_exception
def base64_vers_octets(s, _variante=None):
    return base64.b64decode(s)


@sans_exception
def decompresser(s, methode):
    # Méthode 1 = zlib (en-tête 78 9C), vérifié sur X-Quest-IDS de la vraie base.
    if methode is None or int(methode) != 1:
        return None, ("méthode de décompression non gérée : %r" % (methode,)).encode("utf-8")
    d = zlib.decompressobj(15)
    sortie = d.decompress(s, TAILLE_MAX_DECOMPRESSE)
    if d.unconsumed_tail:
        return None, b"donnees decompressees trop grosses"
    return sortie


def refuser_attributs(obj, nom, ecriture):
    # Lua ne voit que des fonctions Python appelables, jamais leurs attributs (__globals__...).
    raise AttributeError("accès refusé")


rt = L.LuaRuntime(encoding=None, unpack_returned_tuples=True, register_eval=False,
                  register_builtins=False, attribute_filter=refuser_attributs)

# Bride le Lua AVANT toute exécution de code : plus de fichiers, de commandes, de C natif ni de Python.
BRIDE = r"""
local hote = ...
local rawloadstring, lire, err = loadstring, hote.lire, error
os = { clock = os.clock, date = os.date, time = os.time, difftime = os.difftime }
io = { write = io.write, stdout = io.stdout, stderr = io.stderr }
debug = { traceback = debug.traceback }
python = nil
require, module = nil, nil
if package then
  package.loadlib = nil
  package.loaders = { package.loaders[1] }
  package.path, package.cpath = "", ""
  package.loaded.python = nil
end
package = nil
-- Pas de bytecode (le vérificateur de Lua 5.1 n'est pas sûr).
local function charger(src, nom)
  if type(src) ~= "string" then return nil, "source invalide" end
  if src:byte(1) == 27 then return nil, "bytecode refusé" end
  return rawloadstring(src, nom)
end
loadstring = charger
load = function(f, nom)
  local morceaux = {}
  while true do
    local m = f()
    if m == nil or m == "" then break end
    morceaux[#morceaux + 1] = m
  end
  return charger(table.concat(morceaux), nom)
end
function loadfile(chemin)
  local src, msg = lire(chemin)
  if not src then return nil, msg end
  return charger(src, "@" .. chemin)
end
function dofile(chemin)
  local f, msg = loadfile(chemin)
  if not f then err(msg, 2) end
  return f()
end
"""

hote = rt.table_from({
    b"lire": lire,
    b"toc": ouvrir_toc,
    b"meta": meta_addon,
    b"base64": base64_vers_octets,
    b"decompresser": decompresser,
})
rt.execute(BRIDE.encode("utf-8"), hote)
g = rt.globals()
g[b"VRAIE_QDB_HOTE"] = hote  # repris puis effacé par tests/vraie_questiedb.lua
for k, v in args.items():
    g[k.encode("utf-8")] = v.encode("utf-8")
with open(sys.argv[1], "rb") as f:
    rt.execute(f.read())
