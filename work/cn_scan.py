import os, re, json

ROOT = r"D:\DSHDev\Reverse\Valorant App\work\apk"
OUT  = r"D:\DSHDev\Reverse\Valorant App\work\out"

# Match runs of characters valid in a MUTF-8 string: printable ASCII, CJK, and common UTF-8
pat = re.compile(
    rb"(?:[\x20-\x7e]|[\xc2-\xdf][\x80-\xbf]|[\xe0-\xef][\x80-\xbf]{2}|[\xf0-\xf4][\x80-\xbf]{3}){2,}"
)

cjk_re = re.compile(r"[\u4e00-\u9fff\u3000-\u303f\uff00-\uffef]")

hits = {}
dexes = sorted([f for f in os.listdir(ROOT) if f.endswith(".dex")])
for d in dexes:
    data = open(os.path.join(ROOT, d), "rb").read()
    for m in pat.finditer(data):
        try:
            s = m.group().decode("utf-8")
        except Exception:
            continue
        if not cjk_re.search(s):
            continue
        if len(s) > 400:
            continue
        hits.setdefault(s, set()).add(d)

with open(os.path.join(OUT, "cn_strings.txt"), "w", encoding="utf-8") as f:
    for s in sorted(hits):
        f.write(f"{','.join(sorted(hits[s]))}\t{s}\n")

print("total CN strings:", len(hits))

kw = ["商店", "商城", "每日", "夜市", "黑市", "皮肤", "套装", "特工", "战绩", "资产", "礼包", "点券", "商品", "抽奖"]
for k in kw:
    sel = [s for s in hits if k in s]
    print(f"--- {k}: {len(sel)}")
    for s in sorted(sel)[:25]:
        print("   ", s[:120])
