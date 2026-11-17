"""Fabrique les fichiers d'une release d'Itinéraire dans dist/.

  dist/Itineraire-vX.Y.Z.zip         l'addon seul (dossier Itineraire/) : c'est lui que l'installateur télécharge
  dist/Itineraire-vX.Y.Z-paquet.zip  installateur + addon + mode d'emploi : à donner aux joueurs

Usage : python -I outils/paquet.py   (depuis n'importe où ; la version vient de Itineraire/Itineraire.toc)
"""
import hashlib
import pathlib
import re
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON = ROOT / "Itineraire"
DIST = ROOT / "dist"


def version():
    toc = (ADDON / "Itineraire.toc").read_text(encoding="utf-8")
    m = re.search(r"^## Version:\s*([0-9]+(?:\.[0-9]+)*)\s*$", toc, re.M)
    if not m:
        sys.exit("Version introuvable dans Itineraire.toc")
    return m.group(1)


def addon_files():
    files = sorted(p for p in ADDON.rglob("*") if p.is_file())
    for p in files:
        if p.suffix.lower() not in {".lua", ".toc", ".xml", ".txt"}:
            sys.exit(f"Fichier inattendu dans l'addon : {p.relative_to(ROOT)}")
    return files


def write_zip(path, entries):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for src, arc in entries:
            z.write(src, arc)
    with zipfile.ZipFile(path) as z:
        if z.testzip() is not None:
            sys.exit(f"Archive abîmée : {path}")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    print(f"{path.name}  {path.stat().st_size} octets  sha256:{digest}")


def main():
    v = version()
    DIST.mkdir(exist_ok=True)
    addon = [(p, "Itineraire/" + p.relative_to(ADDON).as_posix()) for p in addon_files()]
    write_zip(DIST / f"Itineraire-v{v}.zip", addon)
    extra = [
        (ROOT / "installateur" / "Installer-Itineraire.cmd", "Installer-Itineraire.cmd"),
        (ROOT / "installateur" / "Installer-Itineraire.ps1", "Installer-Itineraire.ps1"),
        (ROOT / "partage" / "paquet" / "_LISEZ-MOI.txt", "_LISEZ-MOI.txt"),
    ]
    write_zip(DIST / f"Itineraire-v{v}-paquet.zip", extra + addon)


if __name__ == "__main__":
    main()
