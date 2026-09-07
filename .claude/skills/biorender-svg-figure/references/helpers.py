#!/usr/bin/env python3
"""Shared primitives for BioRender-style SVG figure generators.

Import into a generator script:

    from helpers import *   # add, T, R, C, EL, P, LN, ARROW, SPH, SHAD, ...

Every helper appends one SVG fragment to the global list `L`; the generator
writes "\\n".join(L) into <svg>…</svg> after calling build_defs().
All opacity is emitted as fill-opacity / stroke-opacity (renderer-safe).
"""
import math

INK="#37474F"; GRAY="#7F8A96"; LGRAY="#B7C0CA"; RULE="#E3E9EF"
CORAL="#E64B35"; TEAL="#0E8F86"; NAVY="#3B4A6B"; SKY="#3E8EC4"; AMBER="#F0A63C"
PURP="#7A63B8"; GREEN="#5CA83C"; PINK="#E36B9B"; GOLD="#E8B31A"

L=[]
def add(s): L.append(s)

def _mid(a,b):
    p=lambda s,n:int(s[n:n+2],16)
    return "#%02X%02X%02X"%tuple((p(a[1:],i)+p(b[1:],i))//2 for i in (0,2,4))

def GRAD(gid,stops,radial=False,cx=0.5,cy=0.5,r=0.7):
    if radial:
        add(f'<radialGradient id="{gid}" cx="{cx}" cy="{cy}" r="{r}">' +
            ''.join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{op}"/>'
                    for o,c,op in stops)+'</radialGradient>')
    else:
        add(f'<linearGradient id="{gid}" x1="0" y1="0" x2="0" y2="1">' +
            ''.join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{op}"/>'
                    for o,c,op in stops)+'</linearGradient>')

# name: (light, deep) — the BioRender candy palette
PALETTE={"gBlue":("#9EC7FF","#2B5EA7"),"gRed":("#FFB4A0","#C43D2B"),
    "gGray":("#FFFFFF","#A9B2BC"),"gTeal":("#9FE3DA","#0C7A72"),
    "gAmber":("#FFDF9E","#D98A25"),"gPurp":("#C9BDF0","#5F4DA8"),
    "gGreen":("#C2E8A0","#4C8F2E"),"gNavy":("#8FA6CF","#34456A"),
    "gSky":("#BFE3FA","#2E7BB5"),"gSteel":("#EEF4FB","#7FA3C8"),
    "gGold":("#FFE9A8","#D9970C"),"gGlass":("#FFFFFF","#C9D4DE"),
    "gTom":("#FF9C86","#D63426"),"gPink2":("#F9CBDD","#D9719F"),
    "gLeaf":("#B4E39A","#5FA244"),"gScreen":("#3A5170","#1D2C42")}

def build_defs(extra=()):
    """Emit <defs> with the full palette (3-stop radial, highlight at .35/.30)."""
    add('<defs>')
    for nm,(c1,c2) in PALETTE.items():
        GRAD(nm,[("0%",c1,1),("55%",_mid(c1,c2),1),("100%",c2,1)],True,0.35,0.3,0.85)
    for nm,stops in extra: GRAD(nm,stops)
    add('</defs>')

# ---------- text / shapes ----------
def T(x,y,s,size=8.5,fill=INK,anchor="middle",weight=None,style=None):
    a=f'x="{x:.1f}" y="{y:.1f}" font-size="{size}" fill="{fill}" text-anchor="{anchor}"'
    if weight:a+=f' font-weight="{weight}"'
    if style:a+=f' font-style="{style}"'
    add(f'<text {a}>{s}</text>')
def R(x,y,w,h,fill="none",stroke=None,sw=1,dash=None,opacity=None,rx=0):
    a=f'x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" fill="{fill}"'
    if stroke:a+=f' stroke="{stroke}" stroke-width="{sw}"'
    if dash:a+=f' stroke-dasharray="{dash}"'
    if opacity is not None and fill!="none":a+=f' fill-opacity="{opacity}"'
    elif opacity is not None:a+=f' stroke-opacity="{opacity}"'
    if rx:a+=f' rx="{rx}"'
    add(f'<rect {a}/>')
def C(cx,cy,r,fill="none",stroke=None,sw=1,dash=None,opacity=None):
    a=f'cx="{cx:.1f}" cy="{cy:.1f}" r="{r}" fill="{fill}"'
    if stroke:a+=f' stroke="{stroke}" stroke-width="{sw}"'
    if dash:a+=f' stroke-dasharray="{dash}"'
    if opacity is not None and fill!="none":a+=f' fill-opacity="{opacity}"'
    elif opacity is not None:a+=f' stroke-opacity="{opacity}"'
    add(f'<circle {a}/>')
def EL(cx,cy,rx,ry,fill="none",stroke=None,sw=1,dash=None,opacity=None):
    a=f'cx="{cx:.1f}" cy="{cy:.1f}" rx="{rx:.1f}" ry="{ry:.1f}" fill="{fill}"'
    if stroke:a+=f' stroke="{stroke}" stroke-width="{sw}"'
    if dash:a+=f' stroke-dasharray="{dash}"'
    if opacity is not None and fill!="none":a+=f' fill-opacity="{opacity}"'
    elif opacity is not None:a+=f' stroke-opacity="{opacity}"'
    add(f'<ellipse {a}/>')
def P(d,fill="none",stroke=INK,sw=1,cap=None,join=None,dash=None,opacity=None):
    a=f'd="{d}" fill="{fill}"'
    if stroke:a+=f' stroke="{stroke}" stroke-width="{sw}"'
    if cap:a+=f' stroke-linecap="{cap}"'
    if join:a+=f' stroke-linejoin="{join}"'
    if dash:a+=f' stroke-dasharray="{dash}"'
    if opacity is not None and fill!="none":a+=f' fill-opacity="{opacity}"'
    elif opacity is not None:a+=f' stroke-opacity="{opacity}"'
    add(f'<path {a}/>')
def LN(x1,y1,x2,y2,stroke=INK,sw=1,dash=None,cap="round",opacity=None):
    a=f'x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="{cap}"'
    if dash:a+=f' stroke-dasharray="{dash}"'
    if opacity is not None:a+=f' stroke-opacity="{opacity}"'
    add(f'<line {a}/>')
def HEAD(x,y,dx,dy,fill,size=6):
    px,py=-dy,dx
    add(f'<polygon points="{x:.1f},{y:.1f} {x-dx*size+px*size*0.5:.1f},'
        f'{y-dy*size+py*size*0.5:.1f} {x-dx*size-px*size*0.5:.1f},'
        f'{y-dy*size-py*size*0.5:.1f}" fill="{fill}"/>')
def ARROW(x1,y1,x2,y2,stroke=GRAY,sw=2.2,size=6.5,dash=None):
    LN(x1,y1,x2,y2,stroke,sw,dash)
    dx,dy=x2-x1,y2-y1; n=math.hypot(dx,dy) or 1
    HEAD(x2,y2,dx/n,dy/n,stroke,size)

# ---------- glossy combos ----------
def PELL(x,y,rx,ry,fill,opacity=None,stroke=None,sw=1):
    P(f'M{x-rx:.1f},{y:.1f} a{rx:.1f},{ry:.1f} 0 1 0 {2*rx:.1f},0 '
      f'a{rx:.1f},{ry:.1f} 0 1 0 {-2*rx:.1f},0 Z',fill=fill,stroke=stroke,sw=sw,opacity=opacity)
def PCIR(x,y,r,fill,opacity=None,stroke=None,sw=1):
    PELL(x,y,r,r,fill,opacity,stroke,sw)
def SPH(x,y,r,g,stroke=None,sw=1):
    """Glossy ball: radial-gradient circle + white sheen."""
    C(x,y,r,f'url(#{g})',stroke,sw)
    PELL(x-r*0.3,y-r*0.38,r*0.42,r*0.27,"#FFFFFF",opacity=0.5)
def SHAD(x,y,rx,ry):
    """Contact shadow: two nested translucent ellipses."""
    PELL(x,y,rx,ry,"#31506B",opacity=0.09)
    PELL(x,y,rx*0.6,ry*0.6,"#31506B",opacity=0.06)
def dr(i,seed):
    """Deterministic pseudo-random in [0,1) for jittered icon details."""
    v=math.sin(i*12.9898+seed*78.233)*43758.5453
    return v-math.floor(v)
def sparkle(x,y,r,col=GOLD,op=1):
    P(f'M{x},{y-r} L{x+r*0.24},{y-r*0.24} L{x+r},{y} L{x+r*0.24},{y+r*0.24} '
      f'L{x},{y+r} L{x-r*0.24},{y+r*0.24} L{x-r},{y} L{x-r*0.24},{y-r*0.24} Z',
      fill=col,opacity=op)
def star5(x,y,r):
    pts=[f'{x+(r if k%2==0 else r*0.45)*math.cos(math.radians(-90+k*36)):.1f},'
         f'{y+(r if k%2==0 else r*0.45)*math.sin(math.radians(-90+k*36)):.1f}'
         for k in range(10)]
    add(f'<polygon points="{" ".join(pts)}" fill="url(#gGold)" stroke="#C98F0A" '
        f'stroke-width="0.8" stroke-linejoin="round"/>')
    PELL(x-r*0.25,y-r*0.3,r*0.3,r*0.18,"#FFFFFF",opacity=0.65)

# ---------- colour-blind safety (top-journal audits) ----------
def _hex2rgb(h): return tuple(int(h[i:i+2],16)/255 for i in (1,3,5))
def _lab(rgb):
    lin=[c/12.92 if c<=0.04045 else ((c+0.055)/1.055)**2.4 for c in rgb]
    X=(0.4124*lin[0]+0.3576*lin[1]+0.1805*lin[2])/0.95047
    Y=0.2126*lin[0]+0.7152*lin[1]+0.0722*lin[2]
    Z=(0.0193*lin[0]+0.1192*lin[1]+0.9505*lin[2])/1.08883
    f=lambda t:t**(1/3) if t>0.008856 else 7.787*t+16/116
    fx,fy,fz=f(X),f(Y),f(Z)
    return (116*fy-16,500*(fx-fy),200*(fy-fz))
def deuteranopia(rgb):
    """Vienot 1999 deuteranope simulation of an sRGB triplet."""
    r,g,b=rgb; return (0.625*r+0.375*g,0.7*r+0.3*g,0.3*g+0.7*b)
def deltaE(a,b,vision="normal"):
    """CIE76 deltaE between two hex colours, optionally deuteranopia-simulated."""
    f=deuteranopia if vision=="deuteranopia" else (lambda c:c)
    A,B=_lab(f(_hex2rgb(a))),_lab(f(_hex2rgb(b)))
    return math.sqrt(sum((A[i]-B[i])**2 for i in range(3)))
def cbt_audit(pairs):
    """pairs: [(name, hexA, hexB), ...] -> [(name, dE, dE_deut, passed)].
    Pass rule for INFORMATIONAL colours: dE_deut>=25, or >=15 with dE>=25.
    Decorative tints are exempt (WCAG 1.4.1: never colour alone)."""
    out=[]
    for nm,a,b in pairs:
        n1,n2=deltaE(a,b),deltaE(a,b,"deuteranopia")
        out.append((nm,round(n1,1),round(n2,1),n2>=25 or (n2>=15 and n1>=25)))
    return out

def zone_scaffold(zones):
    """zones: list of (x,y,w,h,chip_grad,letter,title,tint_fill,tint_border).
    Emits tinted panels + letter chips + titles; returns nothing."""
    for (zx,zy,zw,zh,cg,let,title,tf,tb) in zones:
        R(zx,zy,zw,zh,tf,tb,1.2,rx=16)
        C(zx+18,zy+22,11,f'url(#{cg})')
        T(zx+18,zy+26,let,12.5,"#FFFFFF",weight="bold")
        T(zx+38,zy+26,"| "+title,12,"#44555F","start",weight="bold")

if __name__=="__main__":   # smoke test: renders a mini card of primitives
    add('<svg xmlns="http://www.w3.org/2000/svg" width="420" height="200" '
        'viewBox="0 0 420 200" font-family="Helvetica, Arial, sans-serif">')
    build_defs()
    R(0,0,420,200,"#FFFFFF")
    for k,nm in enumerate(["gBlue","gRed","gTeal","gAmber","gPurp","gGreen"]):
        SPH(40+k*60,70,18,nm)
    SHAD(210,150,120,14); star5(160,140,14); sparkle(260,140,10)
    add('</svg>')
    print("cbt:", cbt_audit([("bead blue vs red","#2B5EA7","#C43D2B")]))
    open('/tmp/helpers_smoke.svg','w').write("\n".join(L))
    print("smoke svg ->", '/tmp/helpers_smoke.svg', len(L), "elements")
