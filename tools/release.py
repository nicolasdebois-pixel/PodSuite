#!/usr/bin/env python3
"""Avant de publier : recopie la version de toolbox.json dans Toolbox_lib.lua et ajoute l'entrée au CHANGELOG.md."""
import json, os, re, datetime
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
m = json.load(open(os.path.join(ROOT, "toolbox.json"), encoding="utf-8"))
v = m["version"]
lib = os.path.join(ROOT, "Scripts", "Toolbox_lib.lua")
s = open(lib, encoding="utf-8").read()
s = re.sub(r'P\.VERSION = "[^"]*"', f'P.VERSION = "{v}"', s, count=1)
open(lib, "w", encoding="utf-8").write(s)
cl = os.path.join(ROOT, "CHANGELOG.md")
old = open(cl, encoding="utf-8").read() if os.path.exists(cl) else "# Nouveautés de Podcast & ADR Toolbox\n"
if f"## {v} " not in old:
    head, _, rest = old.partition("\n")
    entry = f"\n## {v} — {datetime.date.today().strftime('%d/%m/%Y')}\n" + "".join(f"- {l}\n" for l in m.get("changelog", []))
    old = head + "\n" + entry + rest
open(cl, "w", encoding="utf-8").write(old)
print("version", v)
