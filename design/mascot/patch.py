# patch.py base variant out x0 y0 x1 y1 : align variant to base (translation+tiny scale) around region, paste region feathered
import sys, numpy as np
from PIL import Image, ImageFilter, ImageDraw
base=Image.open(sys.argv[1]).convert('RGBA'); var=Image.open(sys.argv[2]).convert('RGBA').resize(base.size)
x0,y0,x1,y1=map(int,sys.argv[4:8])
A=np.asarray(base).astype(np.float32); 
pad=50
ref=A[y0-pad:y1+pad, x0-pad:x1+pad,:3]
best=None
V=np.asarray(var).astype(np.float32)
# use ring (exclude inner region which changed) -> compare full window but weight outer ring
h,w=ref.shape[:2]; m=np.ones((h,w),np.float32); m[pad:-pad,pad:-pad]=0.15
for s in [0.99,0.995,1.0,1.005,1.01]:
  vs=np.asarray(var.resize((round(base.size[0]*s),round(base.size[1]*s)),Image.LANCZOS)).astype(np.float32)
  off=(vs.shape[0]-A.shape[0])//2
  for dy in range(-40,41,2):
    for dx in range(-40,41,2):
      yy=y0-pad+dy+off; xx=x0-pad+dx+off
      if yy<0 or xx<0: continue
      win=vs[yy:yy+h, xx:xx+w,:3]
      if win.shape!=ref.shape: continue
      e=(np.abs(win-ref).mean(axis=2)*m).sum()
      if best is None or e<best[0]: best=(e,s,dx,dy)
e,s,dx,dy=best
# refine
vsI=var.resize((round(base.size[0]*s),round(base.size[1]*s)),Image.LANCZOS); off=(vsI.size[0]-base.size[0])//2
vs=np.asarray(vsI).astype(np.float32)
for ddy in range(dy-2,dy+3):
  for ddx in range(dx-2,dx+3):
    yy=y0-pad+ddy+off; xx=x0-pad+ddx+off
    win=vs[yy:yy+h, xx:xx+w,:3]
    if win.shape!=ref.shape: continue
    ee=(np.abs(win-ref).mean(axis=2)*m).sum()
    if ee<e: e,dx,dy=ee,ddx,ddy
print('align',s,dx,dy,e/m.sum())
shifted=Image.new('RGBA',base.size,(0,0,0,0)); shifted.paste(vsI,(-(dx+off),-(dy+off)))
mask=Image.new('L',base.size,0); ImageDraw.Draw(mask).ellipse((x0,y0,x1,y1),fill=255)
mask=mask.filter(ImageFilter.GaussianBlur(int(sys.argv[8]) if len(sys.argv)>8 else 14))
out=Image.composite(shifted,base,mask); out.save(sys.argv[3])
