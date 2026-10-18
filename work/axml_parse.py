import struct, sys, json

P = r"D:\DSHDev\Reverse\Valorant App\work\apk\AndroidManifest.xml"
data = open(P, "rb").read()

def parse_string_pool(off):
    ctype, hsize, csize = struct.unpack_from("<HHI", data, off)
    assert ctype == 0x0001, hex(ctype)
    scount, styleCount, flags, sstart, stystart = struct.unpack_from("<IIIII", data, off + 8)
    utf8 = (flags & (1 << 8)) != 0
    offsets = struct.unpack_from("<%dI" % scount, data, off + hsize)
    out = []
    for o in offsets:
        pos = off + sstart + o
        if utf8:
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
    return out, csize

# --- collect chunks ---
off = 8
strpool = None
resmap = None
xml_off = None
while off + 8 <= len(data):
    ctype, hsize, csize = struct.unpack_from("<HHI", data, off)
    if csize == 0:
        break
    if ctype == 0x0001 and strpool is None:
        strpool, _ = parse_string_pool(off)
    elif ctype == 0x0180:
        n = (csize - hsize) // 4
        resmap = list(struct.unpack_from("<%dI" % n, data, off + hsize))
    elif ctype in (0x0102, 0x0100):
        if xml_off is None:
            xml_off = off
    off += csize

print("strings:", len(strpool), "resmap:", len(resmap) if resmap else None)

def s(i):
    if i is None or i < 0 or i >= len(strpool):
        return None
    return strpool[i]

def attr_name(i):
    return s(i)

elements = []
off = xml_off
guard = 0
while off + 8 <= len(data) and guard < 200000:
    guard += 1
    ctype, hsize, csize = struct.unpack_from("<HHI", data, off)
    if csize == 0:
        break
    if ctype not in (0x0100, 0x0101, 0x0102, 0x0103, 0x0104):
        print("UNKNOWN chunk at", off, hex(ctype), hsize, csize)
        break
    if ctype == 0x0102:  # START_ELEMENT
        line, comment = struct.unpack_from("<II", data, off + 8)
        ns, name = struct.unpack_from("<ii", data, off + 16)
        attrStart, attrSize, attrCount = struct.unpack_from("<HHH", data, off + 24)
        attrs = {}
        aoff = off + 16 + attrStart
        for k in range(attrCount):
            if aoff + 20 > len(data):
                print("OOB attr at", aoff, "elem", s(name), off)
                break
            a_ns, a_name, a_rawv = struct.unpack_from("<iii", data, aoff)
            a_size, a_res0, a_type, a_data = struct.unpack_from("<HBBI", data, aoff + 12)
            if a_type == 0x03:
                val = s(a_data)
            elif a_type == 0x12:
                val = bool(a_data)
            elif a_type == 0x10:
                val = a_data
            elif a_type == 0x11:
                val = "0x%08x" % a_data
            else:
                val = "%s(type=0x%02x)" % (s(a_rawv) if a_rawv >= 0 else a_data, a_type)
            an = attr_name(a_name)
            if a_ns >= 0:
                an = "android:" + (s(a_name) or str(a_name))
            attrs[an] = val
            aoff += 20
        tag = s(name)
        elements.append((tag, attrs))
    off += csize

with open(r"D:\DSHDev\Reverse\Valorant App\work\out\manifest_dump.txt", "w", encoding="utf-8") as f:
    for tag, attrs in elements:
        f.write("<%s %s>\n" % (tag, " ".join('%s="%s"' % (k, v) for k, v in attrs.items())))

# print manifest root + application attrs and meta-data
for tag, attrs in elements:
    if tag == "manifest":
        print("MANIFEST:", attrs)
    if tag == "application":
        print("APPLICATION:", {k: v for k, v in attrs.items()})
    if tag == "meta-data":
        print("META:", attrs)
print("total elements:", len(elements))
