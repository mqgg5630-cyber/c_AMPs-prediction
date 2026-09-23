# 组特异性 AMP 集合分析 — 自动汇总  (2026-09-23 15:26:54, LAPTOP-R77M5D6M)

## Cohort2_Matched265_NCvsAD

```
set             n        pct_of_group                  pct_of_union
AD_total        2010251  100.00                        54.33
NC_total        1888741  100.00                        51.05
shared          199135   9.91 (of AD) / 10.54 (of NC)  5.38
AD_specific     1811116  90.09                         48.95
NC_specific     1689606  89.46                         45.67
Jaccard(AD,NC)  0.0538                                 
```

特征对比 (features.tsv):
```
metric                                        AD_specific  NC_specific  shared
n_peptides                                    1811116      1689606      199135
n_sampled_for_features                        300000       300000       199135
length_mean                                   15.42        15.46        10.55
length_median                                 13           13           7
net_charge_mean                               3.28         3.22         2.43
cationic_frac(charge>=2)                      0.755        0.751        0.653
hydrophobic_frac_mean                         0.340        0.343        0.351
eisenberg_H_mean                              -0.228       -0.216       -0.256
aa_A_pct                                      5.62         5.44         4.67
aa_C_pct                                      8.25         8.04         7.47
aa_D_pct                                      1.10         1.14         0.86
aa_E_pct                                      1.43         1.48         1.25
aa_F_pct                                      3.67         3.77         3.74
aa_G_pct                                      6.29         6.41         5.76
aa_H_pct                                      2.81         2.86         2.85
aa_I_pct                                      5.23         5.37         5.82
aa_K_pct                                      7.93         8.27         8.93
aa_L_pct                                      7.76         7.76         9.36
aa_M_pct                                      0.59         0.63         0.53
aa_N_pct                                      2.78         2.82         2.44
aa_P_pct                                      6.93         6.92         7.28
aa_Q_pct                                      3.34         3.37         3.34
aa_R_pct                                      15.61        14.90        15.90
aa_S_pct                                      7.94         7.86         7.47
aa_T_pct                                      3.37         3.36         2.92
aa_V_pct                                      3.43         3.45         3.38
aa_W_pct                                      3.51         3.70         3.76
aa_Y_pct                                      2.43         2.44         2.24
cliffs_delta_length_vs_AD_specific            ref          -0.002       0.424
cliffs_delta_charge_vs_AD_specific            ref          0.007        0.214
cliffs_delta_hydrophobic_frac_vs_AD_specific  ref          -0.013       -0.028
cliffs_delta_eisenberg_H_vs_AD_specific       ref          -0.011       0.033
```

## Cohort4_Full476_NCvsAD

```
set             n        pct_of_group                  pct_of_union
AD_total        4276575  100.00                        70.30
NC_total        2197149  100.00                        36.12
shared          390206   9.12 (of AD) / 17.76 (of NC)  6.41
AD_specific     3886369  90.88                         63.88
NC_specific     1806943  82.24                         29.70
Jaccard(AD,NC)  0.0641                                 
```

特征对比 (features.tsv):
```
metric                                        AD_specific  NC_specific  shared
n_peptides                                    3886369      1806943      390206
n_sampled_for_features                        300000       300000       300000
length_mean                                   15.74        15.75        11.52
length_median                                 13           13           9
net_charge_mean                               3.34         3.24         2.59
cationic_frac(charge>=2)                      0.760        0.754        0.671
hydrophobic_frac_mean                         0.339        0.342        0.346
eisenberg_H_mean                              -0.228       -0.212       -0.250
aa_A_pct                                      5.70         5.37         5.17
aa_C_pct                                      8.17         8.05         7.83
aa_D_pct                                      1.11         1.17         0.91
aa_E_pct                                      1.45         1.51         1.29
aa_F_pct                                      3.62         3.77         3.65
aa_G_pct                                      6.42         6.52         5.87
aa_H_pct                                      2.77         2.91         2.85
aa_I_pct                                      5.13         5.34         5.49
aa_K_pct                                      7.77         8.22         8.31
aa_L_pct                                      7.60         7.77         8.72
aa_M_pct                                      0.60         0.64         0.55
aa_N_pct                                      2.70         2.81         2.42
aa_P_pct                                      7.19         6.91         7.40
aa_Q_pct                                      3.28         3.41         3.32
aa_R_pct                                      15.71        14.78        16.05
aa_S_pct                                      7.98         7.86         7.68
aa_T_pct                                      3.39         3.35         3.09
aa_V_pct                                      3.41         3.43         3.37
aa_W_pct                                      3.61         3.68         3.84
aa_Y_pct                                      2.38         2.49         2.20
cliffs_delta_length_vs_AD_specific            ref          0.002        0.351
cliffs_delta_charge_vs_AD_specific            ref          0.011        0.176
cliffs_delta_hydrophobic_frac_vs_AD_specific  ref          -0.023       -0.024
cliffs_delta_eisenberg_H_vs_AD_specific       ref          -0.021       0.030
```

## Cohort1_Matched265_5Stage

```
stage  n_total  n_stage_specific  specific_pct  n_in_core5
NC     1888741  1378566           72.99         36851
SCS    1798519  1357002           75.45         36851
SCD    1927898  1419270           73.62         36851
MCI    1483763  1033801           69.67         36851
AD     2010251  1529329           76.08         36851
```

成员模式 Top 12:
```
pattern_NC_SCS_SCD_MCI_AD  n        stages
00001                      1529329  AD
00100                      1419270  SCD
10000                      1378566  NC
01000                      1357002  SCS
00010                      1033801  MCI
10100                      93439    NC+SCD
00101                      81585    SCD+AD
11000                      78795    NC+SCS
00011                      73581    MCI+AD
10010                      73354    NC+MCI
00110                      73284    SCD+MCI
01001                      67172    SCS+AD
```

特征对比:
```
metric                                        NC_specific  AD_specific  core5   late_only_MCI_AD  early_only_NC_SCS
n_peptides                                    1378566      1529329      36851   73581             78795
n_sampled_for_features                        300000       300000       36851   73581             78795
length_mean                                   16.03        15.96        7.39    13.88             13.18
length_median                                 13           13           5       11                11
net_charge_mean                               3.32         3.38         2.15    2.98              2.82
cationic_frac(charge>=2)                      0.763        0.764        0.637   0.726             0.707
hydrophobic_frac_mean                         0.342        0.339        0.352   0.343             0.346
eisenberg_H_mean                              -0.213       -0.226       -0.360  -0.229            -0.231
aa_A_pct                                      5.52         5.68         4.63    5.81              4.97
aa_C_pct                                      8.10         8.31         6.90    8.03              8.01
aa_D_pct                                      1.15         1.11         0.48    0.99              1.06
aa_E_pct                                      1.48         1.44         0.81    1.36              1.55
aa_F_pct                                      3.77         3.65         3.68    3.56              3.83
aa_G_pct                                      6.49         6.35         4.64    6.34              5.70
aa_H_pct                                      2.88         2.81         2.72    2.69              2.93
aa_I_pct                                      5.35         5.21         5.74    5.24              5.62
aa_K_pct                                      8.20         7.84         9.65    7.94              8.29
aa_L_pct                                      7.68         7.60         11.37   7.87              8.48
aa_M_pct                                      0.63         0.60         0.30    0.59              0.60
aa_N_pct                                      2.84         2.80         1.63    2.54              2.71
aa_P_pct                                      6.89         6.92         7.16    7.51              6.59
aa_Q_pct                                      3.34         3.33         3.19    3.17              3.41
aa_R_pct                                      14.84        15.58        20.51   15.60             15.44
aa_S_pct                                      7.86         7.97         6.84    7.87              7.92
aa_T_pct                                      3.41         3.43         2.08    3.24              3.28
aa_V_pct                                      3.44         3.43         2.74    3.46              3.62
aa_W_pct                                      3.67         3.49         3.25    3.80              3.63
aa_Y_pct                                      2.46         2.45         1.67    2.39              2.36
cliffs_delta_length_vs_NC_specific            ref          0.012        0.762   0.171             0.210
cliffs_delta_charge_vs_NC_specific            ref          -0.012       0.313   0.076             0.107
cliffs_delta_hydrophobic_frac_vs_NC_specific  ref          0.012        -0.026  -0.004            -0.014
cliffs_delta_eisenberg_H_vs_NC_specific       ref          0.022        0.162   0.021             0.025
```

## Cohort3_Full476_5Stage

```
stage  n_total  n_stage_specific  specific_pct  n_in_core5
NC     2197149  1437291           65.42         81349
SCS    2668215  1803443           67.59         81349
SCD    3015354  2044126           67.79         81349
MCI    3422342  2295957           67.09         81349
AD     4276575  3092822           72.32         81349
```

成员模式 Top 12:
```
pattern_NC_SCS_SCD_MCI_AD  n        stages
00001                      3092822  AD
00010                      2295957  MCI
00100                      2044126  SCD
01000                      1803443  SCS
10000                      1437291  NC
00011                      257518   MCI+AD
00101                      174495   SCD+AD
00110                      161935   SCD+MCI
01001                      160689   SCS+AD
10001                      120517   NC+AD
01010                      118876   SCS+MCI
10010                      113340   NC+MCI
```

特征对比:
```
metric                                        NC_specific  AD_specific  core5   late_only_MCI_AD  early_only_NC_SCS
n_peptides                                    1437291      3092822      81349   257518            71298
n_sampled_for_features                        300000       300000       81349   257518            71298
length_mean                                   16.32        16.35        8.08    14.41             13.70
length_median                                 13           13           5       12                11
net_charge_mean                               3.34         3.44         2.18    3.12              2.97
cationic_frac(charge>=2)                      0.764        0.771        0.623   0.739             0.725
hydrophobic_frac_mean                         0.342        0.337        0.351   0.339             0.346
eisenberg_H_mean                              -0.210       -0.226       -0.321  -0.236            -0.231
aa_A_pct                                      5.44         5.74         4.82    5.78              4.91
aa_C_pct                                      8.07         8.21         7.28    8.16              7.86
aa_D_pct                                      1.20         1.12         0.57    1.00              1.09
aa_E_pct                                      1.52         1.46         0.94    1.38              1.57
aa_F_pct                                      3.77         3.64         3.69    3.48              3.85
aa_G_pct                                      6.59         6.52         4.83    6.28              5.70
aa_H_pct                                      2.88         2.78         2.72    2.67              2.83
aa_I_pct                                      5.32         5.08         5.75    5.23              5.69
aa_K_pct                                      8.19         7.70         9.56    7.76              8.65
aa_L_pct                                      7.65         7.45         10.49   7.53              8.43
aa_M_pct                                      0.65         0.60         0.39    0.59              0.61
aa_N_pct                                      2.85         2.74         1.93    2.58              2.74
aa_P_pct                                      6.88         7.17         7.16    7.49              6.56
aa_Q_pct                                      3.40         3.29         3.25    3.09              3.38
aa_R_pct                                      14.70        15.64        18.63   16.00             15.39
aa_S_pct                                      7.89         8.02         7.07    8.06              8.00
aa_T_pct                                      3.41         3.43         2.47    3.36              3.27
aa_V_pct                                      3.44         3.42         2.99    3.31              3.48
aa_W_pct                                      3.65         3.57         3.63    3.88              3.63
aa_Y_pct                                      2.49         2.40         1.84    2.35              2.35
cliffs_delta_length_vs_NC_specific            ref          -0.003       0.711   0.152             0.197
cliffs_delta_charge_vs_NC_specific            ref          -0.018       0.314   0.056             0.087
cliffs_delta_hydrophobic_frac_vs_NC_specific  ref          0.019        -0.021  0.012             -0.014
cliffs_delta_eisenberg_H_vs_NC_specific       ref          0.024        0.127   0.037             0.028
```

