#!/usr/bin/env python3
"""The fili-bar menu of Facteur (shell/appmenu/fili-mail.json) stays in agreement with the window (qml/Main.qml): every
`fili-mail ctl --pid %pid action NAME` of the menu is an action of the window, every action of the window is in the menu (the
few that have none are listed below), every announced shortcut is a key of the window's QML, and the brief of Lia
(shell/lia/fili-mail.md) exists. Usage: scripts/check-shell-menu.py (from anywhere)."""
import json, pathlib, re, sys

root = pathlib.Path(__file__).resolve().parents[1]
menu = json.loads((root / "shell/appmenu/fili-mail.json").read_text())
qml_files = {f.name: f.read_text() for f in (root / "qml").glob("*.qml")}
qml = qml_files["Main.qml"]
body = qml[qml.index("function onCommand(name)"):qml.index("function onSent(json)")]
actions = set(re.findall(r'name === "([a-z-]+)"', body))
# The mailboxes ({ "inbox": "inbox", ... }) and the operations on the selected message (win.doAct) have no `name ===` of their own
boxes = re.search(r"const boxes = \{([^}]*)\}", body)
actions |= set(re.findall(r'"([a-z-]+)":', boxes.group(1))) if boxes else set()
message_actions = {"archive", "trash", "spam", "star", "unstar", "read", "unread"}
everything_qml = "\n".join(qml_files.values())
actions |= {a for a in message_actions if f'"{a}"' in everything_qml}
sequences = set()
for text in qml_files.values():
    for m in re.finditer(r'sequences?: (\[[^\]]*\]|"[^"]*")', text):
        sequences |= set(re.findall(r'"([^"]+)"', m.group(1)))
# Reachable from the keyboard help (F1) or the interface only (the combined views of the sidebar, the button of the reader
# that loads remote pictures): not commands of the menu
without_menu = {"shortcuts", "all-inboxes", "all-unread", "load-pictures"}
# Keys the text fields handle themselves (copy and select all)
native_keys = {"Ctrl+C", "Ctrl+A"}
errors = []
if not (root / "shell/lia/fili-mail.md").is_file():
    errors.append("brief of Lia missing: shell/lia/fili-mail.md")

def entries(items):
    for e in items:
        if "children" in e:
            yield from entries(e["children"])
        elif not e.get("sep"):
            yield e

def key_known(k):
    if k in sequences or k in native_keys:
        return True
    # A single key of the message list or of the reader (Keys.onPressed: Qt.Key_E, Qt.Key_Delete)
    return "+" not in k and f"Qt.Key_{k}" in everything_qml

everything = list(entries(menu["app"] + menu["window"] + [m for top in menu["menus"] for m in top["children"]]))
used = set()
for e in everything:
    cmd = e.get("exec", "")
    if not cmd.startswith("fili-mail ctl"):
        continue  # a command that opens a file (Settings…)
    m = re.fullmatch(r"fili-mail ctl --pid %pid action ([a-z-]+)", cmd)
    if not m or m.group(1) not in actions:
        errors.append(f"command without an action in Main.qml: {cmd}")
    else:
        used.add(m.group(1))
    k = e.get("keys")
    if k and not key_known(k):
        errors.append(f"shortcut without a key in the window: {k}")
for a in sorted(actions - used - without_menu):
    errors.append(f"action of Main.qml missing from the menu: {a}")
if errors:
    print("not ok - menu of Facteur:")
    print("\n".join("#   " + e for e in errors))
    sys.exit(1)
print("ok - menu of Facteur agrees with Main.qml (%d actions)" % len(actions))
