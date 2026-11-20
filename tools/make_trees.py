# Procedural stylized trees (Blender, CC0/own). Run: blender -b -P tools/make_trees.py
import bpy, bmesh, random, math, colorsys
from mathutils import Vector, noise
OUT="/workspace/work/moba-prototipo/assets/nature/"
def mat():
    m=bpy.data.materials.new("tree"); m.use_nodes=True
    nt=m.node_tree; b=nt.nodes["Principled BSDF"]
    ca=nt.nodes.new("ShaderNodeVertexColor"); ca.layer_name="Col"
    nt.links.new(ca.outputs[0], b.inputs["Base Color"]); b.inputs["Roughness"].default_value=1.0
    return m
def add_blob(bm,col,c,r,base_rgb,seed):
    res=bmesh.ops.create_icosphere(bm,subdivisions=2,radius=r)
    vs=res["verts"]
    for v in vs:
        d=v.co.normalized()
        v.co = d*r*(1+0.18*noise.noise(d*2.3+Vector((seed,seed*2,0))))
        v.co.z*=0.82
        v.co+=c
    h,s,l=colorsys.rgb_to_hls(*base_rgb)
    for f in bm.faces:
        if all(v in set(vs) for v in f.verts): pass
    vset=set(vs)
    for f in bm.faces:
        if f.verts[0] in vset:
            for lo in f.loops:
                t=(lo.vert.co.z-(c.z-r))/(2*r)
                k=0.45+0.75*t
                lo[col]=(min(1,base_rgb[0]*k),min(1,base_rgb[1]*k),min(1,base_rgb[2]*k),1)
def add_trunk(bm,col,p,h,r):
    res=bmesh.ops.create_cone(bm,cap_ends=False,segments=6,radius1=r,radius2=r*0.6,depth=h)
    vset=set(res["verts"])
    for v in vset: v.co+=p+Vector((0,0,h/2))
    for f in bm.faces:
        if f.verts[0] in vset:
            for lo in f.loops: lo[col]=(0.32,0.2,0.12,1)
def add_cone(bm,col,p,h,r,rgb):
    res=bmesh.ops.create_cone(bm,cap_ends=True,segments=9,radius1=r,radius2=0.0,depth=h)
    vset=set(res["verts"])
    for v in vset: v.co+=p+Vector((0,0,h/2))
    for f in bm.faces:
        if f.verts[0] in vset:
            for lo in f.loops:
                k=0.5+0.7*(lo.vert.co.z-p.z)/h
                lo[col]=(rgb[0]*k,rgb[1]*k,rgb[2]*k,1)
GREENS=[(0.16,0.42,0.12),(0.22,0.5,0.14),(0.12,0.36,0.14),(0.3,0.55,0.15)]
def broadleaf(bm,col,p,h,rng,rgb=None):
    rgb=rgb or rng.choice(GREENS)
    add_trunk(bm,col,p,h*0.45,h*0.07)
    cr=h*0.33
    add_blob(bm,col,p+Vector((0,0,h*0.62)),cr,rgb,rng.random()*9)
    a0=rng.random()*6.28
    for i in range(3):
        a=a0+i*2.09+rng.uniform(-0.4,0.4)
        add_blob(bm,col,p+Vector((math.cos(a)*cr*0.62,math.sin(a)*cr*0.62,h*0.48+rng.random()*h*0.15)),cr*rng.uniform(0.62,0.78),rgb,rng.random()*9)
def pine(bm,col,p,h,rng):
    add_trunk(bm,col,p,h*0.25,h*0.06)
    rgb=(0.1,0.32,0.16)
    for i,(z,s) in enumerate([(0.18,0.42),(0.42,0.33),(0.64,0.22)]):
        add_cone(bm,col,p+Vector((0,0,h*z)),h*0.42,h*s*0.75,rgb)
def build(name,fn):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    me=bpy.data.meshes.new(name); bm=bmesh.new(); col=bm.loops.layers.color.new("Col")
    fn(bm,col,random.Random(hash(name)%999))
    bm.to_mesh(me); bm.free()
    for poly in me.polygons: poly.use_smooth=True
    ob=bpy.data.objects.new(name,me); bpy.context.collection.objects.link(ob); me.materials.append(mat())
    bpy.ops.export_scene.gltf(filepath=OUT+name+".glb",export_format='GLB',export_vertex_color='ACTIVE' if bpy.app.version>=(4,2,0) else None) if False else None
    try:
        bpy.ops.export_scene.gltf(filepath=OUT+name+".glb",export_format='GLB',export_colors=True)
    except TypeError:
        bpy.ops.export_scene.gltf(filepath=OUT+name+".glb",export_format='GLB')
    print("TRIS",name,sum(len(p.vertices)-2 for p in me.polygons))
def clump(seed,n):
    def f(bm,col,rng):
        rng.seed(seed)
        for i in range(n):
            a=i*6.28/n+rng.random(); d=0.0 if i==0 else rng.uniform(0.45,0.7)
            p=Vector((math.cos(a)*d,math.sin(a)*d,0))
            if rng.random()<0.3: pine(bm,col,p,rng.uniform(1.1,1.5),rng)
            else: broadleaf(bm,col,p,rng.uniform(0.9,1.3),rng)
    return f
build("clump_a",clump(1,3)); build("clump_b",clump(2,4)); build("clump_c",clump(3,3))
build("round_a",lambda bm,col,rng: broadleaf(bm,col,Vector(),1.25,rng,(0.2,0.48,0.13)))
build("round_red",lambda bm,col,rng: broadleaf(bm,col,Vector(),1.2,rng,(0.62,0.16,0.12)))
build("pine_a",lambda bm,col,rng: pine(bm,col,Vector(),1.45,rng))
def bush(bm,col,rng):
    for i in range(3):
        a=i*2.1; add_blob(bm,col,Vector((math.cos(a)*0.22,math.sin(a)*0.22,0.18)),0.26,(0.2,0.46,0.13),i)
build("bush_a",bush)
