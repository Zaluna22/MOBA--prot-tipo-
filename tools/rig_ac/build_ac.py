import json,numpy as np,pygltflib,io
from pygltflib import GLTF2,Node,Skin,Accessor,BufferView
from scipy.spatial import cKDTree
from scipy.spatial.transform import Rotation as Rr
from PIL import Image
g=GLTF2().load('ac_src.glb'); blob=bytearray(g.binary_blob())
R=json.load(open('rig.json')); nodes={int(k):v for k,v in R['nodes'].items()}
W=json.load(open('weights.json'))
def acc(i):
    a=g.accessors[i];bv=g.bufferViews[a.bufferView]
    n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a.type];dt={5126:np.float32,5125:np.uint32,5123:np.uint16}[a.componentType]
    return np.frombuffer(blob,dt,a.count*n,(bv.byteOffset or 0)+(a.byteOffset or 0)).reshape(a.count,n) if n>1 else np.frombuffer(blob,dt,a.count,(bv.byteOffset or 0)+(a.byteOffset or 0))
prim=g.meshes[0].primitives[0]
P=acc(prim.attributes.POSITION).copy(); 
# rewrite position accessor in place
newblob=bytearray()
def add(arr,target=None):
    global newblob
    while len(newblob)%4: newblob+=b'\0'
    off=len(newblob);b=arr.tobytes();newblob+=b
    g.bufferViews.append(BufferView(buffer=0,byteOffset=off,byteLength=len(b),target=target));return len(g.bufferViews)-1
# copy old blob first, but shrink images
oldviews=list(g.bufferViews)
g.bufferViews=[]
imgview={im.bufferView for im in g.images}
for k,bv in enumerate(oldviews):
    data=bytes(blob[(bv.byteOffset or 0):(bv.byteOffset or 0)+bv.byteLength])
    if k in imgview:
        im=Image.open(io.BytesIO(data));print('img',im.size,im.mode,len(data))
        im=im.resize((1024,1024),Image.LANCZOS);o=io.BytesIO()
        if im.mode in('RGBA','LA') : im.save(o,'PNG',optimize=True)
        else: im.convert('RGB').save(o,'JPEG',quality=88)
        data=o.getvalue()
        for gi in g.images:
            if gi.bufferView==k: gi.mimeType='image/png' if im.mode in('RGBA','LA') else 'image/jpeg'
    while len(newblob)%4: newblob+=b'\0'
    g.bufferViews.append(BufferView(buffer=0,byteOffset=len(newblob),byteLength=len(data),target=bv.target,byteStride=bv.byteStride));newblob+=data
pv=add(P.astype(np.float32),34962)
pa=g.accessors[prim.attributes.POSITION];pa.bufferView=pv;pa.byteOffset=0;pa.min=P.min(0).tolist();pa.max=P.max(0).tolist()
# weights
joints=R['joints']; jname=[nodes[j]['name'] for j in joints]; jidx={n:i for i,n in enumerate(jname)}
WP=np.array([[x[0][0],x[0][2],-x[0][1]] for x in W]); tree=cKDTree(WP); d,ix=tree.query(P)
print('maxdist',d.max())
JI=np.zeros((len(P),4),np.uint16);WW=np.zeros((len(P),4),np.float32)
for v,k in enumerate(ix):
    ws=sorted(W[k][1],key=lambda t:-t[1])[:4];s=sum(w for _,w in ws)
    for m,(n,w) in enumerate(ws): JI[v,m]=jidx[n];WW[v,m]=w/s
g.accessors.append(Accessor(bufferView=add(JI,34962),componentType=5123,count=len(P),type='VEC4'));prim.attributes.JOINTS_0=len(g.accessors)-1
g.accessors.append(Accessor(bufferView=add(WW,34962),componentType=5126,count=len(P),type='VEC4'));prim.attributes.WEIGHTS_0=len(g.accessors)-1
# skeleton nodes
base=len(g.nodes); m={}
order=sorted(nodes); ROOT=[i for i in nodes if nodes[i]['name']=='root'][0]
for i in order: m[i]=base+len(m)
for i in order:
    v=nodes[i];kids=[m[c] for c in order if nodes[c]['parent']==i]
    from json import loads
    q=None
    g.nodes.append(Node(name=v['name'],children=kids or None,translation=v['newT']))
# rotations from UAL
import struct
f=open('/workspace/work/moba-prototipo/assets/_src/UAL1_Standard.glb','rb').read();l=struct.unpack('<I',f[12:16])[0];UJ=json.loads(f[20:20+l])
for i in order:
    r=UJ['nodes'][i].get('rotation')
    if r: g.nodes[m[i]].rotation=r
    if nodes[i]['name']=='root': g.nodes[m[i]].translation=None
IBM=[]
for j in joints:
    M=np.eye(4);M[:3,:3]=Rr.from_quat(nodes[j]['WA']).as_matrix();M[:3,3]=nodes[j]['PA']
    IBM.append(np.linalg.inv(M).T.reshape(-1))
IBM=np.array(IBM,np.float32)
g.accessors.append(Accessor(bufferView=add(IBM),componentType=5126,count=len(joints),type='MAT4'))
g.skins=[Skin(name='Armature',joints=[m[j] for j in joints],inverseBindMatrices=len(g.accessors)-1,skeleton=m[ROOT])]
meshnode=[k for k,n in enumerate(g.nodes) if n.mesh is not None][0]
g.nodes[meshnode].skin=0
for k in ['translation','rotation','scale']: setattr(g.nodes[meshnode],k,None)
g.nodes.append(Node(name='Armature',children=[meshnode,m[ROOT]]))
g.scenes[0].nodes=[len(g.nodes)-1]
g.buffers[0].byteLength=len(newblob);g.set_binary_blob(bytes(newblob))
g.save('ac_rigged.glb');import os;print('size',os.path.getsize('ac_rigged.glb'))
