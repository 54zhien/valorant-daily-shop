import re, sys

path = r"D:\DSHDev\Reverse\Valorant App\work\out\all_strings.txt"
seen = set()
pat = re.compile(r"^/[A-Za-z0-9_\-/\.]{4,80}(\?[^\s]*)?$")
noise = re.compile(
    r"^(/(system|data|proc|dev|sdcard|storage|mnt|vendor|apex|android_asset|assets|res|"
    r"lib|etc|usr|tmp|var|root|meta-inf|okhttp|kotlin|org|google|com/|javax|sun/|dalvik)|"
    r"/go/|/proc/|/sys/)", re.I)
skip_words = ("/drawable", "/mipmap", "/layout", "/color", "/anim", "/style", "/string", "/attr",
              "/id/", "/xml", "/raw", "/dimen", "/plurals", "/array", "/integer", "/menu")

for line in open(path, encoding="utf-8", errors="replace"):
    parts = line.rstrip("\n").split("\t", 1)
    if len(parts) != 2:
        continue
    s = parts[1].strip()
    if not pat.match(s):
        continue
    if noise.match(s):
        continue
    if any(w in s for w in skip_words):
        continue
    if s in seen:
        continue
    seen.add(s)

for s in sorted(seen):
    print(s)
print("TOTAL", len(seen), file=sys.stderr)
