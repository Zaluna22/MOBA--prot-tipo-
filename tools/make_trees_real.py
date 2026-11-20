# Leaf-card trees (Blender). Run: blender -b -P tools/make_trees_real.py
import bpy, bmesh, random, math
from mathutils import Vector, Matrix
OUT="/workspace/work/moba-prototipo/assets/nature/"
def mats():
    lm=bpy.data.materials.new("leaves"); lm.use_nodes=True; nt=lm.node_tree; b=nt.nodes["Principled BSDF"]
    t=nt.nodes.new("ShaderNodeTexImage"); t.image=bpy.data.images.load(OUT+"leaves.png")
    nt.links.new(t.outputs[0],b.inputs["Base Color"]); nt.links.new(t.outputs[1],b.inputs["Alpha"]); b.inputs["Roughness"].default_value=1
    lm.blend_method='CLIP'
    bm_=bpy.data.materials.new("bark"); bm_.use_nodes=True; nt=bm_.node_tree; b=nt.nodes["Principled BSDF"]
    t=nt.nodes.new("ShaderNodeTexImage"); t.image=bpy.data.images.load(OUT+"bark.png"); nt.links.new(t.outputs[0],b.inputs["Base Color"])
    return lm,bm_
def card(bm,uv,c,center,size,rng):
    # random oriented quad; normals bent away from canopy center
    n=Vector((rng.uniform(-1,1),rng.uniform(-1,1),rng.uniform(-0.3,1))).normalized()
    t=n.cross(Vector((0,0,1)) if abs(n.z)<0.9 else Vector((1,0,0))).normalized(); b=n.cross(t)
    rot=rng.random()*6.28; t,b=t*math.cos(rot)+b*math.sin(rot), -t*math.sin(rot)+b*math.cos(rot)
    vs=[bm.verts.new(c+(t*sx+b*sy)*size) for sx,sy in ((-1,-1),(1,-1),(1,1),(-1,1))]
    f=bm.faces.new(vs); f.material_index=0
    for lo,(u,v) in zip(f.loops,((0,0),(1,0),(1,1),(0,1))): lo[uv].uv=(u,v)
    return [(v,(v.co-center).normalized()) for v in vs]
def trunk(bm,uv,p,h,r,lean):
    segs=7; top=p+Vector((lean.x,lean.y,h))
    rings=[]
    for k,z in enumerate((0,0.5,1)):
        c=p.lerp(top,z); rr=r*(1-0.45*z)*(1.3 if k==0 else 1)
        rings.append([bm.verts.new(c+Vector((math.cos(i*6.283/segs)*rr,math.sin(i*6.283/segs)*rr,0))) for i in range(segs)])
    for k in range(2):
        for i in range(segs):
            j=(i+1)%segs; f=bm.faces.new((rings[k][i],rings[k][j],rings[k+1][j],rings[k+1][i])); f.material_index=1
            for lo,(u,v) in zip(f.loops,((i/segs,k/2),((i+1)/segs,k/2),((i+1)/segs,(k+1)/2),(i/segs,(k+1)/2))): lo[uv].uv=(u,v*2)
    return top
def tree(bm,uv,p,h,rng,normals,conical=False):
    lean=Vector((rng.uniform(-0.08,0.08),rng.uniform(-0.08,0.08),0))*h
    top=trunk(bm,uv,p,h*0.55,h*0.05,lean)
    cen=top+Vector((0,0,h*0.12))
    nblob=4 if not conical else 5
    for k in range(nblob):
        if conical:
            bc=p+lean+Vector((0,0,h*(0.3+0.15*k))); br=h*(0.32-0.055*k)
        else:
            a=rng.random()*6.28; bc=cen+Vector((math.cos(a),math.sin(a),rng.uniform(-0.3,0.5)))*h*0.18; br=h*rng.uniform(0.2,0.27)
        for i in range(13):
            d=Vector((rng.uniform(-1,1),rng.uniform(-1,1),rng.uniform(-0.6,1)))
            if d.length>1: d.normalize()
            c=bc+Vector((d.x*br,d.y*br,d.z*br*0.7))
            normals+=card(bm,uv,c,cen if not conical else Vector((p.x,p.y,c.z-h*0.05)),h*rng.uniform(0.17,0.24),rng)
def build(name,fn):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    lm,bk=mats()
    me=bpy.data.meshes.new(name); bm=bmesh.new(); uv=bm.loops.layers.uv.new("UV")
    normals=[]; fn(bm,uv,random.Random(sum(map(ord,name))),normals)
    vid={id(v):n for v,n in normals}
    bm.verts.index_update(); idx={v.index:n for v,n in normals}
    bm.to_mesh(me); bm.free()
    me.materials.append(lm); me.materials.append(bk)
    cn=[None]*len(me.loops)
    for poly in me.polygons:
        for li in poly.loop_indices:
            vi=me.loops[li].vertex_index
            cn[li]=idx.get(vi, None)
    for poly in me.polygons:
        poly.use_smooth=True
    normals_list=[]
    me.update()
    for li,l in enumerate(me.loops):
        normals_list.append(cn[li] if cn[li] is not None else l.normal.copy())
    me.normals_split_custom_set(normals_list)
    ob=bpy.data.objects.new(name,me); bpy.context.collection.objects.link(ob)
    bpy.ops.export_scene.gltf(filepath=OUT+name+".glb",export_format='GLB')
    print("TRIS",name,sum(len(p.vertices)-2 for p in me.polygons))
def clump(n,seed):
    def f(bm,uv,rng,normals):
        rng.seed(seed)
        for i in range(n):
            a=i*6.28/n+rng.random(); d=0 if i==0 else rng.uniform(0.45,0.7)
            tree(bm,uv,Vector((math.cos(a)*d,math.sin(a)*d,0)),rng.uniform(1.0,1.4),rng,normals,conical=rng.random()<0.25)
    return f
build("clump_a",clump(3,1)); build("clump_b",clump(4,2)); build("clump_c",clump(3,3))
build("round_a",lambda bm,uv,rng,n: tree(bm,uv,Vector(),1.3,rng,n))
build("round_red",lambda bm,uv,rng,n: tree(bm,uv,Vector(),1.2,rng,n))
build("pine_a",lambda bm,uv,rng,n: tree(bm,uv,Vector(),1.45,rng,n,True))
def bush(bm,uv,rng,normals):
    c=Vector((0,0,0.22))
    for i in range(10):
        d=Vector((rng.uniform(-1,1),rng.uniform(-1,1),rng.uniform(-0.3,1))).normalized()*0.2
        normals+=card(bm,uv,c+d,c-Vector((0,0,0.1)),rng.uniform(0.17,0.23),rng)
build("bush_a",bush)
