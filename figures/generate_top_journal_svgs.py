#!/usr/bin/env python3
"""Generate and QA top-journal SVG graphical abstracts.

This repo keeps the two precedent master SVGs editable; this generator adds the
new P. gingivalis / Alzheimer's-mechanism theme and exports all available SVGs
to vector PDF + 2340x1590 PNG. It is intentionally dependency-light and reuses
`.claude/skills/biorender-svg-figure/references/helpers.py` primitives.
"""
from __future__ import annotations

import contextlib
import io
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HELPERS = ROOT / ".claude" / "skills" / "biorender-svg-figure" / "references"
sys.path.insert(0, str(HELPERS))
from helpers import *  # noqa: F401,F403

FIG = ROOT / "figures"
W, H = 1560, 1060


def esc(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def txt(x, y, s, size=8.5, fill=INK, anchor="middle", weight=None, style=None):
    T(x, y, esc(s), size, fill, anchor, weight, style)


def label(x, y, s, w=None, size=8.2):
    txt(x, y, s, size=size, fill="#5F6F7A")


def group_start(gid: str):
    add(f'<g id="{gid}">')


def group_end():
    add('</g>')


def rounded_panel(x, y, w, h, fill, stroke, gid, letter, title):
    group_start(gid)
    R(x, y, w, h, fill, stroke, 1.2, rx=18)
    C(x + 20, y + 25, 12, "url(#gNavy)")
    txt(x + 20, y + 29, letter, 12.5, "#FFFFFF", weight="bold")
    txt(x + 40, y + 29, "| " + title, 12.0, "#34495A", "start", weight="bold")


def pathogen(x, y, s=1.0):
    SHAD(x, y + 38 * s, 70 * s, 10 * s)
    # inflamed gingival pocket and tooth root
    P(f"M{x-85*s:.1f},{y+85*s:.1f} C{x-55*s:.1f},{y-5*s:.1f} {x-20*s:.1f},{y-10*s:.1f} {x+5*s:.1f},{y+70*s:.1f} C{x+28*s:.1f},{y+10*s:.1f} {x+65*s:.1f},{y+8*s:.1f} {x+92*s:.1f},{y+85*s:.1f} L{x+92*s:.1f},{y+135*s:.1f} L{x-85*s:.1f},{y+135*s:.1f} Z", fill="#F7C7C7", stroke="#C75E64", sw=1.2)
    P(f"M{x-65*s:.1f},{y-40*s:.1f} C{x-45*s:.1f},{y-70*s:.1f} {x-15*s:.1f},{y-66*s:.1f} {x-5*s:.1f},{y-32*s:.1f} C{x-18*s:.1f},{y-8*s:.1f} {x-46*s:.1f},{y-8*s:.1f} {x-65*s:.1f},{y-40*s:.1f} Z", fill="#FFFDF8", stroke="#D9CFC4", sw=1.2)
    P(f"M{x+14*s:.1f},{y-37*s:.1f} C{x+35*s:.1f},{y-69*s:.1f} {x+68*s:.1f},{y-63*s:.1f} {x+78*s:.1f},{y-27*s:.1f} C{x+63*s:.1f},{y-3*s:.1f} {x+32*s:.1f},{y-5*s:.1f} {x+14*s:.1f},{y-37*s:.1f} Z", fill="#FFFDF8", stroke="#D9CFC4", sw=1.2)
    # pocket biofilm wash
    P(f"M{x-5*s:.1f},{y+10*s:.1f} C{x+22*s:.1f},{y+30*s:.1f} {x+24*s:.1f},{y+110*s:.1f} {x-10*s:.1f},{y+122*s:.1f} C{x-38*s:.1f},{y+88*s:.1f} {x-35*s:.1f},{y+30*s:.1f} {x-5*s:.1f},{y+10*s:.1f} Z", fill="#E7B383", stroke="#B97958", sw=1.0)
    # P. gingivalis rods with fimbriae
    for i in range(12):
        bx = x - 24*s + dr(i, 3) * 54*s
        by = y + 28*s + dr(i, 9) * 82*s
        ang = -35 + dr(i, 13) * 80
        add(f'<g transform="translate({bx:.1f},{by:.1f}) rotate({ang:.1f}) scale({s:.2f})">')
        R(-17, -5, 34, 10, "url(#gPurp)", "#4B357D", 0.9, rx=5)
        PELL(-6, -3, 8, 2.5, "#FFFFFF", opacity=0.22)
        for k in range(5):
            a = -70 + k * 35
            x2 = 22 * math.cos(math.radians(a)); y2 = 17 * math.sin(math.radians(a))
            LN(0, 0, x2, y2, "#4B357D", 0.75)
        add('</g>')
    # zoom inset
    C(x-15*s, y-100*s, 74*s, "#F8FBFF", "#153B6E", 2)
    for i in range(6):
        bx = x-48*s + dr(i, 21)*70*s; by = y-124*s + dr(i,22)*48*s
        add(f'<g transform="translate({bx:.1f},{by:.1f}) rotate({-25+dr(i,5)*60:.1f}) scale({0.92*s:.2f})">')
        R(-18, -5, 36, 10, "url(#gPurp)", "#4B357D", 0.9, rx=5)
        PELL(-6, -3, 8, 2.4, "#FFFFFF", opacity=0.28)
        add('</g>')
    LN(x-36*s, y-39*s, x-62*s, y-55*s, "#1F385C", 1.2, dash="4,3")
    LN(x+20*s, y+5*s, x+32*s, y-55*s, "#1F385C", 1.2, dash="4,3")


def cargo_panel(x, y):
    # gingipain enzyme blobs with letters as redundant cue
    for i, (nm, grad, col) in enumerate([("RgpA", "gBlue", "#2B5EA7"), ("RgpB", "gTeal", "#0C7A72"), ("Kgp", "gTom", "#D63426")]):
        cx = x - 70 + i*70
        P(f"M{cx-20},{y-18} C{cx-5},{y-35} {cx+25},{y-25} {cx+23},{y-3} C{cx+20},{y+18} {cx-6},{y+25} {cx-20},{y+10} C{cx-8},{y+4} {cx-8},{y-8} {cx-20},{y-18} Z", fill=f"url(#{grad})", stroke=col, sw=1.1)
        PELL(cx-6, y-15, 11, 5, "#FFFFFF", opacity=0.38)
        txt(cx, y+36, nm, 10.0, "#22324A")
    label(x, y+58, "R/K letters + shape encode proteases")
    # OMVs
    for i in range(5):
        cx = x - 78 + i*40
        cy = y + 110 + (i % 2)*20
        C(cx, cy, 17, "#F7FBFF", "#6355B7", 1.6)
        C(cx, cy, 13, "#FFFFFF", "#7B6BD1", 0.8, dash="2,2")
        for k, col in enumerate(["#2B5EA7", "#0C7A72", "#D63426", "#5F4DA8"]):
            C(cx - 6 + (k % 2)*12, cy - 5 + (k // 2)*10, 3.1, col)
    txt(x, y+153, "outer-membrane vesicles", 10, "#22324A", weight="bold")
    label(x, y+170, "vesicle outline + cargo dots")


def blood_vessel(x, y):
    SHAD(x, y+185, 72, 11)
    P(f"M{x-62},{y} C{x-82},{y+92} {x-80},{y+236} {x-58},{y+328} L{x-35},{y+312} C{x-52},{y+215} {x-51},{y+102} {x-35},{y+14} Z", fill="#F59AA0", stroke="#C85862", sw=1.2)
    P(f"M{x+62},{y} C{x+82},{y+92} {x+80},{y+236} {x+58},{y+328} L{x+35},{y+312} C{x+52},{y+215} {x+51},{y+102} {x+35},{y+14} Z", fill="#F59AA0", stroke="#C85862", sw=1.2)
    R(x-46, y+16, 92, 296, "#FAD1D2", "#D77079", 1.0, opacity=0.75, rx=18)
    for i in range(7):
        C(x-25+dr(i,44)*50, y+36+i*36, 11, "url(#gRed)", "#B5312B", 1)
        C(x+4+dr(i,45)*39, y+55+i*33, 4.0, ["#2B5EA7", "#0C7A72", "#D63426"][i%3])
        if i % 2 == 0:
            C(x-10+dr(i,56)*35, y+47+i*36, 12, "#EFF3FC", "#9CADC7", 0.9)
            C(x-10+dr(i,56)*35, y+47+i*36, 4, "#9BAFD3")


def bbb(x, y):
    R(x-27, y+5, 54, 310, "#FFF2F4", "#D77C87", 1.2, rx=12)
    for i in range(8):
        R(x-18, y+17+i*36, 36, 24, "#F7B8C0", "#BD6975", 0.8, rx=7)
        LN(x-17, y+29+i*36, x+17, y+29+i*36, "#E57885", 1.0)
    for i in range(6):
        R(x-9, y+40+i*42, 18, 7, "#1D5F9F", "#153B6E", 0.6, rx=2)
    # astrocytes / neuron endfeet as blue branches
    for i in range(6):
        yy = y+35+i*45
        LN(x+34, yy, x+78, yy-20, "#2E83A4", 1.3)
        LN(x+60, yy-10, x+86, yy-35, "#2E83A4", 1.1)
        LN(x+59, yy-10, x+90, yy+8, "#2E83A4", 1.0)


def brain_icon(x, y):
    SHAD(x+20, y+230, 120, 14)
    # brain outline/lobes
    P(f"M{x-95},{y+125} C{x-130},{y+70} {x-78},{y+35} {x-33},{y+52} C{x-12},{y+15} {x+36},{y+23} {x+46},{y+57} C{x+94},{y+45} {x+130},{y+83} {x+108},{y+128} C{x+137},{y+171} {x+89},{y+211} {x+40},{y+195} C{x+10},{y+224} {x-40},{y+207} {x-44},{y+171} C{x-72},{y+178} {x-112},{y+159} {x-95},{y+125} Z", fill="#EFF3FA", stroke="#8FA0B8", sw=1.4)
    for k in range(9):
        x1=x-72+dr(k,70)*160; y1=y+70+dr(k,71)*110
        P(f"M{x1:.1f},{y1:.1f} C{x1+20:.1f},{y1-22:.1f} {x1+42:.1f},{y1+18:.1f} {x1+65:.1f},{y1-2:.1f}", fill="none", stroke="#C1CAD8", sw=1.0)
    P(f"M{x-35},{y+142} C{x+10},{y+113} {x+60},{y+113} {x+83},{y+142} C{x+45},{y+132} {x+9},{y+136} {x-18},{y+163} Z", fill="#D9E3F2", stroke="#8299B6", sw=1.2)
    P(f"M{x+22},{y+160} C{x+54},{y+156} {x+71},{y+177} {x+69},{y+209} C{x+48},{y+198} {x+33},{y+187} {x+22},{y+160} Z", fill="#D2DEEE", stroke="#8299B6", sw=1.1)


def neuron_callout(x, y):
    R(x, y, 294, 250, "#FBFDFF", "#153B6E", 2, rx=10)
    txt(x+147, y+29, "neuron injury", 12, "#111827", weight="bold")
    # neuron
    C(x+88, y+111, 34, "url(#gSky)", "#1F6F9B", 1.2)
    C(x+88, y+111, 9, "#2F739F")
    for ang in [-155,-110,-62,-20,28,72,125]:
        x2=x+88+70*math.cos(math.radians(ang)); y2=y+111+70*math.sin(math.radians(ang))
        LN(x+88, y+111, x2, y2, "#1F6F9B", 2.0)
        LN(x2, y2, x2+22*math.cos(math.radians(ang+25)), y2+22*math.sin(math.radians(ang+25)), "#1F6F9B", 1.2)
        LN(x2, y2, x2+20*math.cos(math.radians(ang-25)), y2+20*math.sin(math.radians(ang-25)), "#1F6F9B", 1.2)
    # plaque spiky aggregate
    cx, cy = x+220, y+92
    for k in range(24):
        a=math.radians(k*15)
        LN(cx, cy, cx+30*math.cos(a), cy+30*math.sin(a), "#9B6B2E", 0.9)
    C(cx, cy, 20, "url(#gGold)", "#8B5D28", 1.0)
    txt(cx+10, cy-42, "amyloid-β", 10, "#3B2A19")
    txt(cx+10, cy-27, "plaques", 10, "#3B2A19")
    # tau squiggle fragments
    for k in range(4):
        x0=x+190+dr(k,84)*60; y0=y+165+dr(k,85)*36
        P(f"M{x0:.1f},{y0:.1f} c10,-12 17,9 28,-2 c8,-8 15,7 24,-2", fill="none", stroke="#5F3D9A", sw=1.2)
    txt(x+230, y+188, "tau fragments", 10, "#3B2A5A")


def ache_ab_callout(x, y):
    """Compact AChE-Aβ inset that stays inside the 315-px right mechanism zone."""
    R(x, y, 286, 270, "#FBFDFF", "#153B6E", 2, rx=10)
    txt(x+143, y+28, "AChE-Aβ nucleation", 12, "#111827", weight="bold")
    # protein surface as clustered spheres
    for i in range(62):
        ang=dr(i,100)*2*math.pi; rad=dr(i,101)**0.5*72
        cx=x+144+math.cos(ang)*rad*1.12; cy=y+142+math.sin(ang)*rad*0.82
        C(cx, cy, 10.5+dr(i,102)*4.3, "url(#gSteel)", "#98A8BC", 0.52)
    # PAS patch green, surface patch amber, Aβ ribbon red; spatial position and labels provide redundant cues.
    for i in range(11): C(x+88+dr(i,110)*50, y+82+dr(i,111)*38, 13.5, "url(#gTeal)", "#0C7A72", 0.6)
    for i in range(10): C(x+130+dr(i,120)*57, y+170+dr(i,121)*36, 13.5, "url(#gAmber)", "#D98A25", 0.6)
    P(f"M{x+150},{y+112} C{x+183},{y+87} {x+201},{y+123} {x+226},{y+103} C{x+244},{y+91} {x+260},{y+90} {x+276},{y+78}", fill="none", stroke="#E64B35", sw=4.2, cap="round")
    P(f"M{x+150},{y+112} C{x+183},{y+87} {x+201},{y+123} {x+226},{y+103} C{x+244},{y+91} {x+260},{y+90} {x+276},{y+78}", fill="none", stroke="#FFD6C9", sw=1.7, cap="round")
    txt(x+47, y+73, "PAS", 10.5, "#0C7A72", "start", weight="bold")
    ARROW(x+70, y+76, x+103, y+96, "#0C7A72", 1.4, 4.5)
    txt(x+216, y+72, "Aβ peptide", 10.5, "#B82E26", "start", weight="bold")
    ARROW(x+274, y+77, x+252, y+94, "#B82E26", 1.4, 4.5)
    txt(x+28, y+230, "surface patch", 10, "#9A6119", "start")
    txt(x+28, y+246, "residues 344-361", 10, "#9A6119", "start")
    ARROW(x+131, y+220, x+149, y+186, "#9A6119", 1.4, 4.5)
    # dashed contacts
    for px,py in [(160,130),(184,121),(204,135)]:
        LN(x+px, y+py, x+158, y+178, "#263238", 1.0, dash="3,3")

def method_transcriptomics(x, y):
    txt(x, y-64, "transcriptomics", 12, "#111827", weight="bold")
    txt(x, y-47, "GEO", 12, "#111827", weight="bold")
    P(f"M{x-120},{y-20} L{x-75},{y-20} L{x-52},{y+3} L{x-52},{y+100} L{x-120},{y+100} Z", fill="#EAF7F5", stroke="#0C7A72", sw=2)
    P(f"M{x-75},{y-20} L{x-75},{y+3} L{x-52},{y+3}", fill="none", stroke="#0C7A72", sw=2)
    txt(x-88, y+39, "GEO", 18, "#0C7A72", weight="bold")
    for k in range(3): LN(x-108, y+57+k*15, x-67, y+57+k*15, "#0C7A72", 2)
    # heatmap and dendrogram
    hm_x, hm_y = x+2, y-6
    for i in range(9):
        for j in range(8):
            val = (i*17+j*9) % 31
            col = ["#E97878", "#F3B0A7", "#7BC7C1", "#2D9089", "#DDEEEE"][val % 5]
            R(hm_x+i*20, hm_y+j*18, 19, 17, col, "#FFFFFF", 0.35)
    for i in range(7): LN(hm_x-18, hm_y+i*20, hm_x-6, hm_y+i*20, "#555", 0.8)
    for i in range(5): LN(hm_x+i*34, hm_y-10, hm_x+i*34, hm_y-23, "#555", 0.8)
    label(x+90, y+157, "DEGs + inflammatory modules")


def method_docking(x, y):
    txt(x, y-47, "molecular docking", 12, "#111827", weight="bold")
    R(x-112, y-24, 224, 126, "#0B2342", "#071C35", 1.5, rx=8)
    R(x-96, y-8, 192, 92, "#F7FBFF", None, rx=3)
    # small protein/ribbon on laptop
    for i in range(26):
        C(x-20+dr(i,130)*78, y+12+dr(i,131)*52, 9, "url(#gSteel)", "#98A8BC", 0.4)
    P(f"M{x-12},{y+35} C{x+10},{y+14} {x+33},{y+43} {x+56},{y+24}", fill="none", stroke="#E64B35", sw=3, cap="round")
    R(x-132, y+102, 264, 14, "#0B2342", "#071C35", 1.2, rx=5)
    label(x, y+157, "Aβ pose on AChE surface")


def method_md(x, y):
    txt(x, y-47, "1 microsecond", 12, "#111827", weight="bold")
    txt(x, y-30, "MD simulation", 12, "#111827", weight="bold")
    C(x-115, y+45, 43, "#FFFFFF", "#164D81", 4)
    for k in range(12):
        a=math.radians(k*30)
        LN(x-115+34*math.cos(a), y+45+34*math.sin(a), x-115+43*math.cos(a), y+45+43*math.sin(a), "#164D81", 2)
    txt(x-115, y+54, "1 µs", 18, "#111827")
    # rmsd plot
    R(x-24, y-10, 205, 105, "#FFFFFF", None)
    LN(x-12, y+80, x+168, y+80, "#444", 1)
    LN(x-12, y+80, x-12, y-3, "#444", 1)
    pts=[]
    for i in range(90):
        xx=x-12+i*2.0
        yy=y+80-(16+45*(1-math.exp(-i/10))+5*math.sin(i/4)+3*math.sin(i/1.7))
        pts.append(f"{xx:.1f},{yy:.1f}")
    add(f'<polyline points="{" ".join(pts)}" fill="none" stroke="#164D81" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>')
    txt(x+75, y+108, "Time (µs)", 8.5, "#444")
    txt(x-41, y+17, "RMSD", 8.5, "#444", style="italic")
    # protein cartoon
    for k in range(4):
        P(f"M{x+235+k*5},{y+15+k*14} C{x+260},{y-6+k*14} {x+290},{y+32+k*14} {x+320},{y+7+k*14} C{x+342},{y-10+k*14} {x+360},{y+22+k*14} {x+338},{y+41+k*14}", fill="none", stroke="#7EC4D4", sw=2.2, opacity=0.8)
    P(f"M{x+242},{y+43} C{x+277},{y+15} {x+299},{y+71} {x+335},{y+42}", fill="none", stroke="#E64B35", sw=3.2, cap="round")
    label(x+143, y+157, "stable complex and trajectories")


def make_pg_ad_svg(out: Path):
    """Original BioRender-style graphical abstract for P. gingivalis -> AD.

    Strategy: do not copy the supplied reference. Build a new editorial layout:
    an S-shaped pathogenic-cargo route links a large oral niche, a vascular/BBB
    transit module, and a dense AD pathology hub, with a compact evidence ribbon.
    """
    L.clear()
    add(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" font-family="Helvetica, Arial, sans-serif" role="img" aria-labelledby="pgad-title pgad-desc">')
    add('<title id="pgad-title">P. gingivalis virulence factors connect periodontal infection to Alzheimer\'s disease mechanisms</title>')
    add('<desc id="pgad-desc">Original graphical abstract. Periodontal Porphyromonas gingivalis biofilms release gingipain proteases, outer-membrane vesicles and inflammatory mediators; these circulate through blood, stress the blood-brain barrier and converge on neuroinflammation, amyloid-beta plaques, tau fragments and acetylcholinesterase-mediated amyloid-beta nucleation. Omics, docking and molecular dynamics provide computational support.</desc>')
    build_defs(extra=(('routeGrad', [('0%', '#FCE6E8', 1), ('45%', '#E6F3F8', 1), ('100%', '#EEF3FF', 1)]),))
    R(0, 0, W, H, "#FFFFFF")
    txt(40, 38, "Oral infection-to-neurodegeneration axis", 18, "#111827", "start", "bold")
    txt(40, 60, "P. gingivalis cargo links periodontal biofilms, vascular transit, BBB stress and AChE-Aβ pathology", 11, "#5B6875", "start")
    LN(40, 76, 1520, 76, "#D8E1EA", 1.2)

    def chip(x, y, letter, title, col="#34456A"):
        C(x, y, 13, f"url(#gNavy)", "#243957", 0.8)
        txt(x, y+4, letter, 12, "#FFFFFF", weight="bold")
        txt(x+22, y+4, title, 12, col, "start", "bold")

    # Soft original route band; the story is carried by geometry, not coloured zones.
    P("M250,360 C385,220 505,230 615,330 C735,440 850,430 955,330 C1075,218 1192,260 1308,385", fill="none", stroke="#E9F0F8", sw=54, cap="round", opacity=1)
    P("M250,360 C385,220 505,230 615,330 C735,440 850,430 955,330 C1075,218 1192,260 1308,385", fill="none", stroke="#9AA8B5", sw=3.0, cap="round")
    HEAD(1308,385,1,0,"#9AA8B5",8)
    for i in range(52):
        t=i/51
        # deterministic scatter along the route corridor
        x=275 + 1000*t + 12*math.sin(20*t)
        y=355 - 95*math.sin(math.pi*t*2.0) + 40*math.sin(math.pi*t*3.2) + (dr(i,41)-0.5)*52
        C(x, y, 3.0+dr(i,42)*2.2, ["#2B5EA7", "#0C7A72", "#D63426", "#5F4DA8"][i%4])
        if i%9==0:
            C(x+8, y-6, 13, "#FFFFFF", "#6A5FC5", 1.1)
            C(x+8, y-6, 9, "#F7FBFF", "#8C82D8", 0.7, dash="2,2")
            C(x+4, y-8, 2.8, "#0C7A72"); C(x+11, y-4, 2.8, "#D63426")

    # A. Oral niche: large editorial hero with tissue layers, teeth, pocket, biofilm.
    group_start("zone-a")
    chip(52, 110, "a", "periodontal biofilm")
    SHAD(172, 625, 150, 13)
    # alveolar bone with trabeculae
    P("M20,552 C66,520 118,540 172,524 C225,508 274,536 326,514 L326,676 L20,676 Z", fill="#F3DEC9", stroke="#D6B998", sw=1.0)
    for i in range(70):
        C(35+dr(i,201)*270, 570+dr(i,202)*82, 4.0+dr(i,203)*8, "#FAEFE5", "#D4B897", 0.55)
    # gums
    P("M20,420 C70,350 124,372 166,440 C205,360 276,355 326,420 L326,560 C255,540 207,555 166,585 C112,554 65,548 20,562 Z", fill="#F8B1B8", stroke="#C75E69", sw=1.2)
    P("M94,392 C123,400 152,435 165,486 C184,427 226,397 277,393 C255,500 219,574 164,596 C113,568 83,492 94,392 Z", fill="#E98E9A", stroke="#B95763", sw=1.0)
    # teeth crowns and roots, partially behind gum
    for tx,tw in [(-5,78),(68,86),(150,88),(236,78)]:
        P(f"M{tx+8},385 C{tx-8},324 {tx+2},250 {tx+39},222 C{tx+72},197 {tx+108},230 {tx+112},294 C{tx+115},345 {tx+90},387 {tx+65},403 C{tx+39},416 {tx+18},405 {tx+8},385 Z", fill="#FFFDF8", stroke="#D7CFC4", sw=1.1)
        P(f"M{tx+36},395 C{tx+36},452 {tx+25},506 {tx+10},552 C{tx+37},565 {tx+73},565 {tx+102},552 C{tx+88},502 {tx+83},450 {tx+72},395 Z", fill="#F5EDDF", stroke="#D4C5B3", sw=0.9)
        PELL(tx+46, 255, 21, 7, "#FFFFFF", opacity=0.45)
    # periodontal pocket/biofilm wedge
    P("M156,402 C197,425 205,534 164,580 C130,536 124,424 156,402 Z", fill="#D59A68", stroke="#9B6547", sw=1.0)
    for i in range(34):
        bx=125+dr(i,210)*80; by=424+dr(i,211)*125; ang=-70+dr(i,212)*140
        add(f'<g transform="translate({bx:.1f},{by:.1f}) rotate({ang:.1f}) scale({0.62+dr(i,213)*0.22:.2f})">')
        R(-24, -6, 48, 12, "url(#gPurp)", "#4B357D", 0.8, rx=6)
        PELL(-8, -4, 11, 3, "#FFFFFF", opacity=0.25)
        for k in range(5):
            a=math.radians(k*72+15)
            LN(0, 0, 24*math.cos(a), 17*math.sin(a), "#4B357D", 0.55)
        add('</g>')
    # magnified bacterium circle
    C(175, 178, 92, "#F8FBFF", "#153B6E", 2.2)
    for i in range(92):
        C(100+dr(i,220)*150, 104+dr(i,221)*135, 1.5+dr(i,222)*1.4, ["#6C4CA5", "#2D78A6", "#B36D5C"][i%3], opacity=0.75)
    for i in range(8):
        bx=108+dr(i,225)*132; by=105+dr(i,226)*115; ang=-35+dr(i,227)*80
        add(f'<g transform="translate({bx:.1f},{by:.1f}) rotate({ang:.1f})">')
        R(-29,-7,58,14,"url(#gPurp)","#4B357D",0.95,rx=7)
        PELL(-12,-5,14,3.5,"#FFFFFF",opacity=0.30)
        for k in range(8):
            a=math.radians(k*45+10)
            LN(0,0,32*math.cos(a),22*math.sin(a),"#4B357D",0.75)
        add('</g>')
    R(151, 333, 23, 24, "none", "#263238", 1.0)
    LN(151,333,105,253,"#263238",1.0,dash="5,4"); LN(174,333,236,255,"#263238",1.0,dash="5,4")
    txt(78, 94, "P. gingivalis", 13, "#111827", "start", "bold", "italic")
    group_end()

    # B. Virulence cargo station with original compact badge row.
    group_start("zone-b")
    chip(370, 130, "b", "virulence cargo")
    R(342, 155, 235, 190, "#FFFFFF", "#CAD6E2", 1.2, rx=14)
    txt(459, 181, "gingipains", 11.5, "#1F2B3A", weight="bold")
    for i,(nm,grad,col,mark) in enumerate([("RgpA","gBlue","#2B5EA7","R"),("RgpB","gTeal","#0C7A72","R"),("Kgp","gTom","#D63426","K")]):
        cx=385+i*73
        P(f"M{cx-23},213 C{cx-8},192 {cx+25},199 {cx+25},223 C{cx+22},244 {cx-9},251 {cx-24},234 C{cx-11},228 {cx-11},219 {cx-23},213 Z", fill=f"url(#{grad})", stroke=col, sw=1.0)
        txt(cx, 228, mark, 12, "#FFFFFF", weight="bold")
        txt(cx, 270, nm, 10, "#22324A")
    LN(358, 293, 562, 293, "#E1E8EF", 1)
    txt(459, 318, "outer-membrane vesicles", 11.5, "#1F2B3A", weight="bold")
    for i in range(6):
        cx=372+i*36; cy=365+(i%2)*14
        C(cx, cy, 18, "#FFFFFF", "#5A50AA", 1.5)
        C(cx, cy, 13, "#F7FBFF", "#8C82D8", 0.8, dash="2,2")
        for k,col in enumerate(["#2B5EA7", "#0C7A72", "#D63426", "#5F4DA8"]):
            C(cx-6+(k%2)*12, cy-5+(k//2)*10, 3.0, col)
    txt(459, 425, "shape + letters provide redundant encoding", 8.5, "#6B7785")
    group_end()

    # C. Vascular transit: horizontal, less reference-like and denser.
    group_start("zone-c")
    chip(650, 136, "c", "systemic spread")
    SHAD(740, 436, 145, 12)
    P("M585,255 C640,210 848,210 910,255 L890,470 C820,510 646,510 585,470 Z", fill="#FAD2D4", stroke="#CD6871", sw=1.2)
    P("M596,267 C650,235 835,235 897,267 L880,458 C810,486 662,486 600,456 Z", fill="#F8B7BA", stroke="#E4868D", sw=0.8, opacity=0.88)
    for i in range(11):
        ex=626+dr(i,240)*235; ey=285+dr(i,241)*160
        add(f'<g transform="translate({ex:.1f},{ey:.1f}) rotate({-25+dr(i,242)*50:.1f})">')
        EL(0,0,14,10,"url(#gRed)","#B5312B",1.0)
        EL(0,0,7,4,"#E95C4D",None,opacity=0.55)
        add('</g>')
    for i in range(6):
        C(648+dr(i,245)*220, 300+dr(i,246)*138, 13, "#EFF3FC", "#9CADC7", 0.9)
        C(648+dr(i,245)*220, 300+dr(i,246)*138, 4, "#9BAFD3")
    txt(740, 526, "OMVs, gingipains and cytokines circulate with immune cells", 8.8, "#65717F")
    group_end()

    # D. Neurovascular unit / BBB: integrated barrier with astrocytes and leakage.
    group_start("zone-d")
    chip(830, 126, "d", "BBB stress")
    R(892, 180, 62, 330, "#FFF2F4", "#D77C87", 1.2, rx=18)
    for i in range(8):
        R(902, 194+i*38, 42, 26, "#F7B8C0", "#BD6975", 0.8, rx=8)
        LN(904, 207+i*38, 942, 207+i*38, "#E57885", 1.0)
    for i in range(7):
        R(918, 225+i*39, 16, 7, "#1D5F9F", "#153B6E", 0.6, rx=2)
    for i in range(7):
        yy=205+i*43
        LN(960, yy, 1028, yy-28, "#2E83A4", 1.4)
        LN(1000, yy-16, 1038, yy-48, "#2E83A4", 1.1)
        LN(1001, yy-16, 1041, yy+4, "#2E83A4", 1.1)
    for i in range(22):
        C(856+dr(i,250)*85, 295+dr(i,251)*130, 3.0+dr(i,252)*1.9, ["#2B5EA7", "#0C7A72", "#D63426"][i%3])
    txt(923, 535, "tight junctions + astrocyte endfeet", 8.8, "#65717F")
    group_end()

    # E/F. AD pathology hub: one dense right-side editorial panel, not copied.
    group_start("zone-e")
    chip(1085, 116, "e", "brain pathology hub")
    # brain silhouette as context
    brain_icon(1150, 205)
    # neuron network panel
    R(1242, 95, 292, 230, "#FBFDFF", "#153B6E", 1.8, rx=12)
    txt(1388, 125, "neuron injury", 12, "#111827", weight="bold")
    C(1330, 205, 34, "url(#gSky)", "#1F6F9B", 1.2); C(1330, 205, 9, "#2F739F")
    for ang in [-160,-120,-78,-35,15,55,92,135]:
        x2=1330+72*math.cos(math.radians(ang)); y2=205+72*math.sin(math.radians(ang))
        LN(1330,205,x2,y2,"#1F6F9B",2.0)
        LN(x2,y2,x2+22*math.cos(math.radians(ang+28)),y2+22*math.sin(math.radians(ang+28)),"#1F6F9B",1.1)
        LN(x2,y2,x2+20*math.cos(math.radians(ang-26)),y2+20*math.sin(math.radians(ang-26)),"#1F6F9B",1.1)
    # amyloid plaque and tau
    cx,cy=1458,186
    for k in range(32):
        a=math.radians(k*360/32); LN(cx,cy,cx+31*math.cos(a),cy+31*math.sin(a),"#9B6B2E",0.8)
    C(cx,cy,23,"url(#gGold)","#8B5D28",1.0)
    txt(1473, 146, "amyloid-β", 9.5, "#3B2A19"); txt(1473, 160, "plaques", 9.5, "#3B2A19")
    for k in range(5):
        x0=1422+dr(k,260)*72; y0=256+dr(k,261)*32
        P(f"M{x0:.1f},{y0:.1f} c10,-11 17,8 28,-2 c8,-8 16,7 25,-2", fill="none", stroke="#5F3D9A", sw=1.2)
    txt(1466, 254, "tau fragments", 9.5, "#3B2A5A")
    # AChE-Aβ nucleation as hero inset
    R(1218, 350, 316, 270, "#FBFDFF", "#153B6E", 1.8, rx=12)
    txt(1376, 380, "AChE-Aβ nucleation", 12, "#111827", weight="bold")
    for i in range(72):
        ang=dr(i,270)*2*math.pi; rad=dr(i,271)**0.5*80
        sx=1364+math.cos(ang)*rad*1.08; sy=485+math.sin(ang)*rad*0.80
        C(sx, sy, 10+dr(i,272)*4.2, "url(#gSteel)", "#98A8BC", 0.5)
    for i in range(13): C(1304+dr(i,275)*58, 425+dr(i,276)*42, 13.5, "url(#gTeal)", "#0C7A72", 0.6)
    for i in range(11): C(1350+dr(i,280)*62, 522+dr(i,281)*38, 13.5, "url(#gAmber)", "#D98A25", 0.6)
    P("M1370,455 C1405,430 1425,466 1454,445 C1475,430 1495,428 1522,408", fill="none", stroke="#E64B35", sw=4.2, cap="round")
    P("M1370,455 C1405,430 1425,466 1454,445 C1475,430 1495,428 1522,408", fill="none", stroke="#FFD6C9", sw=1.7, cap="round")
    txt(1276, 428, "PAS", 10, "#0C7A72", "start", weight="bold"); ARROW(1300,430,1322,442,"#0C7A72",1.3,4)
    txt(1464, 428, "Aβ peptide", 10, "#B82E26", "start", weight="bold"); ARROW(1512,430,1496,438,"#B82E26",1.3,4)
    txt(1248, 580, "residues 344-361", 9.5, "#9A6119", "start"); ARROW(1335,570,1360,535,"#9A6119",1.3,4)
    for px,py in [(1390,474),(1412,464),(1434,480)]: LN(px,py,1380,522,"#263238",1.0,dash="3,3")
    R(1168, 315, 23, 23, "none", "#1F385C", 1.1)
    LN(1191,315,1242,142,"#1F385C",1.0,dash="5,4"); LN(1191,338,1218,455,"#1F385C",1.0,dash="5,4")
    group_end()

    # G. Evidence ribbon: compact but denser and visually aligned.
    group_start("zone-g")
    R(28, 720, 1504, 252, "#FBFDFF", "#153B6E", 1.5, rx=14)
    chip(58, 750, "f", "orthogonal evidence", "#153B6E")
    method_transcriptomics(200, 845)
    LN(450, 755, 450, 925, "#AEB9C5", 1.2)
    method_docking(630, 845)
    LN(825, 755, 825, 925, "#AEB9C5", 1.2)
    method_md(995, 845)
    # small checklist for evidence convergence
    R(1335, 790, 145, 95, "#FFFFFF", "#D2DDE8", 1.0, rx=8)
    for i,(t,col) in enumerate([("DEGs", "#0C7A72"),("binding", "#E64B35"),("1 µs stable", "#153B6E")]):
        C(1353, 815+i*24, 6, col); txt(1366, 819+i*24, t, 9.2, "#4D5B68", "start")
    group_end()

    # Caption: full two-line journal format.
    txt(34, 1034, "Figure 1 |", 10.5, "#37474F", "start", "bold")
    txt(98, 1034, "An oral infection-to-neurodegeneration axis driven by P. gingivalis virulence cargo.", 10.5, "#5A6B7A", "start")
    txt(34, 1050, "Gingipains, OMVs and cytokines connect periodontal biofilms to BBB stress, neuronal injury and AChE-Aβ nucleation.", 9.0, "#7F8A96", "start")
    add('</svg>')
    out.write_text("\n".join(L), encoding="utf-8")


def fix_accessibility(svg: Path):
    """Add role/aria ids to older masters without changing artwork."""
    s = svg.read_text(encoding="utf-8")
    if 'role="img"' in s:
        return False
    stem = svg.stem.replace("_", "-")
    s = s.replace('<svg xmlns="http://www.w3.org/2000/svg"', f'<svg xmlns="http://www.w3.org/2000/svg" role="img" aria-labelledby="{stem}-title {stem}-desc"', 1)
    s = re.sub(r'<title>(.*?)</title>', fr'<title id="{stem}-title">\1</title>', s, count=1, flags=re.S)
    s = re.sub(r'<desc>(.*?)</desc>', fr'<desc id="{stem}-desc">\1</desc>', s, count=1, flags=re.S)
    svg.write_text(s, encoding="utf-8")
    return True


def qa_svg(svg: Path):
    s = svg.read_text(encoding="utf-8")
    font_sizes = [float(x) for x in re.findall(r'font-size="([0-9.]+)"', s)]
    ids = set(re.findall(r'id="([^"]+)"', s))
    refs = set(re.findall(r'url\(#([^\)]+)\)', s))
    missing = refs - ids
    assert not missing, f"{svg}: missing defs {missing}"
    assert font_sizes and min(font_sizes) >= 8.0, f"{svg}: small font {min(font_sizes)}"
    assert '<desc' in s and '<title' in s and 'role="img"' in s, f"{svg}: missing a11y metadata"
    assert not re.search(r'stroke="0\.', s), f"{svg}: positional opacity slip"
    return {"texts": len(font_sizes), "min_font": min(font_sizes), "refs": len(refs)}


def export(svg: Path):
    from svglib.svglib import svg2rlg
    from reportlab.graphics import renderPDF
    import pymupdf

    pdf = svg.with_suffix(".pdf")
    png = svg.with_suffix(".png")
    buf = io.StringIO()
    with contextlib.redirect_stderr(buf):
        drawing = svg2rlg(str(svg))
        renderPDF.drawToFile(drawing, str(pdf))
    warnings = [ln for ln in buf.getvalue().splitlines() if ln.strip()]
    doc = pymupdf.open(str(pdf))
    page = doc[0]
    pix = page.get_pixmap(matrix=pymupdf.Matrix(2.0, 2.0), alpha=False)  # svglib maps 1560x1060 px to 1170x795 pt -> 2340x1590 px
    pix.save(str(png))
    doc.close()
    return {"pdf": pdf.name, "png": png.name, "warnings": len(warnings), "warning_lines": warnings[:5]}


def main():
    make_pg_ad_svg(FIG / "pg_ad_mechanism_fig1.svg")
    changed = [p.name for p in [FIG / "amp_dl_review_fig1.svg", FIG / "umami_ml_fig1.svg", FIG / "pg_ad_mechanism_fig1.svg"] if fix_accessibility(p)]
    report = {}
    for svg in [FIG / "amp_dl_review_fig1.svg", FIG / "umami_ml_fig1.svg", FIG / "pg_ad_mechanism_fig1.svg"]:
        report[svg.name] = {"qa": qa_svg(svg), "export": export(svg)}
    pairs = [
        ("gingipain Rgp/Kgp blue-red", "#2B5EA7", "#D63426"),
        ("OMV teal-red cargo", "#0C7A72", "#D63426"),
        ("PAS patch vs surface patch", "#0C7A72", "#D98A25"),
        ("Aβ peptide vs protein surface", "#E64B35", "#7FA3C8"),
        ("heatmap teal vs salmon", "#2D9089", "#E97878"),
    ]
    cbt = cbt_audit(pairs)
    for row in cbt:
        assert row[3], f"CBT failed: {row}"
    print("accessibility patched:", changed)
    print("CBT:", cbt)
    for k, v in report.items():
        print(k, v)


if __name__ == "__main__":
    main()
