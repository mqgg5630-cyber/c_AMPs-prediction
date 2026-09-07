# c_AMPs-prediction
Prediction of new c_AMPs, from the prediction of sORF to the getting c_AMPs. [Scripts](https://github.com/mayuefine/c_AMPs-prediction/blob/master/c_AMPs-Prediction.md "c_AMPs-Prediction.md").<br>
Trained predictive model.[Models](https://github.com/mayuefine/c_AMPs-prediction/tree/master/Models).<br>
Test set data under 50AA in length, and also the benchmark dataset.[Dataset](https://github.com/mayuefine/c_AMPs-prediction/tree/master/Data).<br>
<br>
Verified AMPs have been deposited and published in [ADP database](https://aps.unmc.edu/).<br>
For sequences that have been predicted but not yet verified, please contact **Jun Wang**(junwang\@im.ac.cn) and request a **Material Transfer Agreement (MTA)** to ensure proper usage.<br>

## 快速安装 & 三模型跑通自检 (推荐入口)

在新机器 (含 WSL + 单卡 GPU) 上，两条命令搞定：

```bash
bash amp_pipeline/install_envs.sh        # mamba 一键建 camps-tf114 (TF1.14/Keras2.2.4) + camps-bert (torch/bert_sklearn)
bash amp_pipeline/smoke_test_3models.sh  # Attention / LSTM / BERT 逐个 PASS/FAIL + 端到端小样本
```

详细说明、GPU 适配 (TF1.14 在 Ampere 上要走 CPU、BERT 走 CUDA)、bert.bin 获取方式与踩坑速查表见
**[INSTALL.md](INSTALL.md)**；宏基因组分组批量流程见 **[amp_pipeline/README.md](amp_pipeline/README.md)**。

## Installation bert_sklearn
Download and copy [bert_sklearn](https://github.com/mayuefine/c_AMPs-prediction/tree/master/bert_sklearn) to your python3 site-packages folder.<br>
```bash
cd bert-sklearn
pip install .
```
**Please cite**: [Identification of antimicrobial peptides from the human gut microbiome using deep learning](https://www.nature.com/articles/s41587-022-01226-0)
