#!/usr/bin/env python3
"""The keys of the message composer follow the Filigrane rule for every message composer: Enter makes a new line,
Shift+Enter sends (Ctrl+Enter too, as mail clients do). The body's TextArea takes Shift+Enter as a new line before
any Shortcut sees it, so the body must send it itself; the one-line fields get it from the Shortcut."""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
compose = (ROOT / "qml/Compose.qml").read_text()
card = (ROOT / "qml/ShortcutsCard.qml").read_text()
fail = []

send = re.search(r'Shortcut \{ sequences: \[([^\]]*)\][^}]*compose\.submit\(\)', compose)
if not send or not all(k in send.group(1) for k in ('"Shift+Return"', '"Shift+Enter"', '"Ctrl+Return"', '"Ctrl+Enter"')):
    fail.append("the send Shortcut of Compose.qml must have Shift+Return, Shift+Enter, Ctrl+Return and Ctrl+Enter")
body = re.search(r'TextArea \{\s*id: body(.*?)\n        \}', compose, re.S)
if not body or not re.search(r'Keys\.onPressed:.*?Qt\.ShiftModifier.*?compose\.submit\(\)', body.group(1), re.S):
    fail.append("the body TextArea of Compose.qml must send on Shift+Enter itself (Keys.onPressed)")
if not re.search(r'\["Shift\+Enter[^"]*", Facteur\.tr\("Send"\)\]', card):
    fail.append("the shortcuts card must show Shift+Enter for Send")

for f in fail:
    print("not ok - " + f, file=sys.stderr)
sys.exit(1 if fail else 0)
