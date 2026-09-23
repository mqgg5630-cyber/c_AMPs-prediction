#!/usr/bin/env python3
"""md2docx.py - render a (simple) Markdown report to .docx with real tables.
Supports: # headings, paragraphs, - bullets, 1. numbered, | tables |, ``` code, **bold**, `code`, --- rules.
Usage: python3 md2docx.py in.md out.docx
"""
import re, sys
from docx import Document
from docx.shared import Pt, RGBColor, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn

src, dst = sys.argv[1], sys.argv[2]
doc = Document()
for s in doc.sections:
    s.left_margin = s.right_margin = Cm(2.2); s.top_margin = s.bottom_margin = Cm(2.2)
st = doc.styles['Normal']; st.font.name = 'Calibri'; st.font.size = Pt(10.5)
st.element.rPr.rFonts.set(qn('w:eastAsia'), '微软雅黑')
for name, size in (('Heading 1', 16), ('Heading 2', 13.5), ('Heading 3', 12)):
    h = doc.styles[name]; h.font.size = Pt(size); h.font.color.rgb = RGBColor(0x1F, 0x3A, 0x5F)
    h.element.rPr.rFonts.set(qn('w:eastAsia'), '微软雅黑')

def add_runs(par, text):
    # **bold** and `code`
    for tok in re.split(r'(\*\*[^*]+\*\*|`[^`]+`)', text):
        if not tok: continue
        if tok.startswith('**'): r = par.add_run(tok[2:-2]); r.bold = True
        elif tok.startswith('`'): r = par.add_run(tok[1:-1]); r.font.name = 'Consolas'; r.font.size = Pt(9.5)
        else: par.add_run(tok)

def add_table(rows):
    header, body = rows[0], [r for r in rows[1:] if not re.match(r'^[\s:|-]+$', '|'.join(r))]
    t = doc.add_table(rows=1 + len(body), cols=len(header)); t.style = 'Light Grid Accent 1'
    for j, c in enumerate(header):
        cell = t.rows[0].cells[j]; cell.text = ''; p = cell.paragraphs[0]; add_runs(p, c); p.runs[0].bold = True if p.runs else None
    for i, row in enumerate(body, 1):
        for j in range(len(header)):
            cell = t.rows[i].cells[j]; cell.text = ''; p = cell.paragraphs[0]
            add_runs(p, row[j] if j < len(row) else '')
            if re.match(r'^[\d,.\s%*-]+$', row[j] if j < len(row) else ''): p.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    for row in t.rows:
        for cell in row.cells:
            for p in cell.paragraphs:
                for r in p.runs: r.font.size = Pt(9)
    doc.add_paragraph()

lines = open(src, encoding='utf-8').read().splitlines()
i = 0; table = []; code = None
while i < len(lines):
    ln = lines[i]
    if code is not None:
        if ln.startswith('```'):
            p = doc.add_paragraph(); r = p.add_run('\n'.join(code)); r.font.name = 'Consolas'; r.font.size = Pt(8.5)
            p.paragraph_format.left_indent = Cm(0.5); code = None
        else: code.append(ln)
        i += 1; continue
    if ln.strip().startswith('|'):
        table.append([c.strip() for c in ln.strip().strip('|').split('|')]); i += 1
        if i == len(lines) or not lines[i].strip().startswith('|'): add_table(table); table = []
        continue
    if ln.startswith('```'): code = []; i += 1; continue
    if not ln.strip(): i += 1; continue
    if ln.startswith('---'): i += 1; continue
    m = re.match(r'^(#+)\s+(.*)', ln)
    if m:
        lvl = min(len(m.group(1)), 3)
        if lvl == 1 and i == 0: doc.add_heading(m.group(2), 0)
        else: doc.add_heading(m.group(2), lvl)
        i += 1; continue
    m = re.match(r'^(\s*)[-*]\s+(.*)', ln)
    if m:
        p = doc.add_paragraph(style='List Bullet 2' if m.group(1) else 'List Bullet'); add_runs(p, m.group(2)); i += 1; continue
    m = re.match(r'^\s*\d+\.\s+(.*)', ln)
    if m:
        p = doc.add_paragraph(style='List Number'); add_runs(p, m.group(1)); i += 1; continue
    if ln.startswith('>'):
        p = doc.add_paragraph(); add_runs(p, ln.lstrip('> ')); p.paragraph_format.left_indent = Cm(0.8)
        for r in p.runs: r.italic = True
        i += 1; continue
    p = doc.add_paragraph(); add_runs(p, ln.strip()); i += 1
doc.save(dst); print('OK:', dst)
