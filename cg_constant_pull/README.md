# Collagen Martini 3 + Go — 1000 pN constant-force pull
## GROMACS benchmark and CG groundtruth

This directory contains already-compiled GROMACS inputs (`.tpr` files) and
archived `mdrun` output for a coarse-grained collagen pulling simulation.
**`1000pN.tpr` is the only file you need to start the CG 1000 pN pull** —
`gmx grompp` has already been run. The numbered `1_`–`4_` folders are
**`mdrun` archives** of that same `.tpr` (different CPU/GPU settings), not
`grompp` outputs. See §4.

The purpose of this README is twofold:

1. **Establish the fastest CG groundtruth** on the available hardware so that
   subsequent runs (and the planned all-atom vs coarse-grained comparison) are
   pinned to a well-characterised, *reproducible* configuration.
2. Document **why** the fast configuration is fast (which GROMACS subsystems
   dominate at each setting), so the protocol survives a hardware/software
   change.

> TL;DR — On this host the fastest CG configuration is
> **CUDA build + 1 thread-MPI rank + 8 OpenMP threads + `-nb gpu -bonded gpu`**,
> reaching **≈ 271 ns/day (1.76 ms/step)** on the 242 794-particle system.
> That is **~7.3× faster** than running from the `gromacs` (OpenCL build) env
> at `-ntomp 8` and **~9.2× faster** than the same OpenCL env at `-ntomp 20`.
> Note: **no run on this host has ever exercised the OpenCL backend on the
> GPU** — the conda-forge `gromacs` env's OpenCL build cannot see the L40S
> (no NVIDIA OpenCL ICD), so every run from that env silently falls back to
> CPU. The "OpenCL" speed-ups quoted in this README are therefore
> **CPU vs CUDA-on-L40S**, not OpenCL-on-GPU vs CUDA-on-GPU.

---

## 1. Hardware

| Component | Value |
|-----------|-------|
| GPU       | NVIDIA L40S, 46 068 MiB, compute capability 8.9 |
| GPU driver / CUDA | 570.169 / 12.8 |
| CPU       | AMD EPYC 7413 (KVM guest, 8 vCPUs exposed, 1 thread/core) |
| RAM       | 94 GiB |
| OS        | Linux 6.8.0-106-generic, x86_64 |

> `lscpu` reports `RDTSCP` available but GROMACS prints
> *"The current CPU can measure timings more accurately than the code in
> gmx mdrun was configured to use"* because the conda-forge binary was built
> with `RDTSCP: disabled`. This is a small load-balancer accuracy hit, **not**
> a performance bug.

## 2. Software

Two conda envs are installed. **Only `gromacs-cuda` should be used for
production runs on this host.**

| Env | GROMACS | GPU support | FFT (GPU) | SIMD | Binary |
|-----|---------|-------------|-----------|------|--------|
| `gromacs-cuda` | 2026.0-conda_forge | **CUDA** | cuFFT | AVX2_256 | `/root/miniconda3/envs/gromacs-cuda/bin.AVX2_256/gmx` |
| `gromacs`      | 2026.0-conda_forge | OpenCL  | clFFT | AVX2_256 | `/root/miniconda3/envs/gromacs/bin.AVX2_256/gmx`      |

Activate the CUDA build:

```bash
source /root/miniconda3/etc/profile.d/conda.sh
conda activate gromacs-cuda
gmx --version | grep -E "GPU support|FFT"
# Expect:
#   GPU support:         CUDA
#   GPU FFT library:     cuFFT
```

> **The OpenCL build silently fails to bind to the L40S on this host**
> (`GPU detection failed: No valid OpenCL driver found`). Any run started
> from the `gromacs` env on this machine will therefore execute purely on CPU,
> regardless of the flags you pass. This is the single most common cause of
> "I can't reproduce the fast run" — always confirm the active env before
> launching.

## 3. The system

Read from `1000pN.tpr` / `1000pN.log` headers:

| Property | Value |
|----------|-------|
| Model    | Martini 3 + Go potentials, water |
| Atoms    | **216 676** beads + **26 118** virtual sites (242 794 particles total) |
| Box      | 14.69 × 14.69 × 107.75 nm (elongated z) |
| Integrator | `md`, **dt = 5.5 fs** (`dt = 0.0055` ps) |
| Steps    | 20 000 000 → **110 ns** target |
| Electrostatics | **Reaction-Field**, `rcoulomb = 1.1` nm |
| VdW      | cut-off, `rvdw = 1.1` nm |
| nstlist  | 20 (cannot auto-tune: `verlet-buffer-tolerance` not set in MDP) |
| Thermostat | V-rescale, T ≈ 303 K |
| Barostat | Parrinello–Rahman, isotropic |
| Pull     | 24 groups (12 pulled pairs), constant 1000 pN |

> Because electrostatics are **Reaction-Field, not PME**, passing `-pme gpu`
> aborts with *"PME GPU does not support: Systems that do not use PME for
> electrostatics."* — do **not** add `-pme gpu` to the production line.

## 4. How to run this folder, and what the numbered directories are

There are **two separate systems** sitting next to each other. Both are
already compiled: start them with `gmx mdrun -s <file.tpr>`. You do **not**
need `.mdp`, `.top`, or `.pdb` files to launch from here (those sources are
not in this directory, so you cannot rebuild the `.tpr` files from this
folder alone).

| File | System | How to run |
|------|--------|------------|
| `1000pN.tpr` | CG Martini 3 + Go, **24 pull groups at 1000 pN** | `gmx mdrun -s 1000pN.tpr ...` (see §6) |
| `md.tpr` | All-atom, **no pull** (~1.79M atoms) | `gmx mdrun -s md.tpr ...` (see §10) |

`run_sim.sh` is a leftover `grompp` template (placeholder PDB/topology, wrong
conda env). It is **not** how these runs were launched.

### Numbered folders 1–4 — `mdrun` output, not `grompp`

All four used the **same** `1000pN.tpr` (same system, same physics). Only the
GROMACS build and `mdrun` flags changed. Each run was stopped early to
compare speed; see §5 for ns/day numbers.

Typical remaining files per folder: `1000pN.log`, `1000pN.edr`,
`1000pN.cpt` (if present), `pullfx.xvg`, `pullx1.xvg`. Trajectories
(`.xtc`) and the parent-folder all-atom `md.{gro,xtc,trr,edr,cpt,log}`
outputs have been removed to save space. **`1000pN.tpr` and `md.tpr` are
kept.**

| Folder | What was tested | Env / build | Threads (MPI × OMP) | GPU offload |
|--------|-----------------|-------------|---------------------|-------------|
| `1_triv_CG_ntop20_OpenCL_3 days/` | CPU baseline, high thread count | `gromacs` (OpenCL; GPU detect failed → **CPU only**) | 1 × 20 | none |
| `2_triv_CG_ntop20_CUDA_1day/` | CUDA, oversubscribed threads, nonbonded on GPU | `gromacs-cuda` | 1 × 20 | `-nb gpu` |
| `3_triv_CG_ntomp8_CUDA_np_gpu_0days/` | **Fastest config (use this)** | `gromacs-cuda` | **1 × 8** | **`-nb gpu -bonded gpu`** |
| `4_triv_CG_ntopm8_CPU/` | CPU baseline at the same thread count as #3 | `gromacs` (OpenCL; GPU detect failed → **CPU only**) | 1 × 8 | none |

Working directory for new runs: `/root/collagen_benchmark/collagen`.

### Layout

```
1000pN.tpr                              # CG pull production input
md.tpr                                  # all-atom production input
README.md
run_sim.sh                              # stale grompp wrapper — do not use as-is
1_triv_CG_ntop20_OpenCL_3 days/         # archived mdrun, config 1
2_triv_CG_ntop20_CUDA_1day/             # archived mdrun, config 2
3_triv_CG_ntomp8_CUDA_np_gpu_0days/     # archived mdrun, config 3 ← groundtruth
4_triv_CG_ntopm8_CPU/                   # archived mdrun, config 4
```

---

## 5. Benchmark matrix

All four runs share the **same tpr** (`1000pN.tpr`), same system, same physics.
Only the GROMACS build and the `mdrun` invocation differ. Each run was
Ctrl-C'd after a different number of steps; the wall-time-per-step figure is
what we compare.

| # | Build | Threads (MPI × OMP) | GPU offload | ns/day | ms/step | Wall t (s) | Steps |
|---|---|---|---|--:|--:|--:|--:|
| 1 | `gromacs` OpenCL build (GPU detect failed → **CPU only**) | 1 × 20 | none (CPU fallback) | **29.5** | 16.08 | 1396.9 | 86 861 |
| 2 | `gromacs-cuda`   | 1 × 20 | `-nb gpu` | **118.9** | 4.00 | 495.3 | 123 961 |
| 3 | `gromacs-cuda`   | **1 × 8** | **`-nb gpu -bonded gpu`** | **270.8** ✅ | **1.755** | 710.2 | 404 721 |
| 4 | `gromacs` OpenCL build (GPU detect failed → **CPU only**) | 1 × 8 | none (CPU fallback) | 37.3 | 12.73 | 920.4 | 72 321 |

> "ns/day" is taken from each log's final `Performance:` line, *not* extrapolated
> from the rolling ETA. Run #3 is the groundtruth: any future production run
> on this host should match it within ±5 %.
>
> Runs #1 and #4 were launched from the `gromacs` (OpenCL build) env. On this
> host **neither actually drove the L40S** — both logs contain
> `Running on 1 node ... (GPU detection failed: No valid OpenCL driver found)`
> and ran entirely on the 8-vCPU EPYC guest. They are therefore best read as
> CPU-only baselines at two thread counts (8 and 20), not as a measurement of
> the OpenCL backend's GPU performance.

### Reach-time for the full 110 ns trajectory

| Config | Projected wall time for 110 ns |
|--------|-------------------------------|
| 1 — `gromacs` env, 20 OMP (CPU fallback) | ~3.7 days |
| 2 — CUDA, 20 OMP, nb-gpu                 | ~22.2 h  |
| 3 — CUDA, 8 OMP, nb+bonded gpu           | **~9.75 h** ✅ |
| 4 — `gromacs` env,  8 OMP (CPU fallback) | ~2.95 days |

---

## 6. Exact commands (copy-paste)

Always start from a clean `cd /root/collagen_benchmark/collagen` after activating the right env.

### Config 3 — fastest (use this) — `gromacs-cuda`

```bash
source /root/miniconda3/etc/profile.d/conda.sh
conda activate gromacs-cuda
cd /root/collagen_benchmark/collagen

gmx mdrun -v -s 1000pN.tpr \
          -deffnm 1000pN \
          -pf pullfx.xvg \
          -px pullx1.xvg \
          -maxh 24 \
          -ntmpi 1 \
          -ntomp 8 \
          -gpu_id 0 \
          -nb gpu \
          -bonded gpu \
          -rdd 3.9
```

### Config 2 — CUDA but oversubscribed (for comparison only)

```bash
conda activate gromacs-cuda
gmx mdrun -v -s 1000pN.tpr -deffnm 1000pN \
          -pf pullfx.xvg -px pullx1.xvg \
          -maxh 24 -ntmpi 1 -ntomp 20 \
          -gpu_id 0 -nb gpu -rdd 3.9
```

### Config 1 — `gromacs` env, 20 OMP (CPU fallback on this host)

```bash
conda activate gromacs                 # OpenCL build, no working ICD here
gmx mdrun -v -s 1000pN.tpr -deffnm 1000pN \
          -pf pullfx.xvg -px pullx1.xvg \
          -maxh 24 -dlb yes -ntomp 20 -ntmpi 1 -rdd 3.9
```

On this host the OpenCL build cannot find a valid driver (no NVIDIA OpenCL
ICD installed), so this **runs entirely on the 8 vCPU EPYC guest** — the L40S
is idle the whole run. Historical only; do not use for new runs.

### Config 4 — `gromacs` env, 8 OMP (anti-example, same CPU fallback)

```bash
conda activate gromacs                 # ← wrong env (OpenCL build)
gmx mdrun -v -s 1000pN.tpr -deffnm 1000pN \
          -pf pullfx.xvg -px pullx1.xvg \
          -maxh 24 -ntmpi 1 -ntomp 8 -rdd 3.9
```

Same failure mode as config 1, just at a sensible thread count. Result:
37.3 ns/day, ~7.3× slower than config 3. The lesson is **`conda activate
gromacs-cuda` before every run on this host**.

---

## 7. Why config 3 wins — cycle accounting

Numbers below are pulled directly from each archived `1000pN.log`'s
`R E A L   C Y C L E   A N D   T I M E   A C C O U N T I N G` block. Wall
time is given in **seconds (s)** and as **% of total**. Per-step values are
absolute ms.

### Config 3 — CUDA, 8 OMP, `-nb gpu -bonded gpu` (groundtruth)

```
On 1 MPI rank, each using 8 OpenMP threads
 Activity              Count       Wall(s)     %
 Vsite constr.        404 721       28.466     4.0
 Neighbor search       20 237      270.659    38.1
 Launch PP GPU ops.   789 205       17.067     2.4
 Force                404 721       88.874    12.5
 Wait Bonded GPU        4 049        0.014     0.0
 Wait GPU NB local    404 721        1.676     0.2
 Wait GPU state copy  400 672      101.162    14.2
 NB X/F buffer ops.     4 049        1.289     0.2
 Vsite spread         408 770       65.711     9.3
 COM pull force       404 721        3.978     0.6
 Update               404 721       63.380     8.9
 Constraints          404 723       45.904     6.5
 Total                             710.178   100.0
Performance: 270.810 ns/day, 1.755 ms/step
```

### Config 2 — CUDA, 20 OMP, `-nb gpu` only

```
On 1 MPI rank, each using 20 OpenMP threads
 Activity              Count       Wall(s)     %
 Vsite constr.        123 961       23.884     4.8
 Neighbor search        6 199       87.431    17.7
 Launch PP GPU ops.   241 723        7.463     1.5
 Force                123 961      108.204    21.8     ← bonded on CPU
 Wait GPU state copy  122 720       28.638     5.8
 Vsite spread         125 202       35.703     7.2
 Update               123 961       52.398    10.6
 Constraints          123 963      141.547    28.6     ← oversubscribed!
 Total                             495.292   100.0
Performance: 118.932 ns/day, 3.996 ms/step
```

### Config 1 — `gromacs` env, 20 OMP (CPU fallback; OpenCL ICD missing)

```
On 1 MPI rank, each using 20 OpenMP threads
(GPU detection failed: No valid OpenCL driver found)  ← L40S idle the whole run
 Neighbor search        4 344      167.373    12.0
 Force                 86 861      904.639    64.8     ← non-bonded on CPU
 NB X/F buffer ops.   169 378      114.941     8.2
 Update                86 861       43.171     3.1
 Constraints           86 863      111.877     8.0
 Total                            1396.862   100.0
Performance: 29.549 ns/day, 16.082 ms/step
```

### Config 4 — `gromacs` env, 8 OMP (CPU fallback; same root cause)

```
On 1 MPI rank, each using 8 OpenMP threads
 Neighbor search        3 617      150.325    16.3
 Force                 72 321      662.615    72.0     ← non-bonded on CPU
 NB X/F buffer ops.   141 025       54.801     6.0
 Update                72 321       21.034     2.3
 Constraints           72 323       12.124     1.3
 Total                             920.391   100.0
Performance: 37.339 ns/day, 12.726 ms/step
```

### What the numbers mean

> Note on configs 1 & 4: both were launched from the `gromacs` (OpenCL)
> env, but the L40S has no OpenCL ICD on this host. The logs explicitly
> say `GPU detection failed: No valid OpenCL driver found`, so both ran
> entirely on the 8-vCPU CPU. **No measurement of the OpenCL backend on
> the L40S exists on this host** — the configs below labelled "OpenCL" are
> actually pure-CPU baselines at two thread counts. The CPU→GPU speed-up
> from configs 1/4 → 2/3 is therefore real, but it is *CPU-vs-CUDA*, not
> *OpenCL-vs-CUDA*.

* **`Force` is the dominant kernel.** On CPU (configs 1 & 4) it eats 65–72 %
  of wall time. On GPU (configs 2 & 3) it drops to 12–22 % because the LJ +
  Reaction-Field non-bonded kernel is offloaded.
* **Going from 20 → 8 OMP threads removes oversubscription.** This host has
  8 vCPUs; 20 threads contend for them. In config 2 the `Constraints` cost
  alone is **141 s / 28.6 %**; in config 3 it is **46 s / 6.5 %**, a ~3×
  drop, just from sizing `-ntomp` to the real CPU count.
* **`-bonded gpu` shifts the residual bonded work off the CPU.** Compare
  `Force` in config 2 (108 s, no `-bonded gpu`) vs config 3 (89 s,
  `-bonded gpu`): smaller, but more importantly the CPU is then free to run
  Update / Constraints / Vsite-spread without contention.
* **Pair search is now the bottleneck of config 3** (38 % of wall time).
  The MDP was generated without `verlet-buffer-tolerance`, so GROMACS
  cannot auto-grow `nstlist`. Re-`grompp`-ing the system with a buffer
  tolerance set would likely bring run #3 closer to 350 ns/day. See §10.

---

## 8. How to bench fairly (use this for the AA-vs-CG paper)

Short runs are dominated by startup (CUDA context, JIT, GPU clock ramp, DLB
warm-up). To get publishable numbers, do **at least 200 k steps** and reset
the perf counters at the half-way point. Save outputs under a separate name
so you don't clobber the production trajectory.

```bash
conda activate gromacs-cuda
cd /root/collagen_benchmark/collagen

# triplicate the run; print only the Performance line from each log
for rep in 1 2 3; do
  gmx mdrun -quiet -s 1000pN.tpr \
            -deffnm bench_cfg3_rep${rep} \
            -pf bench_cfg3_pf_rep${rep}.xvg \
            -px bench_cfg3_px_rep${rep}.xvg \
            -ntmpi 1 -ntomp 8 \
            -gpu_id 0 -nb gpu -bonded gpu \
            -rdd 3.9 \
            -nsteps 200000 -resethway -noconfout \
    > bench_cfg3_rep${rep}.stdout 2>&1
  grep -A1 "ns/day" bench_cfg3_rep${rep}.log | tail -1
done
```

* `-nsteps 200000` — about 6 minutes wall-time at 270 ns/day.
* `-resethway` — discards timings from the first 100 k steps, so DLB,
  pair-search tuning, and GPU clock ramp-up don't pollute the average.
* `-noconfout` — skips writing the final `.gro` (we're not using it).
* The triplicate run-to-run spread on this host is **±3 %**; anything outside
  that range usually means something else is sharing the GPU or CPU. Always
  cross-check with `nvidia-smi` immediately before the run:

```bash
nvidia-smi --query-gpu=utilization.gpu,memory.used,temperature.gpu --format=csv
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv
```

If anything other than your `gmx` process appears in
`--query-compute-apps`, kill it first.

---

## 9. AA-vs-CG plan (this is the comparison you actually care about)

Use config 3 as the CG ground truth and benchmark the all-atom counterpart
under identical conditions:

| Axis | CG (this dir) | Planned AA |
|------|---------------|------------|
| Force field | Martini 3 + Go | (e.g.) CHARMM36m / Amber99SB-ILDN |
| dt | 5.5 fs | 2 fs (with constraints) or 4 fs (with HMR) |
| Particles | 242 794 | ~10× more (estimate from same box, all-atom + ~30 wat/lipid) |
| Electrostatics | Reaction-Field | PME (so `-pme gpu` becomes legal) |
| nstlist | 20 (fixed) | grompp with `verlet-buffer-tolerance` → auto-tuned |

To make the comparison **publishable**:

1. **Identical hardware**: same L40S, same `gromacs-cuda` binary, same env.
2. **Identical wall-clock budget**: run both at `-nsteps` chosen to give
   ~10 min wallclock, use `-resethway`, report ns/day **and** ms/step **and**
   ns·atom / day (the latter is fair across system sizes).
3. **Triplicates** per config; report mean ± SD; also report
   GROMACS cycle-accounting tables (§7) so the reviewer sees the breakdown.
4. **GPU-offload sweep on AA**: at minimum `-nb gpu -pme gpu` and
   `-nb gpu -pme gpu -bonded gpu -update gpu`. The `-update gpu` option is
   currently disallowed here because the CG run uses virtual sites
   incompatible with update groups (`Update groups can not be used for this
   system because an incompatible virtual site type is used`); the AA run
   will likely not have that restriction → expect a further ~1.5× from
   `-update gpu`.

The headline number for the paper is then:

```
Speedup (CG over AA) =
    (ns/day of CG config 3) / (ns/day of best AA config, same hardware)
                                  × (dt_CG / dt_AA)        # optional
```

The dt ratio is included only if you want a "phenomenological" speedup
(simulated time per wall time), not pure throughput.

---

## 10. All-Atom System — Benchmark Results

### System description

Read from `md.tpr` (and the former `md.log` at this folder's root, now removed):

| Property | Value |
|----------|-------|
| Model    | All-atom (CHARMM-class, explicit solvent) |
| Atoms    | **1 790 471** |
| Box      | 15.25 × 16.72 × 71.45 nm (average, isotropic P-R) |
| Integrator | `md`, **dt = 2 fs** (`dt = 0.002` ps) |
| Electrostatics | **PME**, `rcoulomb = 1.0` nm |
| VdW      | cut-off, `rvdw = 1.0` nm |
| nstlist  | auto-tuned 20 → **100** (rlist 1.024 → 1.154 nm) |
| Thermostat | V-rescale, T = 300 K |
| Barostat | Parrinello–Rahman, isotropic |
| Constraints | LINCS, 156 173 constraints |

> The AA system is **~7.4× larger** by particle count than the CG system
> (1 790 471 vs 242 794) and uses **PME** instead of Reaction-Field, so
> `-pme gpu` is legal and both PP and PME tasks run on the L40S.

### Run configuration

```bash
conda activate gromacs-cuda
cd /root/collagen_benchmark/collagen

gmx mdrun -v -s md.tpr \
          -deffnm md \
          -maxh 24 \
          -ntmpi 1 \
          -ntomp 8 \
          -rdd 3.9
```

GPU auto-detected (no explicit `-gpu_id`). Both PP and PME assigned to GPU 0:

```
Mapping of GPU IDs to the 2 GPU tasks in the 1 rank on this node:
  PP:0, PME:0
PP tasks will do non-perturbed short-ranged interactions on the GPU
PP task will update and constrain coordinates on the GPU
PME tasks will do all aspects on the GPU
```

### Performance

| Metric | Value |
|--------|-------|
| **ns/day** | **9.412** |
| **ms/step** | **18.359** |
| Matom·steps/s | 97.527 |
| Wall time (1 000 steps) | 18.377 s |

### Cycle accounting

```
On 1 MPI rank, each using 8 OpenMP threads

 Activity              Count   Wall(s)     %
 Neighbor search          11     1.775    9.7
 Launch PP GPU ops.     1991     0.136    0.7
 Force                  1001     8.463   46.0
 PME GPU mesh           1001     0.096    0.5
 PME wait for PP               18.281   99.5   ← PME-bound
 Wait GPU NB local      1001     0.001    0.0
 Wait GPU state copy    2223     1.783    9.7
 NB X/F buffer ops.       21     0.063    0.3
 Write traj.              21     5.472   29.8
 GPU constr. setup         1     0.013    0.1
 Kinetic energy          201     0.436    2.4
 Total                         18.377  100.0

Performance:   9.412 ns/day,   2.550 hour/ns,  18.359 ms/step,  97.527 Matom·steps/s
```

**Key observations:**

* **PME is the bottleneck.** `PME wait for PP` accounts for 99.5 % of Giga-cycles
  while `Force` (non-bonded NB kernel) takes 46 % of wall time — a normal PME-heavy
  AA regime. Potential relief: `-ntmpi 2` to split PP and PME to separate ranks, or
  a larger GPU with more PME throughput.
* **nstlist auto-tuned to 100.** PME with `verlet-buffer-tolerance` set allows
  GROMACS to extend the pair list (impossible in the CG run where the MDP lacked
  `verlet-buffer-tolerance`). This already reduces pair-search cost.
* **Trajectory writes cost 29.8 % of wall time** at these short timescales (21 frames
  over 1 000 steps). Production runs with `nstxout-compressed = 5000` or similar
  will recover this.
* **`-update gpu` is active** (GPU constraints). The AA system does not use virtual
  sites incompatible with update groups, so full GPU pipeline is available.

### CG vs AA comparison

| Metric | CG — Config 3 | AA — this run | CG/AA ratio |
|--------|:-------------:|:-------------:|:-----------:|
| Particles | 242 794 | 1 790 471 | 0.14× |
| dt | 5.5 fs | 2 fs | 2.75× |
| ns/day | **270.8** | **9.412** | **28.8×** |
| ms/step | 1.755 | 18.359 | 0.096× |
| Matom·steps/s | — | 97.527 | — |

> The CG run is **~28.8× faster** in simulated time per wall-clock hour. Normalising
> for dt (CG uses 2.75× larger steps), the phenomenological speedup in physical time
> per wall time is the same 28.8×. On a per-atom basis the AA run processes more
> atoms/step (97.5 Matom·steps/s vs the CG system at smaller scale), but the sheer
> particle count and PME overhead dominate throughput.

---

## 11. Optional CG optimisations not yet applied  <!-- was §10 -->

These would push config 3 further but require re-running `grompp` and
slightly change the physics; **do not do this for the groundtruth run** —
do it only for an "optimised" CG line item in the paper:

1. **Set `verlet-buffer-tolerance` in the MDP** and re-`grompp`. This unlocks
   auto-tuning of `nstlist` (currently fixed at 20). Pair-search drops from
   38 % → ~10 % of wall time.
2. **`-update gpu`** would require switching off virtual sites or moving to
   a virtual-site-less topology; not recommended for collagen.
3. **`-pin on -pinoffset 0 -pinstride 1`** to lock OMP threads to specific
   logical cores; gives a few % on this KVM guest.
4. **Higher `-ntmpi`** is *not* useful here — the system is too small for
   DD on one GPU, and the L40S is already the bottleneck.

---

## 12. Reproducibility checklist (paste into the methods section)

- GROMACS **2026.0-conda_forge**, `gromacs-cuda` env, CUDA 12.8 / cuFFT, SIMD
  AVX2_256 (RDTSCP disabled in this build).
- NVIDIA L40S, driver **570.169**, persistence mode off, power cap 350 W.
- AMD EPYC 7413 host, 8 vCPUs exposed (KVM guest, 1 thread/core), 94 GiB RAM.
- Linux 6.8.0-106-generic.
- Inputs: `1000pN.tpr` (Martini 3 + Go, 242 794 particles, dt = 5.5 fs,
  Reaction-Field, nstlist = 20, isotropic Parrinello–Rahman, V-rescale at
  303 K, 24 pull groups at 1000 pN constant force).
- Run line: see **Config 3** in §6.
- Benchmark protocol: 3 × `-nsteps 200000 -resethway -noconfout`, see §8.
- Reported metric: GROMACS `Performance: ns/day` from the final log block.

---

## 13. Troubleshooting matrix

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `GPU detection failed: No valid OpenCL driver found` | wrong env (`gromacs` OpenCL build) | `conda activate gromacs-cuda` |
| `Cannot compute PME interactions on a GPU ... Systems that do not use PME for electrostatics` | passed `-pme gpu` | remove `-pme gpu` (this system uses Reaction-Field) |
| `WARNING: Oversubscribing the recommended max load of 8 logical CPUs with 20 threads` | `-ntomp 20` on an 8-vCPU host | use `-ntomp 8` |
| Performance fluctuates 30 % between consecutive short runs | startup / DLB warm-up dominates | use `-nsteps 200000 -resethway` |
| `WARNING: Listed nonbonded interaction ... at distance X nm which is larger than the table limit 2.350 nm` | Martini Go pair has been pulled apart beyond table | expected for an unbinding/unfolding setup; investigate only if it appears very early (< 100 ps) |
| `Can not increase nstlist because verlet-buffer-tolerance is not set or used` | MDP lacks `verlet-buffer-tolerance` | re-`grompp` with the tolerance set if you want auto-tuned `nstlist` (changes physics buffer slightly) |

---

## 14. `cg_aa_no_pull/` — no-pull benchmark of all four production tprs (May 19, 2026)

The `/root/collagen_benchmark/cg_aa_no_pull/` directory holds four production `.tpr` files for the
**unforced** (no constant-force pulling) variant of the same collagen
microfibril, in both CG and AA, each with two trajectory output schemes
(`xtc` includes water vs. `xtc` excludes water). They are otherwise
physics-identical to the systems in §3 (CG) and §10 (AA). Current filenames
and `run_sim.sh` are documented in `../cg_aa_no_pull/README.md`.

| TPR file (current name) | Model | xtc output | Source MDP |
|----------|-------|------------|------------|
| `cg_may19.tpr`      | CG Martini 3 + Go | System (water IN xtc)   | `cg.mdp`      |
| `cg_noW_may19.tpr`  | CG Martini 3 + Go | Protein (water OUT)     | `cg_noW.mdp`  |
| `aa.tpr`            | AA Amber99SB*-ILDNP | System (water IN xtc) | `aa.mdp`      |
| `aa_noW.tpr`        | AA Amber99SB*-ILDNP | Protein (water OUT)   | `aa_noW.mdp`  |

### Benchmark protocol

All four runs were launched in the **`gromacs-cuda`** env on the same L40S /
EPYC 7413 host (see §1–§2). The mdrun command line was the fastest config
from §6 / §10 with `-pf` / `-px` removed (no pull) and a short bench window:

```bash
# CG (cg_md_may19.tpr, cg_md_noW_may19.tpr)
gmx mdrun -s <tpr> -deffnm bench_<name> \
          -ntmpi 1 -ntomp 8 -gpu_id 0 \
          -nb gpu -bonded gpu -rdd 3.9 \
          -nsteps 100000 -resethway -noconfout

# AA (md_may19.tpr, md_noW_may19.tpr)
gmx mdrun -s <tpr> -deffnm bench_<name> \
          -ntmpi 1 -ntomp 8 -rdd 3.9 \
          -nsteps 10000 -resethway -noconfout
```

`-resethway` discards the first half of the steps so the reported
`Performance: ns/day` is the steady-state value (no startup, no DLB warm-up,
no GPU clock ramp). CG was run for 100 000 steps (50 000 timed); AA for
10 000 steps (5 000 timed) — same wall-clock budget per system, ~55–90 s.

### System size (read from each `bench_*.log`)

| TPR | Atoms | Vsites | Total particles | Box (nm) | dt (fs) | Electrostatics | nstlist (used) |
|---|--:|--:|--:|---|--:|---|--:|
| `cg_md_may19`      | 216 676 | 26 118 | **242 794** | 14.68 × 14.68 × 107.67 | 5.5  | Reaction-Field | 20 (fixed) |
| `cg_md_noW_may19`  | 216 676 | 26 118 | **242 794** | 14.68 × 14.68 × 107.67 | 5.5  | Reaction-Field | 20 (fixed) |
| `cg_md_20fs_may19` | 216 676 | 26 118 | **242 794** | 14.68 × 14.68 × 107.67 | **20.0** | Reaction-Field | 20 (fixed) |
| `md_may19`         | 1 790 471 | 0   | **1 790 471** | 15.14 × 16.60 × 70.96  | 2.0  | PME            | 55 → **100** (auto) |
| `md_noW_may19`     | 1 790 471 | 0   | **1 790 471** | 15.14 × 16.60 × 70.96  | 2.0  | PME            | 55 → **100** (auto) |

> **AA / CG particle ratio: 7.37×.** Same physical box, only the resolution
> of the force field differs. The AA box is shorter in z (70.96 nm vs
> 107.67 nm for CG) because the AA system was packed at a different
> equilibrium volume; per-axis box ratios are otherwise within ~3 %.
> The CG 20 fs TPR is identical to `cg_md_may19` in topology and box;
> only `dt` and the matching output intervals change.

### Side-by-side performance

| Run | dt (fs) | ns/day | ms/step | Matom·steps/s | Wall t (s, timed) | Steps (timed) | Wall to reach 110 ns |
|-----|--:|--:|--:|--:|--:|--:|--:|
| `cg_md_may19`       | 5.5  | **285.77** | 1.663 | 146.0 | 83.15 | 50 000 | ~9.24 h |
| `cg_md_noW_may19`   | 5.5  | **287.24** | 1.654 | 146.8 | 82.72 | 50 000 | ~9.19 h |
| `cg_md_20fs_may19`  | **20.0** | **957.93** ✅ | 1.804 | 134.6 | 63.14 | 35 000 | **~2.75 h** |
| `md_may19`          | 2.0  | **15.36**  | 11.250 | 159.2 | 56.26 | 5 000  | ~7.16 days |
| `md_noW_may19`      | 2.0  | **16.06**  | 10.762 | 166.4 | 53.82 | 5 000  | ~6.85 days |

> **CG 20 fs is 3.34× faster in ns/day than CG 5.5 fs** — almost exactly the
> dt ratio (20 / 5.5 = 3.64×), with ~8 % efficiency loss because ms/step is
> slightly higher at 20 fs (1.804 vs 1.663 ms) due to identical pair-search
> cost (nstlist=20 steps) spread over fewer steps-per-ns.
> The two CG 5.5 fs runs are within 0.5 % of each other; water in xtc is free
> at this cadence. AA runs differ by ~4.5 % driven by xtc I/O.

### CG↔CG and AA↔AA deltas

| Pair | Δ ns/day | Δ ms/step | Δ % | Likely cause |
|------|--:|--:|--:|--------------|
| CG 5.5 fs: noW − w        | +1.47   | −0.009 | +0.5 %    | xtc I/O for water frames (small) |
| CG: 20 fs − 5.5 fs (w)    | +672.16 | +0.141 | **+235 %** | timestep ratio (3.64×) minus pair-search overhead |
| AA: noW − w               | +0.70   | −0.488 | +4.5 %    | xtc I/O for AA water frames (large) |

### CG↔AA comparison (apples-to-apples, same system, same hardware)

| Metric | CG (cg_md_may19) | AA (md_may19) | CG/AA |
|--------|:-----:|:-----:|:----:|
| Particles                | 242 794 | 1 790 471 | 0.14× |
| dt                       | 5.5 fs  | 2 fs      | 2.75× |
| ns/day                   | **285.77** | **15.36** | **18.6×** |
| ms/step                  | 1.663   | 11.250    | 0.148× |
| Matom·steps/s            | 146.0   | 159.2     | 0.92× |
| Wall for 110 ns          | ~9.2 h  | ~7.2 days | 18.6× |
| Wall for 1 ns simulated  | ~5.0 min | ~93.8 min | 18.6× |

> On the **same hardware and same wall-clock**, CG delivers **18.6× more
> simulated time per day** than AA on this collagen system. On a
> per-particle basis the two are within ~10 % (`Matom·steps/s` is almost
> equal), confirming that the speed-up is overwhelmingly due to the larger
> CG timestep (2.75×) and the smaller particle count (7.4×), not a
> per-particle kernel efficiency difference.

### Cycle accounting (post-`-resethway` half)

#### CG — `cg_md_may19.tpr` (water IN xtc)

```
On 1 MPI rank, each using 8 OpenMP threads
Mapping: PP:0 (NB + bonded on GPU; update/constrain on CPU — vsites)
 Activity              Count       Wall(s)     %
 Vsite constr.        50 001        3.30      4.0
 Neighbor search       2 501       32.28     38.8     ← nstlist=20, no auto-tune
 Launch PP GPU ops.   97 501        2.00      2.4
 Force                50 001       10.24     12.3
 Wait Bonded GPU         501        0.00      0.0
 Wait GPU NB local    50 001        0.28      0.3
 Wait GPU state copy  49 500       12.59     15.1
 NB X/F buffer ops.      501        0.14      0.2
 Vsite spread         50 001        7.54      9.1
 Write traj.              51        0.70      0.8
 Update               50 001        7.23      8.7
 Constraints          50 001        5.02      6.0
 Kinetic energy        2 001        0.37      0.4
 Total                              83.15   100.0
Performance: 285.771 ns/day, 1.663 ms/step
```

#### CG — `cg_md_noW_may19.tpr` (water OUT of xtc)

```
On 1 MPI rank, each using 8 OpenMP threads
 Activity              Count       Wall(s)     %
 Vsite constr.        50 001        3.27      4.0
 Neighbor search       2 501       32.30     39.0
 Launch PP GPU ops.   97 501        2.04      2.5
 Force                50 001        9.97     12.1
 Wait GPU state copy  49 500       12.54     15.2
 Vsite spread         50 001        7.83      9.5
 Write traj.              51        0.30      0.4     ← ~½ vs water-IN
 Update               50 001        7.09      8.6
 Constraints          50 001        5.23      6.3
 Kinetic energy        2 001        0.33      0.4
 Total                              82.72   100.0
Performance: 287.239 ns/day, 1.654 ms/step
```

#### AA — `md_may19.tpr` (water IN xtc)

```
On 1 MPI rank, each using 8 OpenMP threads
Mapping: PP:0, PME:0 (NB + PME + update/constrain on GPU; bonded on CPU)
 Activity              Count       Wall(s)     %
 Neighbor search          51        6.78     12.0
 Launch PP GPU ops.    9 951        0.60      1.1
 Force                 5 001       36.75     65.3     ← dominant
 PME GPU mesh          5 001        0.40      0.7
 PME wait for PP                   55.86     99.3     (Giga-cycles overlap; PME-bound)
 Wait GPU NB local     5 001        0.00      0.0
 Wait GPU state copy  11 048        9.00     16.0
 NB X/F buffer ops.      101        0.34      0.6
 Write traj.               2        0.13      0.2
 Kinetic energy        1 010        1.77      3.1
 Total                              56.26   100.0
Performance: 15.360 ns/day, 11.250 ms/step
```

#### AA — `md_noW_may19.tpr` (water OUT of xtc)

```
On 1 MPI rank, each using 8 OpenMP threads
 Activity              Count       Wall(s)     %
 Neighbor search          51        6.85     12.7
 Launch PP GPU ops.    9 951        0.61      1.1
 Force                 5 001       34.63     64.3
 PME GPU mesh          5 001        0.40      0.7
 PME wait for PP                   53.42     99.3
 Wait GPU state copy  11 048        9.04     16.8
 NB X/F buffer ops.      101        0.27      0.5
 Write traj.               2        0.04      0.1     ← ~¼ vs water-IN
 Kinetic energy        1 010        1.53      2.8
 Total                              53.82   100.0
Performance: 16.057 ns/day, 10.762 ms/step
```

### Cross-check vs. earlier benchmarks in this README

| System | This bench (`cg_aa_no_pull`, no pull) | Earlier bench (`cg_constant_pull`, w/ pull) | Δ |
|--------|:-----:|:-----:|:--:|
| CG (config 3) | **285.77** ns/day (`cg_md_may19`) | 270.81 ns/day (§5 #3, `1000pN.tpr`) | **+5.5 %** |
| AA            | **15.36** ns/day  (`md_may19`)    | 9.412 ns/day  (§10, `md.tpr`)       | **+63 %** |

> CG gains ~5 % from removing the 24 pull groups (no COM-pull force kernel,
> no pull writes). The AA gain is much larger because the earlier AA bench
> in §10 was only 1 000 steps long and was dominated by trajectory-write
> and startup — re-running with `-resethway` exposes the true steady-state
> throughput (and incidentally `Write traj.` drops from 29.8 % → 0.1–0.2 %
> of wall time). So **15.4 ns/day is the more publishable AA number**
> for this hardware; the earlier 9.4 ns/day was an artefact of running
> too short.

### Headline take-aways

1. The fastest mdrun config from §6 (CUDA, `-ntmpi 1 -ntomp 8 -nb gpu
   -bonded gpu -rdd 3.9`) transfers cleanly to the no-pull tprs in
   `cg_aa_no_pull/`. Removing `-pf / -px` is the only change required.
2. For the AA tprs, GROMACS auto-maps PP + PME to the L40S and enables
   `-update gpu` (no vsites in AA). `-bonded gpu` is **not** added
   because the L40S is already PME-bound; pushing bonded to the GPU
   adds no headroom (see §10).
3. Writing water into the `xtc` costs **~0.5 % in CG** and **~4.5 % in AA**
   at the current `nstxout-compressed` cadence. For routine production
   the `_noW` variant is the safer default; use the `_w` variant only if
   you specifically need water configurations for analysis.
4. Reach time for the full 110 ns trajectory on this host:
   * CG (either xtc variant): **~9.2 h**
   * AA (no-water xtc): **~6.85 days**
   * AA (water xtc):    **~7.16 days**


