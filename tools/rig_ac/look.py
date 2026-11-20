import pygltflib,numpy as np,io,sys
from PIL import Image
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection
g=pygltflib.GLTF2().load(sys.argv[1] if len(sys.argv)>1 else 'ac_dec.glb'); blob=g.binary_blob()
def acc(i):
    a=g.accessors[i];bv=g.bufferViews[a.bufferView]
    n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a.type];dt={5126:np.float32,5125:np.uint32,5123:np.uint16}[a.componentType]
    x=np.frombuffer(blob,dt,a.count*n,(bv.byteOffset or 0)+(a.byteOffset or 0));return x.reshape(a.count,n) if n>1 else x
p=g.meshes[0].primitives[0]
P=acc(p.attributes.POSITION);UV=acc(p.attributes.TEXCOORD_0);F=acc(p.indices).reshape(-1,3)
ti=g.materials[p.material].pbrMetallicRoughness.baseColorTexture.index; im=g.images[g.textures[ti].source]
bv=g.bufferViews[im.bufferView];T=np.asarray(Image.open(io.BytesIO(blob[bv.byteOffset:bv.byteOffset+bv.byteLength])).convert('RGB'))/255.
print('tex',T.shape)
uv=UV[F].mean(1);h,w,_=T.shape
col=T[np.clip((uv[:,1]*h).astype(int),0,h-1),np.clip((uv[:,0]*w).astype(int),0,w-1)]
V=P[F]
fig,axs=plt.subplots(1,3,figsize=(21,8))
for ax,(xa,ya,da,sgn,t) in zip(axs,[(0,1,2,1,'front (+z toward viewer)'),(2,1,0,-1,'side from -x: horizontal=z'),(0,1,2,-1,'back')]):
    o=np.argsort(sgn*V[:,:,da].mean(1))
    pc=PolyCollection(V[o][:,:,[xa,ya]],facecolors=col[o],edgecolors='none');ax.add_collection(pc)
    ax.set_xlim(-1.2,1.2);ax.set_ylim(0,2.05);ax.set_aspect('equal');ax.grid(True,alpha=0.4);ax.set_xticks(np.arange(-1.2,1.21,0.1));ax.set_yticks(np.arange(0,2.05,0.1));ax.tick_params(labelsize=6);ax.set_title(t)
plt.tight_layout();plt.savefig('/tmp/look.png',dpi=80)
