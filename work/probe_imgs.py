import urllib.request, struct
urls = {
 "title":  "https://game.gtimg.cn/images/val/agamezlk/valapp/gift/title.png",
 "spray":  "https://game.gtimg.cn/images/val/agamezlk/Sprays/C0D282F7-4659-7699-4DD9-6C8364791D7F.png",
 "charm":  "https://game.gtimg.cn/images/val/agamezlk/Charms/7C80CD43-4F82-5D07-C8CF-AA82FADA4E2D.png",
 "acce_bg":"https://game.gtimg.cn/images/val/agamezlk/valapp/store/accessory.png",
 "skin":   "https://game.gtimg.cn/images/val/agamezlk/WeaponSkins/FB9B07EB-4591-D22C-A611-BB821664FBF6.png",
}
SIG = b"\x89PNG\r\n\x1a\n"
for k,u in urls.items():
    try:
        req=urllib.request.Request(u, headers={"User-Agent":"okhttp/4.9.2"})
        with urllib.request.urlopen(req, timeout=20) as r:
            b=r.read()
        w=h=None
        ispng = b[:8]==SIG
        if ispng:
            w,h=struct.unpack(">II", b[16:24])
        print("{:8} bytes={:7} png={} size={}x{}".format(k, len(b), ispng, w, h))
    except Exception as e:
        print("{:8} ERR {}".format(k, e))
