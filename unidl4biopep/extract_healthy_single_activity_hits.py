#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""健康人组 22 个模型分别提取脚本。

这是 extract_single_activity_hits.py 的便捷入口，默认固定处理
Healthy_Specific。每个模型独立筛选 prob > 0.8，并生成一个 FASTA。
"""

import sys

from extract_single_activity_hits import main


if "--dataset" not in sys.argv:
    sys.argv.extend(["--dataset", "Healthy_Specific"])

main()
