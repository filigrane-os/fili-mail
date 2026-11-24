#!/usr/bin/env python3
"""Checks the QML of Facteur against the fili-ui kit it is pinned to (found through cargo), without linking Qt:

    scripts/check-kit-qml.py          (from the source tree of Facteur (fili-mail))

 - every FiliTheme.<name> used in qml/*.qml is a token the kit defines (a misspelled token does not fail at run time: the item
   just stays transparent);
 - the actions the window panel of the kit shows are exactly the ones src/window.rs allows (ACTIONS), so nothing but a listed
   window action can be run from the interface.
Exit code 1 on any problem.
"""
import glob
import json
import os
import re
import subprocess
import sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
out = subprocess.run(["cargo", "metadata", "--format-version", "1", "--locked"], cwd=root, capture_output=True, text=True)
if out.returncode != 0:
    sys.exit("check-kit-qml: cargo metadata failed, cannot find the fili-ui kit:\n" + out.stderr[-400:])
manifest = next(p["manifest_path"] for p in json.loads(out.stdout)["packages"] if p["name"] == "fili-ui")
kit = os.path.join(os.path.dirname(manifest), "qml/Fili/UI")

problems = 0
theme = open(f"{kit}/FiliTheme.qml").read()
defined = {m.group(1) for m in re.finditer(r"^\s*(?:readonly )?property \w+ (\w+)", theme, re.M)}
defined |= {m.group(1) for m in re.finditer(r"^\s*function (\w+)\(", theme, re.M)}
for path in sorted(glob.glob(f"{root}/qml/*.qml")):
    for name in sorted(set(re.findall(r"FiliTheme\.(\w+)", open(path).read()))):
        if name not in defined:
            print(f"{os.path.relpath(path, root)}: FiliTheme.{name} is not defined by the kit")
            problems += 1

panel = set(re.findall(r'action: "([^"]+)"', open(f"{kit}/FiliWindowPanel.qml").read()))
window = open(f"{root}/src/window.rs").read()
allowed = set(re.findall(r'"([^"]+)"', re.search(r"pub const ACTIONS: &\[&str\] = &\[(.*?)\];", window, re.S).group(1)))
for a in sorted(panel - allowed):
    print(f"{a} is shown by the window panel but not allowed in src/window.rs")
    problems += 1
for a in sorted(allowed - panel):
    print(f"{a} is allowed in src/window.rs but not shown by the window panel")
    problems += 1
print(f"{len(defined)} kit tokens, {len(panel)} window actions, {problems} problem(s)")
sys.exit(1 if problems else 0)
