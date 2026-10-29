#!/usr/bin/env python3
"""Génère / met à jour index.xml (dépôt ReaPack) à partir de podsuite.json.

Usage : python3 tools/build_index.py --repo PROPRIÉTAIRE/DÉPÔT --commit SHA
Une nouvelle <version> n'est ajoutée que si le numéro de version de podsuite.json est nouveau ;
les anciennes versions restent disponibles (URL figées sur leur commit)."""
import argparse, hashlib, json, os, sys, urllib.parse
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATEGORY = "PodSuite"
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
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--commit", required=True)
    ap.add_argument("--branch", default="main")
    a = ap.parse_args()
    man = json.load(open(os.path.join(ROOT, "podsuite.json"), encoding="utf-8"))
    path = os.path.join(ROOT, "index.xml")
    if os.path.exists(path):
        root = ET.parse(path).getroot()
    else:
        root = ET.Element("index", version="1", name=man["name"])
    root.set("commit", a.commit)
    cat = root.find(f"category[@name='{CATEGORY}']")
    if cat is None: cat = ET.SubElement(root, "category", name=CATEGORY)
    pkg = cat.find("reapack[@name='PodSuite']")
    if pkg is None: pkg = ET.SubElement(cat, "reapack", name="PodSuite", type="script", desc=man["name"])
    meta = pkg.find("metadata")
    if meta is None: meta = ET.SubElement(pkg, "metadata")
    for c in list(meta): meta.remove(c)
    ET.SubElement(meta, "description").text = rtf(man["description"])
    ET.SubElement(meta, "link", rel="website").text = f"https://github.com/{a.repo}"

    if pkg.find(f"version[@name='{man['version']}']") is not None:
        print(f"Version {man['version']} déjà publiée : index inchangé (augmentez « version » dans podsuite.json pour publier).")
    else:
        ver = ET.Element("version", name=man["version"], author=man.get("author", ""),
                         time=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
        ET.SubElement(ver, "changelog").text = "\n".join("• " + l for l in man.get("changelog", []))
        for rel in man["files"]:
            full = os.path.join(ROOT, rel)
            data = open(full, "rb").read()
            name = os.path.basename(rel)
            url = f"https://raw.githubusercontent.com/{a.repo}/{a.commit}/" + urllib.parse.quote(rel)
            attrs = {"file": name, "hash": "1220" + hashlib.sha256(data).hexdigest()}
            if name in man["main"]: attrs["main"] = "main"
            ET.SubElement(ver, "source", attrs).text = url
        # versions : la plus ancienne d'abord, on en garde KEEP
        old = pkg.findall("version")
        pkg.append(ver)
        for v in old[:max(0, len(old) + 1 - KEEP)]: pkg.remove(v)
        print(f"Version {man['version']} ajoutée à l'index.")
    # metadata en dernier, comme dans les index officiels
    pkg.remove(meta); pkg.append(meta)
    ET.indent(root, space="  ")
    xml = '<?xml version="1.0" encoding="utf-8"?>\n' + ET.tostring(root, encoding="unicode") + "\n"
    open(path, "w", encoding="utf-8").write(xml)

if __name__ == "__main__":
    main()
