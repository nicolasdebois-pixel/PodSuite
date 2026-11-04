#!/usr/bin/env python3
"""Génère / met à jour index.xml (dépôt ReaPack) à partir de toolbox.json.
Usage : python3 tools/build_index.py --repo PROPRIÉTAIRE/DÉPÔT --commit SHA
Une nouvelle <version> n'est ajoutée que si le numéro de version est nouveau ; les anciennes restent disponibles."""
import argparse, hashlib, json, os, urllib.parse
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEEP = 15

def rtf(text):
    out = []
    for ch in text:
        o = ord(ch)
        if ch in "\\{}": out.append("\\" + ch)
        elif o < 128: out.append(ch)
        else: out.append("\\u%d?" % (o if o < 32768 else o - 65536))
    return "{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 \\fswiss Helvetica;}}\\f0\\fs22 " + "".join(out) + "\\par}"

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--repo", required=True); ap.add_argument("--commit", required=True)
    a = ap.parse_args()
    man = json.load(open(os.path.join(ROOT, "toolbox.json"), encoding="utf-8"))
    path = os.path.join(ROOT, "index.xml")
    root = ET.parse(path).getroot() if os.path.exists(path) else ET.Element("index", version="1")
    if root.get("name") != man["name"]:                      # nouveau nom de dépôt : on repart d'un index propre
        root = ET.Element("index", version="1")
    root.set("name", man["name"]); root.set("commit", a.commit)
    cat = root.find(f"category[@name='{man['category']}']")
    if cat is None: cat = ET.SubElement(root, "category", name=man["category"])
    pkg = cat.find(f"reapack[@name='{man['package']}']")
    if pkg is None: pkg = ET.SubElement(cat, "reapack", name=man["package"], type="script", desc=man["name"])
    meta = pkg.find("metadata")
    if meta is None: meta = ET.SubElement(pkg, "metadata")
    for c in list(meta): meta.remove(c)
    ET.SubElement(meta, "description").text = rtf(man["description"])
    ET.SubElement(meta, "link", rel="website").text = f"https://github.com/{a.repo}"
    if pkg.find(f"version[@name='{man['version']}']") is not None:
        print(f"Version {man['version']} déjà publiée : index inchangé (augmentez « version » dans toolbox.json pour publier).")
    else:
        ver = ET.Element("version", name=man["version"], author=man.get("author", ""), time=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
        ET.SubElement(ver, "changelog").text = "\n".join("• " + l for l in man.get("changelog", []))
        for f in man["files"]:
            rel = f["path"]; data = open(os.path.join(ROOT, rel), "rb").read()
            attrs = {"file": os.path.basename(rel), "hash": "1220" + hashlib.sha256(data).hexdigest()}
            if f.get("main"): attrs["main"] = "main"
            if f.get("type"): attrs["type"] = f["type"]
            ET.SubElement(ver, "source", attrs).text = f"https://raw.githubusercontent.com/{a.repo}/{a.commit}/" + urllib.parse.quote(rel)
        old = pkg.findall("version"); pkg.append(ver)
        for v in old[:max(0, len(old) + 1 - KEEP)]: pkg.remove(v)
        print(f"Version {man['version']} ajoutée à l'index.")
    pkg.remove(meta); pkg.append(meta)
    ET.indent(root, space="  ")
    open(path, "w", encoding="utf-8").write('<?xml version="1.0" encoding="utf-8"?>\n' + ET.tostring(root, encoding="unicode") + "\n")

if __name__ == "__main__": main()
