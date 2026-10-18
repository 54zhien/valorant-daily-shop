import struct, sys

p = r"D:\DSHDev\Reverse\Valorant App\work\apk\AndroidManifest.xml"
data = open(p, "rb").read()
print("magic", data[:4].hex(), "size", len(data))

# AXML header: 0x00080003, then chunk headers
off = 8
chunks = []
while off + 8 <= len(data):
    ctype, hsize, csize = struct.unpack_from("<HHI", data, off)
    chunks.append((hex(ctype), hsize, csize, off))
    if csize == 0:
        break
    off += csize
for c in chunks[:10]:
    print(c)

# string pool chunk: type 0x0001
off = 8
while off + 8 <= len(data):
    ctype, hsize, csize = struct.unpack_from("<HHI", data, off)
    if ctype == 0x0001:
        base = off
        scount, styleCount, flags, sstart, stystart = struct.unpack_from("<IIIII", data, base + 8)
        utf8 = (flags & (1 << 8)) != 0
        offsets = struct.unpack_from("<%dI" % scount, data, base + hsize)
        out = []
        for o in offsets:
            pos = base + sstart + o
            if utf8:
                # u16 len (utf16), u16 len (utf8), bytes, 0
                n1 = data[pos]; pos += 1
                if n1 & 0x80:
                    n1 = ((n1 & 0x7F) << 8) | data[pos]; pos += 1
                n2 = data[pos]; pos += 1
                if n2 & 0x80:
                    n2 = ((n2 & 0x7F) << 8) | data[pos]; pos += 1
                s = data[pos:pos + n2].decode("utf-8", "replace")
            else:
                n = struct.unpack_from("<H", data, pos)[0]; pos += 2
                if n & 0x8000:
                    n = ((n & 0x7FFF) << 16) | struct.unpack_from("<H", data, pos)[0]
                    pos += 2
                s = data[pos:pos + n * 2].decode("utf-16-le", "replace")
            out.append(s)
        with open(r"D:\DSHDev\Reverse\Valorant App\work\out\manifest_strings.txt", "w", encoding="utf-8") as f:
            for i, s in enumerate(out):
                f.write("%d\t%s\n" % (i, s))
        print("strings:", len(out))
        break
    if csize == 0:
        break
    off += csize
