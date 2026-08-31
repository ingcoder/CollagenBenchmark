#!/bin/bash
# No-pull CG / AA runner (cg_aa_no_pull).
# Same GROMACS flags as cg_constant_pull config 3, without -pf / -px.
#
# Usage:
#   ./run_sim.sh              # short benches of all four production TPRs
#   ./run_sim.sh cg           # CG, water in xtc
#   ./run_sim.sh cg_now       # CG, water out of xtc
#   ./run_sim.sh aa           # all-atom, water in xtc
#   ./run_sim.sh aa_now       # all-atom, water out of xtc
#   ./run_sim.sh cg_20fs      # experimental 20 fs CG (previously crashed)
#
#   MODE=production ./run_sim.sh cg
#       full TPR length, no -resethway (hours, not a 90 s bench)

set -euo pipefail

source /root/miniconda3/etc/profile.d/conda.sh
conda activate gromacs-cuda

ROOT=/root/collagen_benchmark/cg_aa_no_pull
OUT="$ROOT/outputs"
MODE="${MODE:-bench}"   # bench | production
TARGET="${1:-all}"

cd "$ROOT"
mkdir -p "$OUT"

run_cg() {
  local tpr="$1" deffnm="$2"
  local extra=()
  if [[ "$MODE" == bench ]]; then
    extra=(-nsteps 100000 -resethway -noconfout)
  else
    extra=(-maxh 24)
  fi
  gmx mdrun -v -s "$tpr" -deffnm "$OUT/$deffnm" \
            -ntmpi 1 -ntomp 8 -gpu_id 0 \
            -nb gpu -bonded gpu -rdd 3.9 \
            "${extra[@]}"
}

run_aa() {
  local tpr="$1" deffnm="$2"
  local extra=()
  if [[ "$MODE" == bench ]]; then
    extra=(-nsteps 10000 -resethway -noconfout)
  else
    extra=(-maxh 24)
  fi
  gmx mdrun -v -s "$tpr" -deffnm "$OUT/$deffnm" \
            -ntmpi 1 -ntomp 8 -rdd 3.9 \
            "${extra[@]}"
}

case "$TARGET" in
  all)
    run_cg cg_may19.tpr     bench_cg
    run_cg cg_noW_may19.tpr bench_cg_noW
    run_aa aa.tpr           bench_aa
    run_aa aa_noW.tpr       bench_aa_noW
    ;;
  cg)      run_cg cg_may19.tpr     bench_cg ;;
  cg_now)  run_cg cg_noW_may19.tpr bench_cg_noW ;;
  aa)      run_aa aa.tpr           bench_aa ;;
  aa_now)  run_aa aa_noW.tpr       bench_aa_noW ;;
  cg_20fs)
    # Same GPU flags as CG 5.5 fs. First attempt hit LINCS errors (see outputs/step7847*.pdb).
    run_cg cg_20fs.tpr bench_cg_20fs
    ;;
  *)
    echo "Unknown target: $TARGET" >&2
    echo "Usage: $0 [all|cg|cg_now|aa|aa_now|cg_20fs]" >&2
    exit 1
    ;;
esac
