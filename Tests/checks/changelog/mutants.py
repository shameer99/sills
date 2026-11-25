"""Mutants of Changelog.swift (iOSClient): each changes one in one place and must make
the check (main.swift) fail. usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))
OUT = os.path.join(ROOT, ".build", "checks", "changelog")
os.makedirs(OUT, exist_ok=True)
FILES = {"C": "iOSClient/Changelog.swift"}
SRC = {k: open(os.path.join(ROOT, v)).read() for k, v in FILES.items()}
MUTANTS = [
    ("C1 the label without parentheses", "C", 'var label: String { "\\(version) (\\(build))" }', 'var label: String { "\\(version) \\(build)" }'),
    ("C2 the newest release's build behind the project's", "C", 'Release(version: "0.6.3", build: "9"', 'Release(version: "0.6.3", build: "10"'),
    ("C3 a day written another way", "C", 'build: "9", date: "2026-11-25"', 'build: "9", date: "25 Nov 2026"'),
    ("C4 no upstream item anywhere", "C", '"Sill 0.6.3 from upstream main (c33d105, 2026-11-20).",\n            "Privacy: the Mac locks itself when the last device leaves (#402).",\n            "Audio: a staged window\'s sound is captured on Sill\'s display, and an ended capture retries by itself (#396).",\n            "Host: follows macOS\'s own tab switches in a streamed window (#399).",', ''),
]
caught = 0
for name, which, old, new in MUTANTS:
    orig = SRC[which]
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    paths = []
    for k, rel in FILES.items():
        p = os.path.join(OUT, os.path.basename(rel))
        open(p, "w").write(orig.replace(old, new, 1) if k == which else SRC[k])
        paths.append(p)
    exe = os.path.join(OUT, "mutant")
    if os.path.exists(exe): os.remove(exe)
    c = subprocess.run(["swiftc", "-O", *paths, os.path.join(SP, "main.swift"), "-o", exe], capture_output=True, text=True)
    if c.returncode != 0:
        print(f"{name}: did not compile: {c.stderr.strip().splitlines()[0] if c.stderr.strip() else ''}"); continue
    r = subprocess.run([exe, os.path.join(ROOT, "iOSClient/Sill.xcodeproj/project.pbxproj")], capture_output=True, text=True, timeout=600)
    failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
    if r.returncode != 0:
        caught += 1
        print(f"{name}: caught ({len(failed)} FAIL lines; first: {failed[0][:150] if failed else 'exit ' + str(r.returncode)})")
    else:
        print(f"{name}: SURVIVED")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
