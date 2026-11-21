# Gera assets/chars/Rogue_assassina_texture.png (aço escuro + azul-petróleo) a partir da textura KayKit do Rogue.
# Uso (na raiz do projeto): python3 tools/recolor_assassina.py  (precisa de Pillow + numpy)
from PIL import Image
import numpy as np
im=Image.open('assets/chars/Rogue_rogue_texture.png').convert('RGBA')
a=np.asarray(im).astype(float)/255.0
rgb=a[...,:3]; out=rgb.copy()
mx=rgb.max(2); mn=rgb.min(2); v=mx; s=np.where(mx>0,(mx-mn)/np.maximum(mx,1e-6),0)
r,g,b=rgb[...,0],rgb[...,1],rgb[...,2]
# hue in degrees
h=np.zeros_like(v)
d=np.maximum(mx-mn,1e-6)
h=np.where(mx==r,((g-b)/d)%6,np.where(mx==g,(b-r)/d+2,(r-g)/d+4))*60
lum=0.3*r+0.59*g+0.11*b
skin=np.zeros(v.shape,bool); accent=np.zeros(v.shape,bool)
C=128
for cy in range(0,v.shape[0],C):
  for cx in range(0,v.shape[1],C):
    sl=(slice(cy,cy+C),slice(cx,cx+C))
    hm=np.median(h[sl]); sm=np.median(s[sl]); vm=np.median(v[sl])
    if 5<hm<45 and vm>0.72 and sm<0.5: skin[sl]=True
    elif 90<hm<260 and sm>0.35: accent[sl]=True
steel_dark=np.array([0.035,0.04,0.05]); steel_light=np.array([0.42,0.47,0.52])
t=np.clip(lum,0,1)**1.15
steel=steel_dark+(steel_light-steel_dark)*t[...,None]
out=steel
teal_dark=np.array([0.05,0.11,0.13]); teal_light=np.array([0.30,0.48,0.55])
teal=teal_dark+(teal_light-teal_dark)*np.clip(lum*1.3,0,1)[...,None]
out=np.where(accent[...,None],teal,out)
pale=rgb*0.55+np.array([0.80,0.80,0.84])*lum[...,None]*0.5
out=np.where(skin[...,None],np.clip(pale,0,1),out)
res=np.concatenate([out,a[...,3:]],2)
Image.fromarray((res*255).astype(np.uint8),'RGBA').save('assets/chars/Rogue_assassina_texture.png')
