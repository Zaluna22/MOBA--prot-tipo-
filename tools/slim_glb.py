"""Slim a Quaternius Fantasy Races GLB for mobile web:
drops normal/roughness maps, morph targets, extra UV/color sets; base color -> 512px JPEG-free PNG."""
import json, struct, sys, io
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
TEX = int(sys.argv[3]) if len(sys.argv) > 3 else 512
b = open(src, 'rb').read()
l, = struct.unpack('<I', b[12:16]); j = json.loads(b[20:20 + l])
o = 20 + l; bl, = struct.unpack('<I', b[o:o + 4]); binb = b[o + 8:o + 8 + bl]

for m in j['materials']:
    m.pop('normalTexture', None)
    pbr = m.setdefault('pbrMetallicRoughness', {})
    pbr.pop('metallicRoughnessTexture', None)
    pbr['roughnessFactor'] = 0.85
    pbr['metallicFactor'] = 0
for me in j['meshes']:
    me.pop('weights', None); me.get('extras', {}).pop('targetNames', None)
    for p in me['primitives']:
        p.pop('targets', None)
        for k in list(p['attributes']):
            if k.startswith('COLOR') or (k.startswith('TEXCOORD') and k != 'TEXCOORD_0'):
                del p['attributes'][k]
for n in j['nodes']:
    n.pop('weights', None)

# which textures remain
used_tex = set()
for m in j['materials']:
    t = m['pbrMetallicRoughness'].get('baseColorTexture')
    if t: used_tex.add(t['index'])
tex_map = {}; new_tex = []; new_img = []
for ti in sorted(used_tex):
    t = j['textures'][ti]; img = j['images'][t['source']]
    bv = j['bufferViews'][img['bufferView']]
    data = binb[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']]
    im = Image.open(io.BytesIO(data)).convert('RGB')
    im.thumbnail((TEX, TEX), Image.LANCZOS)
    out = io.BytesIO(); im.save(out, 'PNG', optimize=True)
    new_img.append({'name': img.get('name', ''), 'mimeType': 'image/png', '_data': out.getvalue()})
    nt = dict(t); nt['source'] = len(new_img) - 1; new_tex.append(nt); tex_map[ti] = len(new_tex) - 1
for m in j['materials']:
    t = m['pbrMetallicRoughness'].get('baseColorTexture')
    if t: t['index'] = tex_map[t['index']]
j['textures'] = new_tex; j['images'] = new_img

# collect used accessors
used_acc = set()
for me in j['meshes']:
    for p in me['primitives']:
        used_acc.update(p['attributes'].values())
        if 'indices' in p: used_acc.add(p['indices'])
for s in j.get('skins', []):
    if 'inverseBindMatrices' in s: used_acc.add(s['inverseBindMatrices'])
for a in j.get('animations', []):
    for smp in a['samplers']: used_acc.update([smp['input'], smp['output']])
acc_map = {}; new_acc = []; new_bv = []; nb = bytearray()
def add_bytes(data, extra):
    while len(nb) % 4: nb.append(0)
    bv = {'buffer': 0, 'byteOffset': len(nb), 'byteLength': len(data)}; bv.update(extra)
    nb.extend(data); new_bv.append(bv); return len(new_bv) - 1
for ai in sorted(used_acc):
    a = dict(j['accessors'][ai]); bv = j['bufferViews'][a['bufferView']]
    s = bv.get('byteOffset', 0); data = binb[s:s + bv['byteLength']]
    extra = {k: bv[k] for k in ('byteStride', 'target') if k in bv}
    a['bufferView'] = add_bytes(data, extra); acc_map[ai] = len(new_acc); new_acc.append(a)
for img in j['images']:
    img['bufferView'] = add_bytes(img.pop('_data'), {})
for me in j['meshes']:
    for p in me['primitives']:
        p['attributes'] = {k: acc_map[v] for k, v in p['attributes'].items()}
        if 'indices' in p: p['indices'] = acc_map[p['indices']]
for s in j.get('skins', []):
    if 'inverseBindMatrices' in s: s['inverseBindMatrices'] = acc_map[s['inverseBindMatrices']]
for a in j.get('animations', []):
    for smp in a['samplers']: smp['input'] = acc_map[smp['input']]; smp['output'] = acc_map[smp['output']]
j['accessors'] = new_acc; j['bufferViews'] = new_bv
while len(nb) % 4: nb.append(0)
j['buffers'] = [{'byteLength': len(nb)}]
js = json.dumps(j, separators=(',', ':')).encode()
while len(js) % 4: js += b' '
out = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(nb)) + struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(nb), 0x004E4942) + bytes(nb)
open(dst, 'wb').write(out)
print(dst, len(out))
