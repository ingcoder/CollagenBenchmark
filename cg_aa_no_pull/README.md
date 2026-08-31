# Unforced CG vs all-atom collagen (no pull)

This directory is the **no-pull** counterpart of `../cg_constant_pull/`.
Same collagen microfibril, two resolutions (Martini 3 + Go CG, and all-atom),
**no constant-force pulling**. `-pf` / `-px` are not used.

`gmx grompp` has already been run. Start from the `.tpr` files with
`run_sim.sh` (or the copy-paste commands below). Use the **`gromacs-cuda`**
env on this host; the `gromacs` (OpenCL) env cannot see the L40S and falls
back to CPU.

Working directory: `/root/collagen_benchmark/cg_aa_no_pull`

---

## 1. What each file is

`md` in a filename means molecular dynamics, **not** all-atom. All-atom
inputs start with `aa`. Coarse-grained inputs start with `cg`.

| File | Model | xtc contents | Source MDP |
|------|--------|--------------|------------|
| `cg_may19.tpr` | CG Martini 3 + Go, **dt = 5.5 fs** | System (water **in**) | `cg.mdp` |
| `cg_noW_may19.tpr` | CG Martini 3 + Go, dt = 5.5 fs | Protein (water **out**) | `cg_noW.mdp` |
| `aa.tpr` | All-atom Amber99SB*-ILDNP, **dt = 2 fs** | System (water **in**) | `aa.mdp` |
| `aa_noW.tpr` | All-atom, dt = 2 fs | Protein (water **out**) | `aa_noW.mdp` |
| `cg_20fs.tpr` | CG, **dt = 20 fs** (experimental) | System (water in) | `cg_20fs.mdp` |

`noW` only changes what is **written** to the trajectory. Water is still in
the simulation.

`outputs/` holds the archived `mdrun` benchmark and reproducibility logs.
Large trajectories, energy files, terminal captures, and the 20 fs crash PDBs
were removed after their relevant results were recorded. The retained logs
still use the old names (`bench_cg_md_may19`, `bench_md_may19`, …).

```
cg_may19.tpr / cg_noW_may19.tpr / cg_20fs.tpr   # CG inputs
aa.tpr / aa_noW.tpr                             # all-atom inputs
*.mdp                                           # sources used to build the TPRs
run_sim.sh                                      # launcher (this folder)
outputs/                                        # previous mdrun output
```

---

## 2. mdrun configs (use these)

Same hardware as `cg_constant_pull` (L40S, EPYC 7413, GROMACS 2026.0 CUDA).
CG uses **config 3** from that folder (fastest pull run), with `-pf` / `-px`
removed. AA does **not** add `-bonded gpu` — the L40S is already PME-bound.

| `run_sim.sh` target | TPR | Threads | GPU offload | Bench steps |
|---------------------|-----|---------|-------------|-------------|
| `cg` | `cg_may19.tpr` | 1 MPI × **8** OpenMP | `-nb gpu -bonded gpu` | 100 000 |
| `cg_now` | `cg_noW_may19.tpr` | 1 × 8 | `-nb gpu -bonded gpu` | 100 000 |
| `aa` | `aa.tpr` | 1 × 8 | auto (PP + PME on GPU; no `-bonded gpu`) | 10 000 |
| `aa_now` | `aa_noW.tpr` | 1 × 8 | same as `aa` | 10 000 |
| `cg_20fs` | `cg_20fs.tpr` | 1 × 8 | `-nb gpu -bonded gpu` | 100 000 |

Do **not** pass `-pme gpu` on the CG runs (Reaction-Field, not PME).

Bench mode uses `-resethway -noconfout` so `Performance: ns/day` is
steady-state (first half of steps discarded). Production mode runs the
full TPR with `-maxh 24`.

### CG (copy-paste)

```bash
source /root/miniconda3/etc/profile.d/conda.sh
conda activate gromacs-cuda
cd /root/collagen_benchmark/cg_aa_no_pull

gmx mdrun -v -s cg_may19.tpr -deffnm outputs/bench_cg \
          -ntmpi 1 -ntomp 8 -gpu_id 0 \
          -nb gpu -bonded gpu -rdd 3.9 \
          -nsteps 100000 -resethway -noconfout
```

### All-atom (copy-paste)

```bash
conda activate gromacs-cuda
cd /root/collagen_benchmark/cg_aa_no_pull

gmx mdrun -v -s aa.tpr -deffnm outputs/bench_aa \
          -ntmpi 1 -ntomp 8 -rdd 3.9 \
          -nsteps 10000 -resethway -noconfout
```

### `run_sim.sh`

```bash
cd /root/collagen_benchmark/cg_aa_no_pull
./run_sim.sh            # all four production TPRs (short benches)
./run_sim.sh cg
./run_sim.sh cg_now
./run_sim.sh aa
./run_sim.sh aa_now

MODE=production ./run_sim.sh cg   # full no-pull CG production
```

---

## 3. System size

| TPR | Particles | Box (nm) | dt | Electrostatics |
|-----|----------:|----------|---:|----------------|
| `cg_may19` / `cg_noW_may19` | **242 794** (216 676 beads + 26 118 vsites) | 14.68 × 14.68 × 107.67 | 5.5 fs | Reaction-Field |
| `cg_20fs` | same as CG 5.5 fs | same | **20 fs** | Reaction-Field |
| `aa` / `aa_noW` | **1 790 471** | 15.14 × 16.60 × 70.96 | 2 fs | PME |

AA / CG particle ratio is **7.37×**. The AA box is shorter in z because it
was packed at a different equilibrium volume.

---

## 4. Measured throughput (May 2026, L40S)

| Run (archived name) | dt (fs) | ns/day | ms/step | Wall for 110 ns |
|---------------------|--------:|-------:|--------:|-----------------|
| CG water-in (`bench_cg_md_may19`) | 5.5 | **285.77** | 1.663 | ~9.24 h |
| CG water-out (`bench_cg_md_noW_may19`) | 5.5 | **287.24** | 1.654 | ~9.19 h |
| CG 20 fs (`bench_cg_md_20fs_v2`) | 20.0 | **957.93** | 1.804 | ~2.75 h |
| AA water-in (`bench_md_may19`) | 2.0 | **15.36** | 11.250 | ~7.16 days |
| AA water-out (`bench_md_noW_may19`) | 2.0 | **16.06** | 10.762 | ~6.85 days |

CG is **~18.6×** faster than AA in ns/day on this hardware (same wall clock,
same microfibril). Writing water into the xtc costs ~0.5 % in CG and ~4.5 %
in AA. No-pull CG is ~5 % faster than the 1000 pN pull run in
`cg_constant_pull` (285.8 vs 270.8 ns/day).

The 20 fs CG TPR is **not** production-ready: the first attempt died with
LINCS constraint errors (`outputs/step7847*.pdb`). A shortened retry
finished the bench window; treat 20 fs as exploratory.

---

## 5. Reproducibility sweeps in `outputs/`

These re-ran `cg_noW_may19.tpr` with the pull-folder thread/GPU matrix:

| Output | Settings | Role |
|--------|----------|------|
| `repro_noW_cfg2` | 20 OpenMP, `-nb gpu` only | oversubscribed (slow) |
| `repro_noW_cfg3` | 8 OpenMP, `-nb gpu -bonded gpu` | **fast config** |
| `repro_noW_cfg_mid` | 8 OpenMP, `-nb gpu` only | mid |
