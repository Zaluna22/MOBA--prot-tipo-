import bpy,json,mathutils
bpy.ops.wm.read_factory_settings(use_empty=True)
R=json.load(open('rig.json'))
nodes={int(k):v for k,v in R['nodes'].items()}
bpy.ops.import_scene.gltf(filepath='ac_src.glb')
me=[o for o in bpy.data.objects if o.type=='MESH'][0]
for o in bpy.data.objects:
    if o.type!='MESH': o.select_set(False)

bpy.ops.object.select_all(action='DESELECT')
me.select_set(True);bpy.context.view_layer.objects.active=me
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=0.0005);bpy.ops.object.mode_set(mode='OBJECT')
def B(p): return mathutils.Vector((p[0],-p[2],p[1]))
ad=bpy.data.armatures.new('A');ao=bpy.data.objects.new('A',ad);bpy.context.collection.objects.link(ao)
bpy.context.view_layer.objects.active=ao;bpy.ops.object.mode_set(mode='EDIT')
skip=lambda n: n=='root' or any(k in n for k in ['index','middle','pinky','ring','thumb','leaf'])
kids={}
for i,v in nodes.items():
    if v['parent'] is not None: kids.setdefault(v['parent'],[]).append(i)
eb={}
for i,v in nodes.items():
    n=v['name']
    if skip(n): continue
    b=ad.edit_bones.new(n);h=B(v['PA']);b.head=h
    cs=[c for c in kids.get(i,[]) if not skip(nodes[c]['name'])]
    if n.startswith('hand'): t=h+(h-B(nodes[v['parent']]['PA'])).normalized()*0.07
    elif n=='Head': t=h+mathutils.Vector((0,0,0.28))
    elif n.startswith('ball'): t=h+mathutils.Vector((0,-0.07,0))
    elif n.startswith('clavicle'): t=B(nodes[cs[0]]['PA'])
    elif n=='spine_03': t=B([x for x in nodes.values() if x['name']=='neck_01'][0]['PA'])
    elif n=='pelvis': t=B([x for x in nodes.values() if x['name']=='spine_01'][0]['PA'])
    elif cs: t=B(nodes[cs[0]]['PA'])
    else: t=h+mathutils.Vector((0,0,0.05))
    b.tail=t;eb[i]=b
for i,b in eb.items():
    p=nodes[i]['parent']
    while p is not None and p not in eb: p=nodes[p]['parent'] if p in nodes else None
    if p is not None: b.parent=eb[p]
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.select_all(action='DESELECT');me.select_set(True);ao.select_set(True);bpy.context.view_layer.objects.active=ao
r=bpy.ops.object.parent_set(type='ARMATURE_AUTO');print('PARENT',r)
# loose parts without weights (cleaver, chain, hooks): whole island -> bone closest to the island
import bmesh
from mathutils.geometry import intersect_point_line
bm=bmesh.new();bm.from_mesh(me.data);bm.verts.ensure_lookup_table()
seen=set();bones=[(b.name,ao.matrix_world@b.head_local,ao.matrix_world@b.tail_local) for b in ad.bones]
def bdist(p,h,t):
    q,f=intersect_point_line(p,h,t);f=min(max(f,0),1);return (p-(h+(t-h)*f)).length
fixed=0
for v0 in bm.verts:
    if v0.index in seen: continue
    isl=[];st=[v0];seen.add(v0.index)
    while st:
        v=st.pop();isl.append(v.index)
        for e in v.link_edges:
            o=e.other_vert(v)
            if o.index not in seen: seen.add(o.index);st.append(o)
    vs=me.data.vertices
    nz=sum(1 for i in isl if any(g.weight>0.001 for g in vs[i].groups))
    if nz>=len(isl)*0.9 and len(isl)>50: continue
    best=None
    for i in isl[::max(1,len(isl)//200)]:
        p=vs[i].co
        for n,h,t in bones:
            d=bdist(p,h,t)
            if best is None or d<best[0]: best=(d,n)
    if nz>0 and len(isl)>2000: continue
    g=me.vertex_groups.get(best[1]) or me.vertex_groups.new(name=best[1])
    for i in isl:
        for gg in list(vs[i].groups): me.vertex_groups[gg.group].remove([i])
        g.add([i],1.0,'REPLACE')
    fixed+=len(isl);print('ISLAND',len(isl),'->',best[1],round(best[0],3))
print('FIXED',fixed)
vg={g.index:g.name for g in me.vertex_groups}
out=[]
empty=0
for v in me.data.vertices:
    w=[(vg[g.group],g.weight) for g in v.groups if g.weight>0.001]
    if not w: empty+=1
    out.append([[v.co.x,v.co.y,v.co.z],w])
print('VERTS',len(out),'EMPTY',empty)
json.dump(out,open('weights.json','w'))
