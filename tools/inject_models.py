#!/usr/bin/env python3
"""Inject the gitignored hero models (Elfa, Orc, Orca, Açougueiro) from an older APK
into a fresh Godot export, patching the sparse PCK index so sizes/md5 match.
usage: inject_models.py NEW.apk OLD.apk OUT_UNSIGNED.apk"""
import sys, zipfile, struct, hashlib, re

new_p, old_p, out_p = sys.argv[1:4]
new = zipfile.ZipFile(new_p); old = zipfile.ZipFile(old_p)

# files to take from the old APK: model remaps + everything they point at
ov = set()
for n in old.namelist():
    if n.startswith(('assets/assets/quaternius/', 'assets/assets/tripo/')):
        ov.add(n)
        for m in re.findall(rb'res://([^"]+)"', old.read(n)):
            ov.add('assets/' + m.decode())
ov = {n for n in ov if n in old.namelist()}

# patch sparse pck index
SP = 'assets/assets.sparsepck'
d = new.read(SP)
diro = struct.unpack('<I', d[32:36])[0]
n = struct.unpack('<I', d[diro:diro + 4])[0]; p = diro + 4; es = {}
order = []
for _ in range(n):
    L = struct.unpack('<I', d[p:p + 4])[0]; path = d[p + 4:p + 4 + L].rstrip(b'\0').decode(); p += 4 + L
    off, size = struct.unpack('<QQ', d[p:p + 16]); md5 = d[p + 16:p + 32]; fl = struct.unpack('<I', d[p + 32:p + 36])[0]; p += 36
    es[path] = [off, size, md5, fl]; order.append(path)
assert p == len(d), (p, len(d))
for z in ov:
    data = old.read(z); rel = z[len('assets/'):]
    if rel not in es:
        es[rel] = [0, 0, b'', 0]; order.append(rel)
    es[rel][1] = len(data); es[rel][2] = hashlib.md5(data).digest()
out_dir = bytearray(struct.pack('<I', len(order)))
for path in order:
    b = path.encode(); pad = (-len(b)) % 4
    off, size, md5, fl = es[path]
    out_dir += struct.pack('<I', len(b) + pad) + b + b'\0' * pad + struct.pack('<QQ', off, size) + md5 + struct.pack('<I', fl)
newsp = d[:diro] + bytes(out_dir)

out = open(out_p, 'wb'); z = zipfile.ZipFile(out, 'w')
def put(name, data, info):
    zi = zipfile.ZipInfo(name, date_time=info.date_time); zi.compress_type = info.compress_type; zi.external_attr = info.external_attr
    if info.compress_type == zipfile.ZIP_STORED:
        align = 16384 if name.endswith('.so') else 4
        off = out.tell() + 30 + len(name.encode())
        pad = (-(off + 4)) % align
        zi.extra = b'\xd9\xd9' + pad.to_bytes(2, 'little') + b'\0' * pad
    z.writestr(zi, data)
seen = set()
for i in new.infolist():
    nm = i.filename
    if nm.startswith('META-INF/') and nm.rsplit('.', 1)[-1] in ('SF', 'RSA', 'MF', 'EC', 'DSA'):
        continue
    if nm == SP: put(nm, newsp, i)
    elif nm in ov: put(nm, old.read(nm), old.getinfo(nm)); seen.add(nm)
    else: put(nm, new.read(nm), i)
for nm in sorted(ov - seen):
    put(nm, old.read(nm), old.getinfo(nm))
z.close()
print('injected', len(ov), 'files; index entries', n, '->', len(order))
