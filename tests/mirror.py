# Copies src/ into tests/.mirror/src with `x.Position` reads rewritten to
# __P(x): Lune's Roblox library can't compute BasePart.Position from CFrame,
# so the harness supplies __P. Writes (`x.Position = v`) are left alone.
import os, re, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "src")
DST = os.path.join(HERE, ".mirror", "src")

shutil.rmtree(DST, ignore_errors=True)
pat = re.compile(r'([A-Za-z_][\w]*(?:\[[^\]\[]*\]|\.[A-Za-z_]\w*|\(\))*?)\.Position\b(?!\s*=[^=])')
for root, _, files in os.walk(SRC):
    for f in files:
        with open(os.path.join(root, f)) as fh:
            s = pat.sub(lambda m: f"__P({m.group(1)})", fh.read())
        out = os.path.join(DST, os.path.relpath(root, SRC))
        os.makedirs(out, exist_ok=True)
        with open(os.path.join(out, f), "w") as fh:
            fh.write(s)
