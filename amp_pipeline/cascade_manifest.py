#!/usr/bin/env python3
# Build/query the disk-backed manifest used by unique_cascade_pipeline.sh.
import argparse, csv, os, sqlite3, sys

AA = set('ACDEFGHIKLMNPQRSTVWY')

def fasta(path):
    name, seq = None, []
    with open(path, errors='replace') as f:
        for line in f:
            line=line.strip()
            if line.startswith('>'):
                if name is not None: yield name, ''.join(seq)
                name=line[1:].rstrip('\r')
                seq=[]
            elif name is not None and line: seq.append(line.upper())
    if name is not None: yield name, ''.join(seq)

def groups(root):
    out=[]
    for d, _, fs in os.walk(root):
        for x in sorted(fs):
            if x.endswith(('.fa','.fasta','.faa')) and x != 'sORF_All_Total.fa': out.append((os.path.basename(d),os.path.join(d,x)))
    return out

def main():
    p=argparse.ArgumentParser()
    p.add_argument('cmd', choices=['prepare','select','materialize'])
    p.add_argument('--grouped', required=True); p.add_argument('--work', required=True)
    p.add_argument('--max-unique', type=int, default=0)
    p.add_argument('--att'); p.add_argument('--lstm'); p.add_argument('--bert')
    p.add_argument('--mode', choices=['strict','any','all'], default='strict')
    args=p.parse_args(); os.makedirs(args.work,exist_ok=True)
    dbpath=os.path.join(args.work,'manifest.sqlite')
    if args.cmd=='prepare':
        total=os.path.join(args.grouped,'sORF_All_Total.fa')
        sources=[total] if os.path.isfile(total) else [x[1] for x in groups(args.grouped)]
        db=sqlite3.connect(dbpath); db.execute('PRAGMA journal_mode=OFF'); db.execute('PRAGMA synchronous=OFF')
        db.execute('DROP TABLE IF EXISTS seq'); db.execute('CREATE TABLE seq(uid INTEGER PRIMARY KEY, header TEXT UNIQUE, sequence TEXT, valid INTEGER, att REAL, lstm REAL)')
        out=open(os.path.join(args.work,'unique.fa'),'w'); n=0; seen=set() if not total else None
        cur=db.cursor()
        for src in sources:
            for h,s in fasta(src):
                if args.max_unique and n>=args.max_unique: break
                # The catalog is already unique. Fallback inputs are deduplicated in memory.
                if not total:
                    if s in seen: continue
                    seen.add(s)
                valid=int(bool(s) and set(s)<=AA)
                cur.execute('INSERT OR IGNORE INTO seq(uid,header,sequence,valid,att,lstm) VALUES(?,?,?,?,NULL,NULL)',(n,h,s,valid))
                if cur.rowcount:
                    out.write(f'>U{n:012d}\n{s}\n'); n+=1
            if args.max_unique and n>=args.max_unique: break
        db.commit(); out.close()
        db.execute('CREATE INDEX IF NOT EXISTS seq_header ON seq(header)'); db.commit(); db.close()
        with open(os.path.join(args.work,'sources.tsv'),'w') as f:
            for g,x in groups(args.grouped): f.write(g+'\t'+x+'\n')
        print(f'UNIQUE_COUNT={n}', flush=True)
        return
    if not os.path.exists(dbpath): raise SystemExit('manifest.sqlite not found; run prepare first')
    db=sqlite3.connect(dbpath)
    if args.cmd=='select':
        att=[float(x.strip()) for x in open(args.att) if x.strip()]
        lstm=[float(x.strip()) for x in open(args.lstm) if x.strip()]
        # uid order equals prediction order; invalid sequences were not formatted and have no scores.
        valid=[r[0] for r in db.execute('SELECT uid FROM seq WHERE valid=1 ORDER BY uid')]
        n=min(len(valid),len(att),len(lstm)); cand=[]
        db.executemany('UPDATE seq SET att=?, lstm=? WHERE uid=?', [(att[i],lstm[i],valid[i]) for i in range(n)])
        db.commit()
        for i in range(n):
            ok=(att[i]>.5 and lstm[i]>.5) if args.mode=='strict' else ((att[i]>.5 or lstm[i]>.5) if args.mode=='any' else True)
            if ok: cand.append((valid[i],att[i],lstm[i]))
        with open(os.path.join(args.work,'candidates.fa'),'w') as fa, open(os.path.join(args.work,'candidates.tsv'),'w') as tf:
            wanted={x[0] for x in cand}
            by={u:s for u,s in db.execute('SELECT uid,sequence FROM seq WHERE valid=1') if u in wanted}
            for u,a,l in cand:
                fa.write(f'>U{u:012d}\n{by[u]}\n'); tf.write(f'{u}\t{a:.8f}\t{l:.8f}\n')
        print(f'VALID_COUNT={n}\nCANDIDATE_COUNT={len(cand)}\nCANDIDATE_PERCENT={100*len(cand)/n if n else 0:.4f}',flush=True)
        return
    # materialize per-group files and final voting input
    probs={}
    for u,a,l in csv.reader(open(os.path.join(args.work,'candidates.tsv')),delimiter='\t'):
        probs[int(u)]=[float(a),float(l),None]
    # all unique att/lstm scores are joined to candidates; non-candidates cannot be 3-vote.
    bert=[float(x.strip()) for x in open(args.bert) if x.strip()]
    for i,u in enumerate(probs):
        probs[u][2]=bert[i] if i<len(bert) else 0.0
    # Grouped FASTAs are generated from the catalog, so the original header is
    # an exact key. Query the indexed SQLite table per record instead of loading
    # a 100-million-row header dictionary into RAM.
    for g,path in groups(args.grouped):
        out=os.path.join(args.work,'results',g,os.path.splitext(os.path.basename(path))[0]); os.makedirs(out,exist_ok=True)
        inp=open(os.path.join(out,'input.fa'),'w'); ap=open(os.path.join(out,'attention_proba.tsv'),'w'); lp=open(os.path.join(out,'lstm_proba.tsv'),'w'); bp=open(os.path.join(out,'bert_proba.tsv'),'w')
        count=0
        for h,s in fasta(path):
            row=db.execute('SELECT uid FROM seq WHERE header=?',(h,)).fetchone()
            if row is None: continue
            u=row[0]
            inp.write('>'+h+'\n'+s+'\n')
            score=db.execute('SELECT att,lstm FROM seq WHERE uid=?',(u,)).fetchone()
            a,l=(score if score and score[0] is not None else (0.0,0.0))
            # Missing BERT scores mean this sequence was not eligible for strict BERT.
            b=probs.get(u,(a,l,0.0))[2] or 0.0
            ap.write(f'{a:.8f}\n'); lp.write(f'{l:.8f}\n'); bp.write(f'{b:.8f}\n'); count+=1
        for x in (inp,ap,lp,bp): x.close()
        print(f'GROUP={g}\tFILE={path}\tCOUNT={count}',flush=True)
    db.close()
if __name__=='__main__': main()
