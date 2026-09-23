#!/usr/bin/env python3
"""job_watch.py - run code/job.sh under a watchdog: progress file, remote progress pushes, stall/timeout kill.

Why: a long job must never hang the round silently. This wrapper
  * streams progress into results/jobs/progress.tsv (elapsed, log size, log mtime age, CPU% of the job tree)
  * pushes that progress (plus the log tail) to the arena branch every --push-every-min minutes,
    so the agent side can SEE the run advancing
  * kills the job when it is stalled (log unchanged for --stall-min AND CPU < --cpu-idle) or over --max-hours
Exit codes: job's own exit code; 90 = stalled and killed; 91 = exceeded max time and killed.
"""
import argparse, os, signal, subprocess, sys, time

def tree_cpu(root):
    """sum of utime+stime (seconds) over the process tree; 0 if gone"""
    try:
        pids = [root]
        seen, tot = set(), 0.0
        while pids:
            p = pids.pop()
            if p in seen: continue
            seen.add(p)
            try:
                with open(f"/proc/{p}/stat") as f:
                    parts = f.read().rsplit(")", 1)[1].split()
                tot += (int(parts[11]) + int(parts[12])) / os.sysconf("SC_CLK_TCK")
                with open(f"/proc/{p}/task/{p}/children") as f:
                    pids += [int(x) for x in f.read().split()]
            except Exception:
                pass
        return tot, len(seen)
    except Exception:
        return 0.0, 0

def git_push_progress(repo, prog, log, msg):
    try:
        subprocess.run(["git", "-C", repo, "add", "-f", prog, "-f", log], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        r = subprocess.run(["git", "-C", repo, "commit", "-qm", msg], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if r.returncode != 0: return False
        for _ in range(3):
            subprocess.run(["git", "-C", repo, "pull", "-q", "--rebase"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if subprocess.run(["git", "-C", repo, "push", "-q"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
                return True
            time.sleep(3)
    except Exception:
        pass
    return False

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cmd", default="bash code/job.sh")
    ap.add_argument("--repo", default=".")
    ap.add_argument("--log", required=True)
    ap.add_argument("--stall-min", type=int, default=25, help="kill if the log does not grow for this long AND cpu is idle")
    ap.add_argument("--cpu-idle", type=float, default=5.0, help="cpu%% of the job tree considered idle")
    ap.add_argument("--max-hours", type=float, default=6.0)
    ap.add_argument("--push-every-min", type=int, default=15)
    a = ap.parse_args()
    repo = os.path.abspath(a.repo)
    os.makedirs(os.path.dirname(a.log), exist_ok=True)
    prog = os.path.join(os.path.dirname(a.log), "progress.tsv")
    open(prog, "a").write(f"# started {time.strftime('%F %T')} cmd={a.cmd} stall_min={a.stall_min} max_h={a.max_hours}\n")
    with open(a.log, "wb") as lf:
        p = subprocess.Popen(a.cmd, shell=True, cwd=repo, stdout=lf, stderr=subprocess.STDOUT, start_new_session=True)
        t0 = time.time(); last_cpu, last_sz, still = tree_cpu(p.pid)[0], 0, 0; last_push = t0; killed = 0; idle_streak = 0
        print(f"[watch] pid={p.pid} log={a.log}", flush=True)
        while p.poll() is None:
            time.sleep(30)
            now = time.time(); el = now - t0
            sz = os.path.getsize(a.log); age = now - os.path.getmtime(a.log)
            cpu, nproc_ = tree_cpu(p.pid); dcpu = max(0.0, (cpu - last_cpu) / 30 * 100); last_cpu = cpu  # tree total can DROP when children exit -> clamp
            grew = sz > last_sz; last_sz = sz
            still = 0 if grew else still + 1
            line = (f"{time.strftime('%F %T')}\telapsed={el/60:.1f}min\tlog={sz}B\tlog_age={age/60:.1f}min\t"
                    f"cpu={dcpu:.0f}%\tprocs={nproc_}\tstalled_polls={still}\tlast: {os.popen(f'tail -n 1 {a.log}').read().strip()[:120]}")
            with open(prog, "a") as f: f.write(line + "\n")
            print("[watch] " + line, flush=True)
            if now - last_push > a.push_every_min * 60:
                ok = git_push_progress(repo, os.path.relpath(prog, repo), os.path.relpath(a.log, repo), f"progress: job running ({el/60:.0f} min)")
                print(f"[watch] progress push: {'ok' if ok else 'skipped'}", flush=True); last_push = now
            idle_streak = idle_streak + 1 if dcpu < a.cpu_idle else 0
            if age / 60 >= a.stall_min and idle_streak >= 3:
                print(f"[watch] STALLED: log unchanged {age/60:.0f} min with cpu {dcpu:.0f}% x{idle_streak} -> killing", flush=True)
                killed = 90; break
            if el / 3600 >= a.max_hours:
                print(f"[watch] TIMEOUT: {el/3600:.1f} h >= {a.max_hours} h -> killing", flush=True)
                killed = 91; break
        if killed:
            try: os.killpg(os.getpgid(p.pid), signal.SIGTERM); time.sleep(10); os.killpg(os.getpgid(p.pid), signal.SIGKILL)
            except Exception: pass
            p.wait()
        rc = killed or p.returncode
        with open(prog, "a") as f: f.write(f"# finished {time.strftime('%F %T')} rc={rc} elapsed={(time.time()-t0)/60:.1f}min\n")
        print(f"[watch] job rc={rc} elapsed={(time.time()-t0)/60:.1f} min")
        sys.exit(rc)

if __name__ == "__main__":
    main()
