#!/usr/bin/env python3
"""One-command GPU setup and verification for c_AMPs-prediction.

Run from the repository root with: python3 amp_pipeline/enable_gpu.py
It operates on ~/miniconda3/envs/py36 and camps-tf114, without requiring
`conda activate` in the calling shell.
"""
import argparse, os, shutil, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def run(cmd, env=None, check=True):
    print("\n$ " + " ".join(map(str, cmd)), flush=True)
    return subprocess.run([str(x) for x in cmd], env=env, check=check)

def find_root():
    for x in (os.environ.get("CONDA_ROOT"), str(Path.home()/"miniconda3"), str(Path.home()/"miniforge3"), str(Path.home()/"anaconda3")):
        if x and (Path(x)/"bin/conda").exists(): return Path(x)
    raise SystemExit("找不到 conda。请设置 CONDA_ROOT=/home/wsh/miniconda3 后重试。")

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--skip-tf", action="store_true", help="只安装/验证 BERT GPU")
    ap.add_argument("--skip-test", action="store_true", help="安装后不运行两条序列 smoke test")
    args=ap.parse_args()
    conda=find_root(); py36=conda/"envs/py36"; tf=conda/"envs/camps-tf114"
    for e in (py36, tf):
        if not (e/"bin/python").exists(): raise SystemExit(f"找不到环境: {e}")

    # BERT: replace the CPU wheel with the CUDA 11.1 wheel. RTX A4000 and the
    # current NVIDIA driver are backward compatible with this runtime.
    pip=py36/"bin/pip"; python=py36/"bin/python"
    run([pip,"uninstall","-y","torch","torchvision","torchaudio"], check=False)
    run([pip,"install","torch==1.10.0+cu111","-f","https://download.pytorch.org/whl/torch_stable.html"])
    run([python,"-c", "import torch; print('BERT torch:',torch.__version__,'CUDA:',torch.version.cuda,'available:',torch.cuda.is_available()); assert torch.cuda.is_available(); print('GPU:',torch.cuda.get_device_name(0))"])

    if not args.skip_tf:
        # TF 1.14 requires its historical CUDA runtime, independent of the
        # newer CUDA version reported by nvidia-smi.
        run([conda,"install","-y","-c","conda-forge","-n","camps-tf114","cudatoolkit=10.0","cudnn=7.6"], check=False)
        tfpip=tf/"bin/pip"; tfpy=tf/"bin/python"
        run([tfpip,"uninstall","-y","tensorflow","tensorflow-gpu"], check=False)
        run([tfpip,"install","tensorflow-gpu==1.14.0","protobuf==3.19.6"])
        tenv=os.environ.copy(); tenv["LD_LIBRARY_PATH"]=str(tf/"lib")+":"+tenv.get("LD_LIBRARY_PATH","")
        run([tfpy,"-c", "import tensorflow as tf; print('TF:',tf.__version__,'GPU:',tf.test.is_gpu_available(cuda_only=True),'device:',tf.test.gpu_device_name()); assert tf.test.is_gpu_available(cuda_only=True)"], env=tenv)

    if not args.skip_test:
        env=os.environ.copy(); env["BERT_USE_CUDA"]="1"; env["N"]="2"; env["ENV_TF"] = str(tf); env["ENV_BERT"] = str(py36)
        run(["bash",ROOT/"amp_pipeline/test_models_gpu.sh"], env=env)
    print("\nGPU 配置与验证完成。")

if __name__ == "__main__": main()
