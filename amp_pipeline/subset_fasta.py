#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
subset_fasta.py —— 从 FASTA 取出前 N 条序列, 输出到 stdout.
用法: python3 subset_fasta.py <input.fa> <N>
默认 N=20。
"""
import sys


def main():
    if len(sys.argv) < 2:
        sys.exit("用法: python3 subset_fasta.py <input.fa> <N>")
    src = sys.argv[1]
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 20

    out = []
    with open(src) as f:
        hdr = None
        seq = []
        for line in f:
            line = line.rstrip("\n")
            if line.startswith(">"):
                if hdr is not None and len(out) < n:
                    out.append((hdr, "".join(seq)))
                hdr = line
                seq = []
            else:
                if hdr is not None:
                    seq.append(line.strip())
        if hdr is not None and len(out) < n:
            out.append((hdr, "".join(seq)))

    for h, s in out:
        print(h)
        print(s)


if __name__ == "__main__":
    main()
