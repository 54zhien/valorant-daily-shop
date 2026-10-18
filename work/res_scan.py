import os, re, collections

ROOT = r"D:\DSHDev\Reverse\Valorant App\work\apk"
OUT  = r"D:\DSHDev\Reverse\Valorant App\work\out"

pat = re.compile(
    rb"(?:[\x20-\x7e]|[\xc2-\xdf][\x80-\xbf]|[\xe0-\xef][\x80-\xbf]{2}|[\xf0-\xf4][\x80-\xbf]{3}){2,}"
)
cjk_re = re.compile(r"[\u4e00-\u9fff]")

hits = collections.defaultdict(set)
targets = []
for dirpath, dirnames, filenames in os.walk(ROOT):
    for fn in filenames:
        p = os.path.join(dirpath, fn)
        ext = os.path.splitext(fn)[1].lower()
        if ext in (".dex", ".so", ".mp4", ".png", ".jpg", ".webp", ".ttf", ".tnnmodel", ".zip", ".apk"):
            continue
        targets.append(p)

print("files:", len(targets))
for p in targets:
    try:
        data = open(p, "rb").read()
    except Exception:
        continue
    rel = os.path.relpath(p, ROOT)
    for m in pat.finditer(data):
        try:
            s = m.group().decode("utf-8")
        except Exception:
            continue
        if not cjk_re.search(s) or len(s) > 300:
            continue
        hits[s].add(rel)

with open(os.path.join(OUT, "cn_strings_res.txt"), "w", encoding="utf-8") as f:
    for s in sorted(hits):
        f.write(f"{'|'.join(sorted(hits[s]))}\t{s}\n")

print("total:", len(hits))
for k in ["每日商店", "商店", "商城", "夜市", "无畏", "掌瓦", "皮肤", "资产"]:
    sel = [s for s in hits if k in s]
    print(f"--- {k}: {len(sel)}")
    for s in sorted(sel)[:30]:
        print("   ", s[:140])
