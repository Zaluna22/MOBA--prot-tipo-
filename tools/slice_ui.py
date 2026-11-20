from PIL import Image
import numpy as np
O='/workspace/work/moba-prototipo/assets/ui/'
names=['elfo','elfa','cavaleiro','orc','orca','barbaro']
def bbox(a,th=40):
    m=a.max(axis=2)>th
    cols=np.where(m.mean(0)>0.3)[0]; rows=np.where(m.mean(1)>0.3)[0]
    return cols[0],cols[-1],rows[0],rows[-1]
def split(prof,lo,hi):
    mid=(lo+hi)//2; w=(hi-lo)//8
    seg=prof[mid-w:mid+w]; return mid-w+int(np.argmin(seg))
for n in names:
    im=Image.open(f'ic_{n}.png').convert('RGB'); a=np.asarray(im).astype(int)
    x0,x1,y0,y1=bbox(a)
    g=a.mean(axis=2)
    xs=split(g[y0:y1].mean(0),x0,x1); ys=split(g[:,x0:x1].mean(1),y0,y1)
    if n=='orc': x0,x1,y0,y1,xs,ys=314,1068,22,754,692,384
    boxes=[(x0,y0,xs,ys),(xs,y0,x1,ys),(x0,ys,xs,y1),(xs,ys,x1,y1)]
    print(n,(x0,x1,y0,y1),xs,ys)
    for i,b in enumerate(boxes):
        c=im.crop(b); w,h=c.size; s=min(w,h); m=int(s*(0.09 if n=='cavaleiro' else 0.05))
        c=c.crop(((w-s)//2+m,(h-s)//2+m,(w+s)//2-m,(h+s)//2-m)).resize((128,128),Image.LANCZOS)
        c.save(O+f'sk_{n}_{i}.webp',quality=82)
    p=Image.open(f'p_{n}.png').convert('RGB'); w,h=p.size; s=min(w,h)
    p=p.crop(((w-s)//2,0,(w+s)//2,s)).resize((256,256),Image.LANCZOS)
    p.save(O+f'p_{n}.webp',quality=82)
f=Image.open('ic_forca.png').convert('RGB').resize((128,128),Image.LANCZOS); f.save(O+'sk_forca.webp',quality=82)
s=Image.open('splash.png').convert('RGB').resize((1280,714),Image.LANCZOS); s.save(O+'splash.webp',quality=78)
s.resize((960,536),Image.LANCZOS).quantize(256,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.FLOYDSTEINBERG).save(O+'boot_splash.png',optimize=True)
