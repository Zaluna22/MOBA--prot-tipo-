import json,struct,numpy as np
from scipy.spatial.transform import Rotation as Rr
f=open('/workspace/work/moba-prototipo/assets/_src/UAL1_Standard.glb','rb').read()
l=struct.unpack('<I',f[12:16])[0];J=json.loads(f[20:20+l])
N=J['nodes'];sk=J['skins'][0]
par={}
for i,n in enumerate(N):
    for c in n.get('children',[]): par[c]=i
def Rq(q): return Rr.from_quat(q)
def loc(i):
    n=N[i];return Rq(n.get('rotation',[0,0,0,1])),np.array(n.get('translation',[0,0,0]),float),np.array(n.get('scale',[1,1,1]),float)
# T-pose world (ignore near-1 scales)
WT={};PT={}
def fk(i):
    if i in WT: return
    r,t,s=loc(i)
    if i in par:
        fk(par[i]);WT[i]=WT[par[i]]*r;PT[i]=PT[par[i]]+WT[par[i]].apply(t)
    else: WT[i]=r;PT[i]=t
for i in range(len(N)): fk(i)
name={n['name']:i for i,n in enumerate(N)}
for k in ['pelvis','Head','upperarm_l','lowerarm_l','hand_l','thigh_l','calf_l','foot_l','ball_l','ball_leaf_l','neck_01','spine_03']:
    print(k,np.round(PT[name[k]],3))
Y0=0.95
T={ # acougueiro targets (glTF, feet y=0, faces +z)
'pelvis':(0,0.68,0.0),'spine_01':(0,0.82,0.03),'spine_02':(0,1.0,0.05),'spine_03':(0,1.2,0.05),'neck_01':(0,1.47,0.15),'Head':(0,1.6,0.25),
'clavicle_l':(0.12,1.42,0.08),'upperarm_l':(0.46,1.44,0.05),'lowerarm_l':(0.85,1.24,0.02),'hand_l':(1.0,1.0,0.1),
'thigh_l':(0.33,0.62,0.05),'calf_l':(0.38,0.36,0.05),'foot_l':(0.4,0.12,-0.02),'ball_l':(0.42,0.04,0.2),'ball_leaf_l':(0.43,0.03,0.32),
}
for k in list(T):
    if k.endswith('_l'):
        x,y,z=T[k];T[k[:-2]+'_r']=(-x,y,z)
T.update({'lowerarm_r':(-0.8,1.22,0.05),'hand_r':(-0.95,0.95,0.2),'thigh_r':(-0.33,0.62,0.05),'calf_r':(-0.4,0.36,0.05),'foot_r':(-0.42,0.12,-0.02),'ball_r':(-0.44,0.04,0.2),'ball_leaf_r':(-0.45,0.03,0.32)})
T={k:np.array(v,float) for k,v in T.items()}
# extra targets for direction of leaf bones
tipT={'hand_l':np.array([1.03,0.85,0.14]),'Head':np.array([0,1.92,0.27]),'hand_r':np.array([-0.97,0.83,0.28])}
joints=sk['joints']
def child_main(i):
    cs=[c for c in N[i].get('children',[]) if N[c]['name'] in T]
    return cs[0] if len(cs)==1 else None
WA={};PA={};Q={}
order=[]
def visit(i):
    order.append(i)
    for c in N[i].get('children',[]): visit(c)
visit(name['root'])
PA[name['root']]=PT[name['root']];WA[name['root']]=WT[name['root']];Q[name['root']]=Rr.identity()
scale_hand=1.0
for i in order[1:]:
    nm=N[i]['name'];p=par[i]
    if nm in T: PA[i]=T[nm]
    else: PA[i]=PA[p]+Q[p].apply(PT[i]-PT[p])
    # swing
    c=child_main(i)
    tgt=None
    if c is not None: a=PT[c]-PT[i]; b=T[N[c]['name']]-PA[i]
    elif nm in tipT:
        # T-pose tip direction = along bone y axis of T frame
        a=WT[i].apply([0,1,0]); b=tipT[nm]-PA[i]
    else: a=None
    if a is not None and np.linalg.norm(b)>1e-6:
        a=a/np.linalg.norm(a);b=b/np.linalg.norm(b)
        v=np.cross(a,b);s=np.linalg.norm(v);cth=np.dot(a,b)
        Q[i]=Rr.from_rotvec(v/s*np.arctan2(s,cth)) if s>1e-8 else Rr.identity()
    else: Q[i]=Q[p]
    WA[i]=Q[i]*WT[i]
# new node translations: offset in parent's A frame
newT={}
for i in order[1:]:
    p=par[i]; newT[i]=WA[p].inv().apply(PA[i]-PA[p]).tolist()
out={'nodes':{},'joints':joints}
for i in order:
    out['nodes'][i]={'name':N[i]['name'],'parent':par.get(i),'PA':PA[i].tolist(),'WA':WA[i].as_quat().tolist(),'newT':newT.get(i,N[i].get('translation',[0,0,0]))}
json.dump(out,open('rig.json','w'))
print('ok', np.round(PA[name['hand_l']],3), np.round(PA[name['index_04_leaf_l']],3))
