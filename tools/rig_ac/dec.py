import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath='/workspace/projects/bea88b3f-1bd1-496e-b7e3-25c16c4c1b3a/assets_incoming/acougueiro_tripo.glb')
me=[o for o in bpy.data.objects if o.type=='MESH'][0]
bpy.context.view_layer.objects.active=me; me.select_set(True)
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=0.0003);bpy.ops.object.mode_set(mode='OBJECT')
print('TRIS before',sum(len(p.vertices)-2 for p in me.data.polygons))
m=me.modifiers.new('d','DECIMATE');m.ratio=13000/sum(len(p.vertices)-2 for p in me.data.polygons);m.use_collapse_triangulate=True
bpy.ops.object.modifier_apply(modifier='d')
print('TRIS after',sum(len(p.vertices)-2 for p in me.data.polygons))
# scale: height 0.905 -> 2.0
s=2.0/0.905120849609375
me.scale=(s,s,s);bpy.ops.object.transform_apply(scale=True)
for im in bpy.data.images:
    if im.size[0]>1024: im.scale(1024,1024)
bpy.ops.export_scene.gltf(filepath='/workspace/work/rig_ac/ac_dec.glb',export_format='GLB',export_image_format='JPEG',export_jpeg_quality=88,export_apply=True)
