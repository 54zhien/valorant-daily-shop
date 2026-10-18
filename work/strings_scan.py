import os, re, sys, json, collections

ROOT = r"D:\DSHDev\Reverse\Valorant App\work\apk"
OUT  = r"D:\DSHDev\Reverse\Valorant App\work\out"
os.makedirs(OUT, exist_ok=True)

# DEX string data is MUTF-8, length-prefixed. Raw regex over bytes gets most of it.
strpat = re.compile(rb"[\x20-\x7e]{6,}")

def dex_strings(path):
    data = open(path, "rb").read()
    seen = set()
    for m in strpat.finditer(data):
        s = m.group().decode("ascii", "ignore")
        if s not in seen:
            seen.add(s)
            yield s

url_re = re.compile(r"https?://[A-Za-z0-9\-\._~:/?#\[\]@!$&'()*+,;=%]+")

urls = collections.Counter()
allstrings_by_dex = {}

dexes = sorted([f for f in os.listdir(ROOT) if f.endswith(".dex")],
               key=lambda x: (len(x), x))
for d in dexes:
    p = os.path.join(ROOT, d)
    s = set()
    for st in dex_strings(p):
        s.add(st)
        for u in url_re.findall(st):
            urls[u] += 1
    allstrings_by_dex[d] = s
    print(d, "unique strings:", len(s), flush=True)

with open(os.path.join(OUT, "urls.txt"), "w", encoding="utf-8") as f:
    for u, c in urls.most_common():
        f.write(f"{c}\t{u}\n")

# dump all strings for grep-ability
with open(os.path.join(OUT, "all_strings.txt"), "w", encoding="utf-8", errors="replace") as f:
    for d in dexes:
        for st in sorted(allstrings_by_dex[d]):
            f.write(f"{d}\t{st}\n")

print("URLS:", len(urls))
for u, c in urls.most_common(60):
    print(c, u)
